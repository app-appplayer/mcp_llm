import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

/// Simple mock MCP client for batch testing
class SimpleBatchMockClient {
  final String clientId;
  
  SimpleBatchMockClient(this.clientId);

  Future<List<dynamic>> listTools() async {
    await Future.delayed(Duration(milliseconds: 10));
    return [
      {'name': 'calculator', 'description': 'Math tool'},
      {'name': 'weather', 'description': 'Weather tool'},
    ];
  }

  Future<dynamic> callTool(String name, Map<String, dynamic> args) async {
    await Future.delayed(Duration(milliseconds: 10));
    return {
      'result': 'Tool $name executed',
      'clientId': clientId,
      'args': args,
    };
  }

  // Mock batch processing support
  Future<List<Map<String, dynamic>>> executeBatch(List<Map<String, dynamic>> requests) async {
    await Future.delayed(Duration(milliseconds: 20));
    
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

/// Simple mock LLM provider
class SimpleBatchLlmProvider implements LlmInterface {
  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return LlmResponse(
      text: 'Mock response',
      metadata: {'provider': 'simple_batch_mock'},
    );
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    yield LlmResponseChunk(
      textChunk: 'Mock streaming',
      isDone: true,
      metadata: {'provider': 'simple_batch_mock'},
    );
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return List.generate(10, (i) => i * 0.1);
  }

  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) => metadata;

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
  group('Batch Processing Simple Tests (2025-03-26)', () {
    late BatchRequestManager batchManager;
    late SimpleBatchMockClient client1;
    late SimpleBatchMockClient client2;

    setUp(() {
      batchManager = BatchRequestManager(
        config: const BatchConfig(
          maxBatchSize: 5,
          batchTimeout: Duration(milliseconds: 50),
        ),
      );

      client1 = SimpleBatchMockClient('client1');
      client2 = SimpleBatchMockClient('client2');

      batchManager.registerClient('client1', client1);
      batchManager.registerClient('client2', client2);
    });

    tearDown(() {
      batchManager.dispose();
    });

    test('should handle single request', () async {
      final result = await batchManager.addRequest(
        'tools/call',
        {'name': 'calculator', 'arguments': {'op': 'add'}},
        clientId: 'client1',
      );
      
      expect(result['result'], isNotNull);
      expect(result['result']['result'], equals('Tool calculator executed'));
    });

    test('should batch multiple requests', () async {
      final futures = [
        batchManager.addRequest('tools/call', {'name': 'calculator'}, clientId: 'client1'),
        batchManager.addRequest('tools/call', {'name': 'weather'}, clientId: 'client1'),
        batchManager.addRequest('tools/list', {}, clientId: 'client1'),
      ];
      
      final results = await Future.wait(futures);
      
      expect(results.length, equals(3));
      expect(results.every((r) => r['result'] != null), isTrue);
      
      final stats = batchManager.getStatistics();
      expect(stats['total_requests'], equals(3));
    });

    test('should handle multiple clients', () async {
      final futures = [
        batchManager.addRequest('tools/list', {}, clientId: 'client1'),
        batchManager.addRequest('tools/list', {}, clientId: 'client2'),
      ];
      
      final results = await Future.wait(futures);
      
      expect(results.length, equals(2));
      expect(results.every((r) => r['result'] != null), isTrue);
    });

    test('should provide statistics', () async {
      await batchManager.addRequest('tools/list', {}, clientId: 'client1');
      
      final stats = batchManager.getStatistics();
      
      expect(stats['total_requests'], equals(1));
      expect(stats['registered_clients'], equals(2));
      expect(stats['batch_efficiency'], greaterThanOrEqualTo(0));
    });

    test('should work with LlmClient integration', () async {
      final llmClient = LlmClient(
        llmProvider: SimpleBatchLlmProvider(),
        mcpClients: {
          'client1': client1,
          'client2': client2,
        },
        batchConfig: const BatchConfig(maxBatchSize: 5),
      );
      
      expect(llmClient.hasBatchProcessing, isTrue);
      
      final toolRequests = [
        {'name': 'calculator', 'arguments': {'op': 'add'}},
        {'name': 'weather', 'arguments': {'city': 'NYC'}},
      ];
      
      final results = await llmClient.executeBatchTools(toolRequests, clientId: 'client1');
      
      expect(results.length, equals(2));
      expect(results.every((r) => r['result'] != null), isTrue);
      
      final batchStats = llmClient.getBatchStatistics();
      expect(batchStats['registered_clients'], equals(2));
      
      await llmClient.close();
    });
  });
}