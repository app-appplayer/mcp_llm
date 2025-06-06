import 'dart:async';
import '../utils/logger.dart';
import '../adapter/mcp_auth_adapter.dart';

/// Batch request configuration for JSON-RPC 2.0 optimization
class BatchConfig {
  final int maxBatchSize;
  final Duration batchTimeout;
  final Duration requestTimeout;
  final bool enableRetry;
  final int maxRetries;
  final bool preserveOrder;

  const BatchConfig({
    this.maxBatchSize = 10,
    this.batchTimeout = const Duration(milliseconds: 100),
    this.requestTimeout = const Duration(seconds: 30),
    this.enableRetry = true,
    this.maxRetries = 3,
    this.preserveOrder = true,
  });
}

/// Individual request in a batch
class BatchRequest {
  final String id;
  final String method;
  final Map<String, dynamic> params;
  final String? clientId;
  final DateTime createdAt;
  final Completer<Map<String, dynamic>> completer;

  BatchRequest({
    required this.id,
    required this.method,
    required this.params,
    this.clientId,
    required this.completer,
  }) : createdAt = DateTime.now();

  /// Convert to JSON-RPC 2.0 format
  Map<String, dynamic> toJsonRpc() {
    return {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };
  }
}

/// Batch response containing multiple results
class BatchResponse {
  final List<Map<String, dynamic>> results;
  final List<String> errors;
  final Duration processingTime;
  final int successCount;
  final int errorCount;

  BatchResponse({
    required this.results,
    required this.errors,
    required this.processingTime,
  }) : successCount = results.where((r) => !r.containsKey('error')).length,
       errorCount = results.where((r) => r.containsKey('error')).length;

  bool get hasErrors => errors.isNotEmpty || errorCount > 0;
  double get successRate => results.isEmpty ? 0.0 : successCount / results.length;
}

/// JSON-RPC 2.0 Batch Processing Manager for 2025-03-26 MCP optimization
class BatchRequestManager {
  final BatchConfig config;
  final Logger _logger = Logger('mcp_llm.batch_request_manager');
  
  final Map<String, List<BatchRequest>> _pendingBatches = {};
  final Map<String, Timer> _batchTimers = {};
  final Map<String, dynamic> _mcpClients = {};
  final Map<String, McpAuthAdapter?> _authAdapters = {};
  
  // Performance metrics
  int _totalRequests = 0;
  int _batchedRequests = 0;
  int _totalBatches = 0;
  Duration _totalProcessingTime = Duration.zero;

  BatchRequestManager({
    this.config = const BatchConfig(),
  });

  /// Register MCP client for batch processing
  void registerClient(String clientId, dynamic mcpClient, {McpAuthAdapter? authAdapter}) {
    _mcpClients[clientId] = mcpClient;
    _authAdapters[clientId] = authAdapter;
    _pendingBatches[clientId] = [];
    _logger.info('Registered MCP client for batch processing: $clientId');
  }

  /// Unregister MCP client
  void unregisterClient(String clientId) {
    // Complete any pending requests with error
    final pending = _pendingBatches[clientId];
    if (pending != null) {
      for (final request in pending) {
        request.completer.complete({
          'error': {'code': -32000, 'message': 'Client unregistered'}
        });
      }
    }
    
    _pendingBatches.remove(clientId);
    _batchTimers[clientId]?.cancel();
    _batchTimers.remove(clientId);
    _mcpClients.remove(clientId);
    _authAdapters.remove(clientId);
    _logger.info('Unregistered MCP client from batch processing: $clientId');
  }

  /// Add request to batch queue for optimal JSON-RPC 2.0 processing
  Future<Map<String, dynamic>> addRequest(
    String method,
    Map<String, dynamic> params, {
    String? clientId,
    bool forceImmediate = false,
  }) async {
    final effectiveClientId = clientId ?? 'default';
    
    if (!_mcpClients.containsKey(effectiveClientId)) {
      throw Exception('MCP client not registered: $effectiveClientId');
    }

    final requestId = _generateRequestId();
    final completer = Completer<Map<String, dynamic>>();
    final request = BatchRequest(
      id: requestId,
      method: method,
      params: params,
      clientId: effectiveClientId,
      completer: completer,
    );

    _totalRequests++;

    // Execute immediately if forced or if batching is disabled
    if (forceImmediate || config.maxBatchSize <= 1) {
      return await _executeImmediateRequest(request);
    }

    // Add to batch queue
    _pendingBatches[effectiveClientId]!.add(request);
    _logger.debug('Added request to batch queue: $method (client: $effectiveClientId)');

    // Check if batch is full
    if (_pendingBatches[effectiveClientId]!.length >= config.maxBatchSize) {
      _logger.debug('Batch size limit reached, executing batch for client: $effectiveClientId');
      _executeBatch(effectiveClientId);
    } else {
      // Start/reset batch timer
      _startBatchTimer(effectiveClientId);
    }

    return await completer.future;
  }

  /// Execute request immediately without batching
  Future<Map<String, dynamic>> _executeImmediateRequest(BatchRequest request) async {
    final clientId = request.clientId!;
    final mcpClient = _mcpClients[clientId];
    final authAdapter = _authAdapters[clientId];

    try {
      // Check authentication if required
      if (authAdapter != null && !authAdapter.hasValidAuth(clientId)) {
        final authResult = await authAdapter.authenticate(clientId, mcpClient);
        if (!authResult.isAuthenticated) {
          return {
            'error': {
              'code': -32001,
              'message': 'OAuth 2.1 authentication failed',
              'data': authResult.error,
            }
          };
        }
      }

      final result = await _executeSingleRequest(mcpClient, request);
      request.completer.complete(result);
      return result;
    } catch (e) {
      final errorResult = {
        'error': {
          'code': -32000,
          'message': 'Request execution failed',
          'data': e.toString(),
        }
      };
      request.completer.complete(errorResult);
      return errorResult;
    }
  }

  /// Start batch timer for delayed execution
  void _startBatchTimer(String clientId) {
    _batchTimers[clientId]?.cancel();
    _batchTimers[clientId] = Timer(config.batchTimeout, () {
      _logger.debug('Batch timeout reached, executing batch for client: $clientId');
      // Execute batch asynchronously but don't wait for it
      _executeBatch(clientId).catchError((e) {
        _logger.error('Error executing timed batch for client $clientId: $e');
      });
    });
  }

  /// Execute batch of requests using JSON-RPC 2.0 batch format
  Future<void> _executeBatch(String clientId) async {
    final requests = List<BatchRequest>.from(_pendingBatches[clientId]!);
    if (requests.isEmpty) return;

    // Clear pending batch
    _pendingBatches[clientId]!.clear();
    _batchTimers[clientId]?.cancel();

    final startTime = DateTime.now();
    _totalBatches++;
    _batchedRequests += requests.length;

    try {
      _logger.info('Executing JSON-RPC 2.0 batch with ${requests.length} requests for client: $clientId');

      final mcpClient = _mcpClients[clientId];
      final authAdapter = _authAdapters[clientId];

      // Check authentication if required
      if (authAdapter != null && !authAdapter.hasValidAuth(clientId)) {
        final authResult = await authAdapter.authenticate(clientId, mcpClient);
        if (!authResult.isAuthenticated) {
          // Complete all requests with auth error
          for (final request in requests) {
            request.completer.complete({
              'error': {
                'code': -32001,
                'message': 'OAuth 2.1 authentication failed',
                'data': authResult.error,
              }
            });
          }
          return;
        }
      }

      // Execute batch request
      final results = await _executeBatchRequest(mcpClient, requests);
      
      // Complete individual request futures
      for (int i = 0; i < requests.length; i++) {
        final result = i < results.length ? results[i] : {
          'error': {'code': -32000, 'message': 'Missing result in batch response'}
        };
        requests[i].completer.complete(result);
      }

      final processingTime = DateTime.now().difference(startTime);
      _totalProcessingTime += processingTime;

      _logger.info('JSON-RPC 2.0 batch completed in ${processingTime.inMilliseconds}ms (${requests.length} requests)');

    } catch (e) {
      _logger.error('Batch execution failed for client $clientId: $e');
      
      // Complete all requests with error
      for (final request in requests) {
        request.completer.complete({
          'error': {
            'code': -32000,
            'message': 'Batch execution failed',
            'data': e.toString(),
          }
        });
      }
    }
  }

  /// Execute batch request on MCP client
  Future<List<Map<String, dynamic>>> _executeBatchRequest(
    dynamic mcpClient,
    List<BatchRequest> requests,
  ) async {
    final results = <Map<String, dynamic>>[];

    // Check if MCP client supports batch processing
    final supportsBatch = _supportsBatchProcessing(mcpClient);
    
    if (supportsBatch) {
      // Use native batch processing if available
      final batchPayload = requests.map((r) => r.toJsonRpc()).toList();
      try {
        final batchResult = await mcpClient.executeBatch(batchPayload);
        if (batchResult is List) {
          return batchResult.cast<Map<String, dynamic>>();
        }
      } catch (e) {
        _logger.warning('Native batch processing failed, falling back to sequential: $e');
      }
    }

    // Fall back to sequential execution with optimization
    if (config.preserveOrder) {
      // Execute in order
      for (final request in requests) {
        try {
          final result = await _executeSingleRequest(mcpClient, request);
          results.add(result);
        } catch (e) {
          results.add({
            'error': {
              'code': -32000,
              'message': 'Request failed',
              'data': e.toString(),
            }
          });
        }
      }
    } else {
      // Execute in parallel for better performance
      final futures = requests.map((request) => 
        _executeSingleRequest(mcpClient, request).catchError((e) => {
          'error': {
            'code': -32000,
            'message': 'Request failed',
            'data': e.toString(),
          }
        })
      ).toList();
      
      results.addAll(await Future.wait(futures));
    }

    return results;
  }

  /// Execute single request on MCP client
  Future<Map<String, dynamic>> _executeSingleRequest(
    dynamic mcpClient,
    BatchRequest request,
  ) async {
    final method = request.method;
    final params = request.params;

    try {
      switch (method) {
        case 'tools/list':
          final tools = await mcpClient.listTools();
          return {'result': tools};
          
        case 'tools/call':
          final toolName = params['name'] as String;
          final arguments = params['arguments'] as Map<String, dynamic>? ?? {};
          final result = await mcpClient.callTool(toolName, arguments);
          return {'result': result};
          
        case 'prompts/list':
          final prompts = await mcpClient.listPrompts();
          return {'result': prompts};
          
        case 'prompts/get':
          final promptName = params['name'] as String;
          final arguments = params['arguments'] as Map<String, dynamic>? ?? {};
          final result = await mcpClient.callPrompt(promptName, arguments);
          return {'result': result};
          
        case 'resources/list':
          final resources = await mcpClient.listResources();
          return {'result': resources};
          
        case 'resources/read':
          final uri = params['uri'] as String;
          final result = await mcpClient.readResource(uri);
          return {'result': result};
          
        default:
          throw Exception('Unsupported method: $method');
      }
    } catch (e) {
      return {
        'error': {
          'code': -32000,
          'message': 'Method execution failed',
          'data': e.toString(),
        }
      };
    }
  }

  /// Check if MCP client supports native batch processing
  bool _supportsBatchProcessing(dynamic mcpClient) {
    try {
      // Check for 2025-03-26 batch method
      return mcpClient != null && 
             mcpClient.toString().contains('executeBatch') ||
             mcpClient.runtimeType.toString().contains('Batch');
    } catch (e) {
      return false;
    }
  }

  /// Generate unique request ID
  String _generateRequestId() {
    return 'batch_${DateTime.now().millisecondsSinceEpoch}_$_totalRequests';
  }

  /// Get batch processing statistics
  Map<String, dynamic> getStatistics() {
    final avgProcessingTime = _totalBatches > 0 
        ? _totalProcessingTime.inMilliseconds / _totalBatches 
        : 0.0;
    
    final batchEfficiency = _totalRequests > 0 
        ? _batchedRequests / _totalRequests 
        : 0.0;

    return {
      'total_requests': _totalRequests,
      'batched_requests': _batchedRequests,
      'total_batches': _totalBatches,
      'avg_processing_time_ms': avgProcessingTime.round(),
      'batch_efficiency': (batchEfficiency * 100).round(),
      'registered_clients': _mcpClients.length,
      'pending_requests': _pendingBatches.values.map((batch) => batch.length).fold(0, (a, b) => a + b),
    };
  }

  /// Clear all pending batches
  Future<void> flush() async {
    final futures = <Future<void>>[];
    
    for (final clientId in _pendingBatches.keys) {
      if (_pendingBatches[clientId]!.isNotEmpty) {
        futures.add(_executeBatch(clientId));
      }
    }
    
    await Future.wait(futures);
    _logger.info('Flushed all pending batches');
  }

  /// Dispose of batch manager resources
  void dispose() {
    // Cancel all timers
    for (final timer in _batchTimers.values) {
      timer.cancel();
    }
    _batchTimers.clear();
    
    // Complete pending requests with error
    for (final requests in _pendingBatches.values) {
      for (final request in requests) {
        request.completer.complete({
          'error': {'code': -32000, 'message': 'Batch manager disposed'}
        });
      }
    }
    _pendingBatches.clear();
    _mcpClients.clear();
    _authAdapters.clear();
    
    _logger.info('Batch request manager disposed');
  }
}