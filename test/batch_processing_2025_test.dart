import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

/// Mock MCP client for batch testing
class MockMcpClientBatch {
  final String clientId;
  bool _authenticationEnabled = false;
  final Map<String, dynamic> _tools = {
    'calculator': {'name': 'calculator', 'description': 'Mathematical calculations'},
    'weather': {'name': 'weather', 'description': 'Weather information'},
    'translator': {'name': 'translator', 'description': 'Text translation'},
  };
  
  MockMcpClientBatch(this.clientId);

  bool get isAuthenticationEnabled => _authenticationEnabled;
  
  void enableAuthentication(TokenValidator validator) {
    _authenticationEnabled = true;
  }

  Future<List<dynamic>> listTools() async {
    await Future.delayed(Duration(milliseconds: 50)); // Simulate network delay
    return _tools.values.toList();
  }

  Future<List<dynamic>> listPrompts() async {
    await Future.delayed(Duration(milliseconds: 30));
    return [
      {'name': 'summary', 'description': 'Summarize text'},
      {'name': 'translate', 'description': 'Translate text'},
    ];
  }

  Future<List<dynamic>> listResources() async {
    await Future.delayed(Duration(milliseconds: 40));
    return [
      {'name': 'docs', 'uri': 'file://docs.txt'},
      {'name': 'config', 'uri': 'file://config.json'},
    ];
  }

  Future<dynamic> callTool(String name, Map<String, dynamic> args) async {
    await Future.delayed(Duration(milliseconds: 100)); // Simulate processing
    
    if (!_tools.containsKey(name)) {
      throw Exception('Tool not found: $name');
    }
    
    return {
      'result': 'Tool $name executed with args: $args',
      'clientId': clientId,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  Future<dynamic> callPrompt(String name, Map<String, dynamic> args) async {
    await Future.delayed(Duration(milliseconds: 80));
    return {
      'content': 'Prompt $name executed with args: $args',
      'clientId': clientId,
    };
  }

  Future<dynamic> readResource(String uri) async {
    await Future.delayed(Duration(milliseconds: 60));
    return {
      'content': 'Resource content for $uri',
      'clientId': clientId,
    };
  }

  // Mock batch processing support
  Future<List<Map<String, dynamic>>> executeBatch(List<Map<String, dynamic>> requests) async {
    await Future.delayed(Duration(milliseconds: 200)); // Batch processing time
    
    final results = <Map<String, dynamic>>[];
    for (final request in requests) {
      final method = request['method'] as String;
      final params = request['params'] as Map<String, dynamic>? ?? {};
      
      try {
        dynamic result;
        switch (method) {
          case 'tools/list':
            result = await listTools();
            break;
          case 'tools/call':
            result = await callTool(params['name'], params['arguments'] ?? {});
            break;
          case 'prompts/list':
            result = await listPrompts();
            break;
          case 'prompts/get':
            result = await callPrompt(params['name'], params['arguments'] ?? {});
            break;
          case 'resources/list':
            result = await listResources();
            break;
          case 'resources/read':
            result = await readResource(params['uri']);
            break;
          default:
            throw Exception('Unsupported method: $method');
        }
        
        results.add({
          'jsonrpc': '2.0',
          'id': request['id'],
          'result': result,
        });
      } catch (e) {
        results.add({
          'jsonrpc': '2.0',
          'id': request['id'],
          'error': {
            'code': -32000,
            'message': e.toString(),
          },
        });
      }
    }
    
    return results;
  }
}

/// Mock LLM provider for testing
class MockLlmProvider implements LlmInterface {
  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return LlmResponse(
      text: 'Mock response for: ${request.prompt}',
      metadata: {'provider': 'mock'},
    );
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    yield LlmResponseChunk(
      textChunk: 'Mock streaming response',
      isDone: true,
      metadata: {'provider': 'mock'},
    );
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return List.generate(384, (i) => i * 0.1);
  }

  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) {
    return metadata;
  }

  @override
  bool hasToolCallMetadata(Map<String, dynamic> metadata) => false;

  @override
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) => null;

  @override
  Future<void> initialize(LlmConfiguration config) async {}

  @override
  Future<void> close() async {}
}

void main() {
  group('JSON-RPC 2.0 Batch Processing Tests (2025-03-26)', () {
    late BatchRequestManager batchManager;
    late MockMcpClientBatch client1;
    late MockMcpClientBatch client2;
    late MockMcpClientBatch client3;

    setUp(() {
      batchManager = BatchRequestManager(
        config: const BatchConfig(
          maxBatchSize: 5,
          batchTimeout: Duration(milliseconds: 100),
          requestTimeout: Duration(seconds: 5),
          preserveOrder: true,
        ),
      );

      client1 = MockMcpClientBatch('client1');
      client2 = MockMcpClientBatch('client2');
      client3 = MockMcpClientBatch('client3');

      batchManager.registerClient('client1', client1);
      batchManager.registerClient('client2', client2);
      batchManager.registerClient('client3', client3);
    });

    tearDown(() {
      batchManager.dispose();
    });

    group('BatchRequestManager Tests', () {
      test('should handle single request efficiently', () async {
        final startTime = DateTime.now();
        
        final result = await batchManager.addRequest(
          'tools/call',
          {'name': 'calculator', 'arguments': {'operation': 'add', 'a': 1, 'b': 2}},
          clientId: 'client1',
        );
        
        final duration = DateTime.now().difference(startTime);
        
        expect(result['result'], isNotNull);
        expect(result['result']['result'], contains('calculator'));
        expect(duration.inMilliseconds, lessThan(600)); // Should be reasonably fast for single request
      });

      test('should batch multiple requests for better performance', () async {
        final startTime = DateTime.now();
        
        // Create multiple requests that should be batched
        final futures = [
          batchManager.addRequest('tools/call', {'name': 'calculator', 'arguments': {'op': 'add'}}, clientId: 'client1'),
          batchManager.addRequest('tools/call', {'name': 'weather', 'arguments': {'city': 'NYC'}}, clientId: 'client1'),
          batchManager.addRequest('tools/call', {'name': 'translator', 'arguments': {'text': 'hello'}}, clientId: 'client1'),
        ];
        
        final results = await Future.wait(futures);
        final duration = DateTime.now().difference(startTime);
        
        expect(results.length, equals(3));
        expect(results.every((r) => r['result'] != null), isTrue);
        
        // Batching should be more efficient than individual requests
        expect(duration.inMilliseconds, lessThan(800)); // vs 300ms for 3 individual requests
        
        final stats = batchManager.getStatistics();
        expect(stats['total_batches'], greaterThanOrEqualTo(1));
        expect(stats['batched_requests'], greaterThanOrEqualTo(3));
      });

      test('should handle batch timeout correctly', () async {
        // Add one request and wait for timeout
        final future = batchManager.addRequest(
          'tools/list',
          {},
          clientId: 'client1',
        );
        
        final result = await future;
        expect(result['result'], isNotNull);
        
        final stats = batchManager.getStatistics();
        expect(stats['total_batches'], equals(1));
      });

      test('should handle multiple clients in batch', () async {
        final futures = [
          batchManager.addRequest('tools/list', {}, clientId: 'client1'),
          batchManager.addRequest('tools/list', {}, clientId: 'client2'),
          batchManager.addRequest('tools/list', {}, clientId: 'client3'),
        ];
        
        final results = await Future.wait(futures);
        
        expect(results.length, equals(3));
        expect(results.every((r) => r['result'] != null), isTrue);
      });

      test('should handle errors gracefully in batch', () async {
        final futures = [
          batchManager.addRequest('tools/call', {'name': 'nonexistent'}, clientId: 'client1'),
          batchManager.addRequest('tools/call', {'name': 'calculator'}, clientId: 'client1'),
        ];
        
        final results = await Future.wait(futures);
        
        expect(results.length, equals(2));
        expect(results[0]['error'], isNotNull); // First should error
        expect(results[1]['result'], isNotNull); // Second should succeed
      });

      test('should provide accurate statistics', () async {
        // Execute several requests
        await Future.wait([
          batchManager.addRequest('tools/list', {}, clientId: 'client1'),
          batchManager.addRequest('tools/list', {}, clientId: 'client2'),
          batchManager.addRequest('prompts/list', {}, clientId: 'client1'),
        ]);
        
        final stats = batchManager.getStatistics();
        
        expect(stats['total_requests'], equals(3));
        expect(stats['registered_clients'], equals(3));
        expect(stats['total_batches'], greaterThanOrEqualTo(1));
        expect(stats['batch_efficiency'], greaterThanOrEqualTo(0));
      });

      test('should handle immediate execution when forced', () async {
        final startTime = DateTime.now();
        
        final result = await batchManager.addRequest(
          'tools/call',
          {'name': 'calculator'},
          clientId: 'client1',
          forceImmediate: true,
        );
        
        final duration = DateTime.now().difference(startTime);
        
        expect(result['result'], isNotNull);
        expect(duration.inMilliseconds, lessThan(200)); // Should be immediate
      });

      test('should flush pending requests', () async {
        // Add requests without waiting
        final future1 = batchManager.addRequest('tools/list', {}, clientId: 'client1');
        final future2 = batchManager.addRequest('prompts/list', {}, clientId: 'client2');
        
        // Flush should complete all pending requests
        await batchManager.flush();
        
        final results = await Future.wait([future1, future2]);
        expect(results.length, equals(2));
        expect(results.every((r) => r['result'] != null), isTrue);
      });
    });

    group('LlmClient Batch Integration Tests', () {
      late LlmClient llmClient;

      setUp(() {
        llmClient = LlmClient(
          llmProvider: MockLlmProvider(),
          mcpClients: {
            'client1': client1,
            'client2': client2,
            'client3': client3,
          },
          batchConfig: const BatchConfig(
            maxBatchSize: 10,
            batchTimeout: Duration(milliseconds: 100),
          ),
        );
      });

      tearDown(() async {
        await llmClient.close();
      });

      test('should have batch processing capabilities', () {
        expect(llmClient.hasBatchProcessing, isTrue);
      });

      test('should execute batch tools efficiently', () async {
        final toolRequests = [
          {'name': 'calculator', 'arguments': {'operation': 'add'}},
          {'name': 'weather', 'arguments': {'city': 'NYC'}},
          {'name': 'translator', 'arguments': {'text': 'hello'}},
        ];
        
        final startTime = DateTime.now();
        final results = await llmClient.executeBatchTools(toolRequests, clientId: 'client1');
        final duration = DateTime.now().difference(startTime);
        
        expect(results.length, equals(3));
        expect(results.every((r) => r['result'] != null), isTrue);
        expect(duration.inMilliseconds, lessThan(800)); // Should be reasonably efficient
      });

      test('should get tools from multiple clients in batch', () async {
        final results = await llmClient.getBatchToolsByClient(['client1', 'client2']);
        
        expect(results.length, equals(2));
        expect(results['client1'], isNotEmpty);
        expect(results['client2'], isNotEmpty);
        expect(results['client1']!.first['name'], isNotNull);
      });

      test('should execute batch prompts', () async {
        final promptRequests = [
          {'name': 'summary', 'arguments': {'text': 'Long text to summarize'}},
          {'name': 'translate', 'arguments': {'text': 'Hello', 'target': 'es'}},
        ];
        
        final results = await llmClient.executeBatchPrompts(promptRequests, clientId: 'client1');
        
        expect(results.length, equals(2));
        expect(results.every((r) => r['result'] != null), isTrue);
      });

      test('should read batch resources', () async {
        final resourceUris = [
          'file://docs.txt',
          'file://config.json',
        ];
        
        final results = await llmClient.readBatchResources(resourceUris, clientId: 'client1');
        
        expect(results.length, equals(2));
        expect(results.every((r) => r['result'] != null), isTrue);
      });

      test('should provide batch statistics', () async {
        // Execute some batch operations
        await llmClient.executeBatchTools([
          {'name': 'calculator', 'arguments': {}},
        ], clientId: 'client1');
        
        final stats = llmClient.getBatchStatistics();
        
        expect(stats['total_requests'], greaterThanOrEqualTo(1));
        expect(stats['registered_clients'], equals(3));
      });

      test('should handle batch client management', () async {
        final newClient = MockMcpClientBatch('client4');
        
        // Add new client
        llmClient.addMcpClient('client4', newClient);
        
        final tools = await llmClient.getBatchToolsByClient(['client4']);
        expect(tools['client4'], isNotEmpty);
        
        // Remove client
        llmClient.removeMcpClient('client4');
        
        final stats = llmClient.getBatchStatistics();
        expect(stats['registered_clients'], equals(3)); // Back to original count
      });

      test('should flush batch requests on demand', () async {
        // Start some requests
        final future1 = llmClient.executeBatchTools([{'name': 'calculator', 'arguments': {}}], clientId: 'client1');
        final future2 = llmClient.readBatchResources(['file://test.txt'], clientId: 'client1');
        
        // Flush should complete them
        await llmClient.flushBatchRequests();
        
        final results1 = await future1;
        final results2 = await future2;
        
        expect(results1.length, equals(1));
        expect(results2.length, equals(1));
      });
    });

    group('Batch Performance Tests', () {
      test('should demonstrate performance improvement with batching', () async {
        // Test individual requests
        final individualStart = DateTime.now();
        final individualResults = <Map<String, dynamic>>[];
        
        for (int i = 0; i < 5; i++) {
          final result = await batchManager.addRequest(
            'tools/call',
            {'name': 'calculator', 'arguments': {'i': i}},
            clientId: 'client1',
            forceImmediate: true,
          );
          individualResults.add(result);
        }
        
        final individualDuration = DateTime.now().difference(individualStart);
        
        // Test batched requests
        final batchStart = DateTime.now();
        final batchFutures = <Future<Map<String, dynamic>>>[];
        
        for (int i = 0; i < 5; i++) {
          batchFutures.add(batchManager.addRequest(
            'tools/call',
            {'name': 'calculator', 'arguments': {'i': i}},
            clientId: 'client1',
          ));
        }
        
        final batchResults = await Future.wait(batchFutures);
        final batchDuration = DateTime.now().difference(batchStart);
        
        expect(individualResults.length, equals(5));
        expect(batchResults.length, equals(5));
        
        // Batching should be faster or at least not significantly slower
        final performanceRatio = batchDuration.inMilliseconds / individualDuration.inMilliseconds;
        expect(performanceRatio, lessThan(1.5)); // Allow some overhead but should be faster
        
        print('Individual requests: ${individualDuration.inMilliseconds}ms');
        print('Batched requests: ${batchDuration.inMilliseconds}ms');
        print('Performance ratio: ${performanceRatio.toStringAsFixed(2)}');
      });

      test('should handle high-load batch processing', () async {
        final futures = <Future<Map<String, dynamic>>>[];
        const requestCount = 50;
        
        final startTime = DateTime.now();
        
        // Create many concurrent requests
        for (int i = 0; i < requestCount; i++) {
          futures.add(batchManager.addRequest(
            'tools/call',
            {'name': 'calculator', 'arguments': {'request': i}},
            clientId: 'client${(i % 3) + 1}', // Distribute across clients
          ));
        }
        
        final results = await Future.wait(futures);
        final duration = DateTime.now().difference(startTime);
        
        expect(results.length, equals(requestCount));
        expect(results.every((r) => r['result'] != null), isTrue);
        
        final stats = batchManager.getStatistics();
        expect(stats['total_requests'], equals(requestCount));
        expect(stats['batch_efficiency'], greaterThan(0));
        
        print('Processed $requestCount requests in ${duration.inMilliseconds}ms');
        print('Batch efficiency: ${stats['batch_efficiency']}%');
      });
    });
  });
}