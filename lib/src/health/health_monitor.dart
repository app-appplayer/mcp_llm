import 'dart:async';
import '../utils/logger.dart';
import '../adapter/mcp_auth_adapter.dart';
import '../core/models.dart';

/// Health check configuration (using models from core/models.dart)
class HealthCheckConfig {
  final Duration timeout;
  final int maxRetries;
  final Duration retryDelay;
  final bool includeSystemMetrics;
  final bool checkAuthentication;
  final List<String> excludeComponents;

  const HealthCheckConfig({
    this.timeout = const Duration(seconds: 5),
    this.maxRetries = 2,
    this.retryDelay = const Duration(milliseconds: 500),
    this.includeSystemMetrics = true,
    this.checkAuthentication = true,
    this.excludeComponents = const [],
  });
}

/// MCP Health Monitor for 2025-03-26 health/check methods
class McpHealthMonitor {
  final HealthCheckConfig config;
  final Logger _logger = Logger('mcp_llm.health_monitor');
  
  final Map<String, dynamic> _mcpClients = {};
  final Map<String, McpAuthAdapter?> _authAdapters = {};
  final Map<String, HealthCheckResult> _lastResults = {};
  
  // Health check history for trending
  final Map<String, List<HealthCheckResult>> _healthHistory = {};
  final int _maxHistorySize = 50;

  McpHealthMonitor({
    this.config = const HealthCheckConfig(),
  });

  /// Register MCP client for health monitoring
  void registerClient(String clientId, dynamic mcpClient, {McpAuthAdapter? authAdapter}) {
    _mcpClients[clientId] = mcpClient;
    _authAdapters[clientId] = authAdapter;
    _healthHistory[clientId] = [];
    _logger.info('Registered MCP client for health monitoring: $clientId');
  }

  /// Unregister MCP client
  void unregisterClient(String clientId) {
    _mcpClients.remove(clientId);
    _authAdapters.remove(clientId);
    _lastResults.remove(clientId);
    _healthHistory.remove(clientId);
    _logger.info('Unregistered MCP client from health monitoring: $clientId');
  }

  /// Perform comprehensive health check on all registered clients
  Future<HealthReport> performHealthCheck({
    List<String>? clientIds,
    bool includeSystemMetrics = true,
  }) async {
    final startTime = DateTime.now();
    final effectiveClientIds = clientIds ?? _mcpClients.keys.toList();
    final resultsMap = <String, HealthCheckResult>{};

    _logger.info('Starting health check for ${effectiveClientIds.length} MCP clients');

    // Perform health checks in parallel for better performance
    final futures = effectiveClientIds.map((clientId) => 
      _performClientHealthCheck(clientId)
    ).toList();

    final clientResults = await Future.wait(futures);
    
    // Build results map
    for (int i = 0; i < effectiveClientIds.length; i++) {
      resultsMap[effectiveClientIds[i]] = clientResults[i];
    }

    // Add system-level health checks if requested
    if (includeSystemMetrics) {
      final systemResult = await _performSystemHealthCheck();
      resultsMap['system'] = systemResult;
    }

    // Calculate overall status
    final overallStatus = _calculateOverallStatus(resultsMap.values.toList());
    final totalCheckTime = DateTime.now().difference(startTime);

    final report = HealthReport(
      overallStatus: overallStatus,
      componentResults: resultsMap,
      timestamp: DateTime.now(),
      totalCheckTime: totalCheckTime,
    );

    _logger.info('Health check completed in ${totalCheckTime.inMilliseconds}ms - Overall status: ${overallStatus.name}');
    return report;
  }

  /// Perform health check on a specific MCP client
  Future<HealthCheckResult> _performClientHealthCheck(String clientId) async {
    if (config.excludeComponents.contains(clientId)) {
      return HealthCheckResult(
        clientId: clientId,
        status: HealthStatus.unknown,
        metrics: {},
        error: 'Component excluded from health checks',
        timestamp: DateTime.now(),
      );
    }

    final mcpClient = _mcpClients[clientId];
    if (mcpClient == null) {
      return HealthCheckResult(
        clientId: clientId,
        status: HealthStatus.unhealthy,
        metrics: {},
        error: 'MCP client not found',
        timestamp: DateTime.now(),
      );
    }

    final startTime = DateTime.now();
    
    for (int attempt = 0; attempt <= config.maxRetries; attempt++) {
      try {
        // Check basic connectivity
        await _checkClientConnectivity(clientId, mcpClient);
        
        // Check authentication if enabled
        if (config.checkAuthentication) {
          await _checkClientAuthentication(clientId);
        }
        
        // Check client capabilities
        final capabilities = await _checkClientCapabilities(clientId, mcpClient);
        
        final responseTime = DateTime.now().difference(startTime);
        final result = HealthCheckResult(
          clientId: clientId,
          status: HealthStatus.healthy,
          metrics: {
            'capabilities': capabilities,
            'attempt': attempt + 1,
            'authenticated': _authAdapters[clientId]?.hasValidAuth(clientId) ?? false,
            'responseTimeMs': responseTime.inMilliseconds,
          },
          timestamp: DateTime.now(),
        );

        _updateHealthHistory(clientId, result);
        _lastResults[clientId] = result;
        return result;

      } catch (e) {
        _logger.warning('Health check attempt ${attempt + 1} failed for $clientId: $e');
        
        if (attempt < config.maxRetries) {
          await Future.delayed(config.retryDelay);
          continue;
        }
        
        // Final attempt failed
        final responseTime = DateTime.now().difference(startTime);
        final result = HealthCheckResult(
          clientId: clientId,
          status: HealthStatus.unhealthy,
          metrics: {
            'attempts': attempt + 1,
            'responseTimeMs': responseTime.inMilliseconds,
          },
          error: 'Health check failed: $e',
          timestamp: DateTime.now(),
        );

        _updateHealthHistory(clientId, result);
        _lastResults[clientId] = result;
        return result;
      }
    }

    // Should not reach here, but provide fallback
    return HealthCheckResult(
      clientId: clientId,
      status: HealthStatus.unknown,
      metrics: {},
      error: 'Unexpected health check state',
      timestamp: DateTime.now(),
    );
  }

  /// Check basic connectivity to MCP client
  Future<void> _checkClientConnectivity(String clientId, dynamic mcpClient) async {
    // Try to list tools as a basic connectivity test
    await mcpClient.listTools().timeout(config.timeout);
  }

  /// Check authentication status if applicable
  Future<void> _checkClientAuthentication(String clientId) async {
    final authAdapter = _authAdapters[clientId];
    if (authAdapter == null) return; // No auth required

    if (!authAdapter.hasValidAuth(clientId)) {
      throw Exception('Authentication invalid or expired');
    }

    // Check OAuth 2.1 compliance for 2025-03-26
    final mcpClient = _mcpClients[clientId];
    if (mcpClient != null) {
      final isCompliant = await authAdapter.checkOAuth21Compliance(mcpClient);
      if (!isCompliant) {
        throw Exception('OAuth 2.1 compliance check failed');
      }
    }
  }

  /// Check client capabilities and supported methods
  Future<Map<String, dynamic>> _checkClientCapabilities(String clientId, dynamic mcpClient) async {
    final capabilities = <String, dynamic>{
      'tools': false,
      'prompts': false,
      'resources': false,
      'health_check': false,
      'batch_processing': false,
    };

    try {
      // Check tools capability
      final tools = await mcpClient.listTools().timeout(config.timeout);
      capabilities['tools'] = true;
      capabilities['tool_count'] = tools.length;
    } catch (e) {
      _logger.debug('Tools not supported by $clientId: $e');
    }

    try {
      // Check prompts capability
      final prompts = await mcpClient.listPrompts().timeout(config.timeout);
      capabilities['prompts'] = true;
      capabilities['prompt_count'] = prompts.length;
    } catch (e) {
      _logger.debug('Prompts not supported by $clientId: $e');
    }

    try {
      // Check resources capability
      final resources = await mcpClient.listResources().timeout(config.timeout);
      capabilities['resources'] = true;
      capabilities['resource_count'] = resources.length;
    } catch (e) {
      _logger.debug('Resources not supported by $clientId: $e');
    }

    // Check for 2025-03-26 specific capabilities
    try {
      // Check health endpoint (2025-03-26)
      if (mcpClient.toString().contains('health') || 
          mcpClient.runtimeType.toString().contains('Health')) {
        capabilities['health_check'] = true;
      }
    } catch (e) {
      _logger.debug('Health check not supported by $clientId: $e');
    }

    try {
      // Check batch processing support (2025-03-26)
      if (mcpClient.toString().contains('batch') || 
          mcpClient.runtimeType.toString().contains('Batch')) {
        capabilities['batch_processing'] = true;
      }
    } catch (e) {
      _logger.debug('Batch processing not supported by $clientId: $e');
    }

    return capabilities;
  }

  /// Perform system-level health check
  Future<HealthCheckResult> _performSystemHealthCheck() async {
    final startTime = DateTime.now();
    
    try {
      final systemStatus = <String, dynamic>{
        'registered_clients': _mcpClients.length,
        'healthy_clients': _lastResults.values.where((r) => r.status == HealthStatus.healthy).length,
        'memory_usage': _getMemoryUsage(),
        'uptime': _getUptime(),
      };

      final responseTime = DateTime.now().difference(startTime);
      
      return HealthCheckResult(
        clientId: 'system',
        status: HealthStatus.healthy,
        metrics: {
          ...systemStatus,
          'responseTimeMs': responseTime.inMilliseconds,
        },
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return HealthCheckResult(
        clientId: 'system',
        status: HealthStatus.unhealthy,
        metrics: {},
        error: 'System health check failed: $e',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Calculate overall health status from component results
  HealthStatus _calculateOverallStatus(List<HealthCheckResult> results) {
    if (results.isEmpty) return HealthStatus.unknown;
    
    final hasUnhealthy = results.any((r) => r.status == HealthStatus.unhealthy);
    if (hasUnhealthy) return HealthStatus.unhealthy;
    
    final hasDegraded = results.any((r) => r.status == HealthStatus.degraded);
    if (hasDegraded) return HealthStatus.degraded;
    
    final hasUnknown = results.any((r) => r.status == HealthStatus.unknown);
    if (hasUnknown) return HealthStatus.degraded; // Treat unknown as degraded
    
    return HealthStatus.healthy;
  }

  /// Update health history for trending analysis
  void _updateHealthHistory(String clientId, HealthCheckResult result) {
    final history = _healthHistory[clientId];
    if (history != null) {
      history.add(result);
      
      // Keep only the most recent results
      if (history.length > _maxHistorySize) {
        history.removeAt(0);
      }
    }
  }


  /// Get memory usage (simplified for demo)
  double _getMemoryUsage() {
    // In a real implementation, you'd use dart:io ProcessInfo
    return 128.5; // MB
  }

  /// Get system uptime (simplified for demo)
  int _getUptime() {
    // In a real implementation, you'd track actual uptime
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  /// Get health status for specific client
  HealthCheckResult? getClientHealth(String clientId) {
    return _lastResults[clientId];
  }

  /// Get health history for trending analysis
  List<HealthCheckResult> getClientHealthHistory(String clientId) {
    return List.unmodifiable(_healthHistory[clientId] ?? []);
  }

  /// Check if all clients are healthy
  bool get allClientsHealthy {
    return _lastResults.values.every((result) => result.status == HealthStatus.healthy);
  }

  /// Get list of unhealthy clients
  List<String> get unhealthyClients {
    return _lastResults.entries
        .where((entry) => entry.value.status != HealthStatus.healthy)
        .map((entry) => entry.key)
        .toList();
  }

  /// Get health statistics
  Map<String, dynamic> getHealthStatistics() {
    final allResults = _lastResults.values.toList();
    
    return {
      'total_clients': _mcpClients.length,
      'healthy': allResults.where((r) => r.status == HealthStatus.healthy).length,
      'degraded': allResults.where((r) => r.status == HealthStatus.degraded).length,
      'unhealthy': allResults.where((r) => r.status == HealthStatus.unhealthy).length,
      'unknown': allResults.where((r) => r.status == HealthStatus.unknown).length,
      'average_response_time': _calculateAverageResponseTime(allResults),
      'last_check': allResults.isNotEmpty 
          ? allResults.map((r) => r.timestamp).reduce((a, b) => a.isAfter(b) ? a : b).toIso8601String()
          : null,
    };
  }

  /// Calculate average response time
  double _calculateAverageResponseTime(List<HealthCheckResult> results) {
    final validTimes = results
        .where((r) => r.metrics.containsKey('responseTimeMs'))
        .map((r) => r.metrics['responseTimeMs'] as int)
        .toList();
    
    if (validTimes.isEmpty) return 0.0;
    
    return validTimes.reduce((a, b) => a + b) / validTimes.length;
  }

  /// Dispose of health monitor resources
  void dispose() {
    _mcpClients.clear();
    _authAdapters.clear();
    _lastResults.clear();
    _healthHistory.clear();
    _logger.info('Health monitor disposed');
  }
}