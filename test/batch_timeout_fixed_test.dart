import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

/// Simple batch test with timeout fixes
class TimeoutFixedMockClient {
  final String clientId;
  
  TimeoutFixedMockClient(this.clientId);

  Future<List<dynamic>> listTools() async {
    // Very short delay to avoid timeouts
    await Future.delayed(Duration(milliseconds: 1));
    return [
      {'name': 'calculator', 'description': 'Math tool'},
      {'name': 'weather', 'description': 'Weather tool'},
    ];
  }

  Future<dynamic> callTool(String name, Map<String, dynamic> args) async {
    // Very short delay to avoid timeouts
    await Future.delayed(Duration(milliseconds: 1));
    return {
      'result': 'Tool $name executed',
      'clientId': clientId,
      'args': args,
    };
  }
}

void main() {
  group('Batch Processing Timeout Fixed Tests', () {
    late BatchRequestManager batchManager;
    late TimeoutFixedMockClient client1;

    setUp(() {
      batchManager = BatchRequestManager(
        config: const BatchConfig(
          maxBatchSize: 3,
          batchTimeout: Duration(milliseconds: 10), // Very short timeout
          requestTimeout: Duration(seconds: 5),      // Reasonable timeout
        ),
      );

      client1 = TimeoutFixedMockClient('client1');
      batchManager.registerClient('client1', client1);
    });

    tearDown(() {
      batchManager.dispose();
    });

    test('should handle immediate single request', () async {
      final result = await batchManager.addRequest(
        'tools/call',
        {'name': 'calculator', 'arguments': {'op': 'add'}},
        clientId: 'client1',
        forceImmediate: true, // Force immediate execution
      );
      
      expect(result['result'], isNotNull);
      expect(result['result']['result'], equals('Tool calculator executed'));
    });

    test('should handle immediate multiple requests', () async {
      final futures = [
        batchManager.addRequest('tools/call', {'name': 'calculator'}, clientId: 'client1', forceImmediate: true),
        batchManager.addRequest('tools/call', {'name': 'weather'}, clientId: 'client1', forceImmediate: true),
        batchManager.addRequest('tools/list', {}, clientId: 'client1', forceImmediate: true),
      ];
      
      final results = await Future.wait(futures);
      
      expect(results.length, equals(3));
      expect(results.every((r) => r['result'] != null), isTrue);
      
      final stats = batchManager.getStatistics();
      expect(stats['total_requests'], equals(3));
    });

    test('should provide correct statistics', () async {
      await batchManager.addRequest('tools/list', {}, clientId: 'client1', forceImmediate: true);
      
      final stats = batchManager.getStatistics();
      
      expect(stats['total_requests'], equals(1));
      expect(stats['registered_clients'], equals(1));
      expect(stats['batch_efficiency'], greaterThanOrEqualTo(0));
    });

    test('should flush pending batches immediately', () async {
      // Add some requests without forcing immediate execution
      batchManager.addRequest('tools/list', {}, clientId: 'client1');
      batchManager.addRequest('tools/call', {'name': 'test'}, clientId: 'client1');
      
      // Flush should complete all pending requests
      await batchManager.flush();
      
      final stats = batchManager.getStatistics();
      expect(stats['total_requests'], equals(2));
      expect(stats['pending_requests'], equals(0));
    });
  });
}