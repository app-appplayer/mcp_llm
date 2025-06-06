/// Example demonstrating JSON-RPC 2.0 batch processing optimization in 2025-03-26 MCP LLM
/// 
/// This example shows how the enhanced mcp_llm package leverages batch processing
/// to optimize performance when working with multiple MCP clients and operations.
library;

import 'package:mcp_llm/mcp_llm.dart';

// Mock MCP clients for demonstration
class MockCalculatorClient {
  Future<List<dynamic>> listTools() async {
    return [
      {
        'name': 'add',
        'description': 'Add two numbers',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'a': {'type': 'number'},
            'b': {'type': 'number'},
          },
          'required': ['a', 'b'],
        },
      },
      {
        'name': 'multiply',
        'description': 'Multiply two numbers',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'a': {'type': 'number'},
            'b': {'type': 'number'},
          },
          'required': ['a', 'b'],
        },
      },
    ];
  }

  Future<dynamic> callTool(String name, Map<String, dynamic> args) async {
    await Future.delayed(Duration(milliseconds: 100)); // Simulate processing
    
    switch (name) {
      case 'add':
        final a = args['a'] as num;
        final b = args['b'] as num;
        return {'result': a + b, 'operation': 'addition'};
      case 'multiply':
        final a = args['a'] as num;
        final b = args['b'] as num;
        return {'result': a * b, 'operation': 'multiplication'};
      default:
        throw Exception('Unknown tool: $name');
    }
  }

  // Support for JSON-RPC 2.0 batch processing
  Future<List<Map<String, dynamic>>> executeBatch(List<Map<String, dynamic>> requests) async {
    print('📦 Processing batch of ${requests.length} requests');
    await Future.delayed(Duration(milliseconds: 200)); // Batch overhead
    
    final results = <Map<String, dynamic>>[];
    for (final request in requests) {
      try {
        final method = request['method'] as String;
        final params = request['params'] as Map<String, dynamic>;
        
        dynamic result;
        if (method == 'tools/call') {
          result = await callTool(params['name'], params['arguments'] ?? {});
        } else if (method == 'tools/list') {
          result = await listTools();
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
          'error': {'code': -32000, 'message': e.toString()},
        });
      }
    }
    
    return results;
  }
}

class MockWeatherClient {
  Future<List<dynamic>> listTools() async {
    return [
      {
        'name': 'get_weather',
        'description': 'Get current weather for a city',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
            'units': {'type': 'string', 'enum': ['celsius', 'fahrenheit']},
          },
          'required': ['city'],
        },
      },
    ];
  }

  Future<dynamic> callTool(String name, Map<String, dynamic> args) async {
    await Future.delayed(Duration(milliseconds: 150)); // Simulate API call
    
    if (name == 'get_weather') {
      final city = args['city'] as String;
      final units = args['units'] ?? 'celsius';
      
      return {
        'city': city,
        'temperature': units == 'celsius' ? 22 : 72,
        'units': units,
        'condition': 'sunny',
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
    
    throw Exception('Unknown tool: $name');
  }
}

class MockLlmProvider implements LlmInterface {
  @override
  Future<void> initialize(LlmConfiguration config) async {
    // Mock initialization - no-op
  }

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return LlmResponse(
      text: 'Processed: ${request.prompt}',
      metadata: {'provider': 'mock', 'model': 'mock-v1'},
    );
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    yield LlmResponseChunk(
      textChunk: 'Streaming response for: ${request.prompt}',
      isDone: true,
      metadata: {'provider': 'mock'},
    );
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return List.generate(384, (i) => i * 0.001);
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
  Future<void> close() async {}
}

void main() async {
  print('🚀 MCP LLM 2025-03-26 Batch Processing Example\n');

  // Create MCP clients
  final calculatorClient = MockCalculatorClient();
  final weatherClient = MockWeatherClient();

  // Create LLM client with batch processing optimization
  final llmClient = LlmClient(
    llmProvider: MockLlmProvider(),
    mcpClients: {
      'calculator': calculatorClient,
      'weather': weatherClient,
    },
    batchConfig: const BatchConfig(
      maxBatchSize: 10,
      batchTimeout: Duration(milliseconds: 100),
      requestTimeout: Duration(seconds: 30),
      enableRetry: true,
      preserveOrder: true,
    ),
  );

  print('✅ LLM Client initialized with batch processing');
  print('📊 Batch processing enabled: ${llmClient.hasBatchProcessing}');

  try {
    // Example 1: Demonstrate individual vs batch tool execution
    print('\n📖 Example 1: Performance Comparison\n');
    
    // Individual requests (traditional approach)
    print('⏱️  Testing individual requests...');
    final individualStart = DateTime.now();
    
    final result1 = await llmClient.executeTool('add', {'a': 10, 'b': 20}, mcpClientId: 'calculator');
    final result2 = await llmClient.executeTool('multiply', {'a': 5, 'b': 6}, mcpClientId: 'calculator');
    final result3 = await llmClient.executeTool('get_weather', {'city': 'New York'}, mcpClientId: 'weather');
    
    final individualDuration = DateTime.now().difference(individualStart);
    print('   Individual requests completed in: ${individualDuration.inMilliseconds}ms');
    print('   Results: $result1, $result2, $result3');

    // Batch requests (2025-03-26 optimization)
    print('\n⚡ Testing batch requests...');
    final batchStart = DateTime.now();
    
    final batchResults = await llmClient.executeBatchTools([
      {'name': 'add', 'arguments': {'a': 10, 'b': 20}},
      {'name': 'multiply', 'arguments': {'a': 5, 'b': 6}},
    ], clientId: 'calculator');
    
    final weatherResult = await llmClient.executeBatchTools([
      {'name': 'get_weather', 'arguments': {'city': 'New York'}},
    ], clientId: 'weather');
    
    final batchDuration = DateTime.now().difference(batchStart);
    print('   Batch requests completed in: ${batchDuration.inMilliseconds}ms');
    print('   Calculator results: $batchResults');
    print('   Weather results: $weatherResult');
    print('   Improvement: ${((individualDuration.inMilliseconds - batchDuration.inMilliseconds) / individualDuration.inMilliseconds * 100).toStringAsFixed(1)}%');

    // Example 2: Multi-client batch operations
    print('\n📖 Example 2: Multi-Client Batch Operations\n');
    
    final multiClientStart = DateTime.now();
    
    // Get tools from multiple clients simultaneously
    final toolsByClient = await llmClient.getBatchToolsByClient(['calculator', 'weather']);
    
    print('🔧 Available tools by client:');
    toolsByClient.forEach((clientId, tools) {
      print('   $clientId: ${tools.map((t) => t['name']).join(', ')}');
    });

    // Execute multiple calculations in parallel
    final calculations = await llmClient.executeBatchTools([
      {'name': 'add', 'arguments': {'a': 1, 'b': 2}},
      {'name': 'add', 'arguments': {'a': 3, 'b': 4}},
      {'name': 'multiply', 'arguments': {'a': 2, 'b': 3}},
      {'name': 'multiply', 'arguments': {'a': 4, 'b': 5}},
    ], clientId: 'calculator');

    final multiClientDuration = DateTime.now().difference(multiClientStart);
    print('   Multi-client operations completed in: ${multiClientDuration.inMilliseconds}ms');
    print('   Calculation results: ${calculations.map((r) => r['result']?['result']).join(', ')}');

    // Example 3: High-throughput batch processing
    print('\n📖 Example 3: High-Throughput Processing\n');
    
    final highThroughputStart = DateTime.now();
    
    // Create a large number of mathematical operations
    final operations = <Map<String, dynamic>>[];
    for (int i = 1; i <= 20; i++) {
      operations.addAll([
        {'name': 'add', 'arguments': {'a': i, 'b': i * 2}},
        {'name': 'multiply', 'arguments': {'a': i, 'b': 3}},
      ]);
    }
    
    print('🔢 Processing ${operations.length} mathematical operations...');
    final mathResults = await llmClient.executeBatchTools(operations, clientId: 'calculator');
    
    final throughputDuration = DateTime.now().difference(highThroughputStart);
    final throughput = operations.length / (throughputDuration.inMilliseconds / 1000);
    
    print('   Processed ${mathResults.length} operations in ${throughputDuration.inMilliseconds}ms');
    print('   Throughput: ${throughput.toStringAsFixed(1)} operations/second');

    // Example 4: Batch statistics and monitoring
    print('\n📖 Example 4: Performance Statistics\n');
    
    final stats = llmClient.getBatchStatistics();
    print('📊 Batch Processing Statistics:');
    print('   Total requests: ${stats['total_requests']}');
    print('   Batched requests: ${stats['batched_requests']}');
    print('   Total batches: ${stats['total_batches']}');
    print('   Average processing time: ${stats['avg_processing_time_ms']}ms');
    print('   Batch efficiency: ${stats['batch_efficiency']}%');
    print('   Registered clients: ${stats['registered_clients']}');

    // Example 5: Real-time batch flushing
    print('\n📖 Example 5: Manual Batch Control\n');
    
    print('🔄 Starting batch operations without waiting...');
    final pendingFutures = [
      llmClient.executeBatchTools([{'name': 'add', 'arguments': {'a': 100, 'b': 200}}], clientId: 'calculator'),
      llmClient.executeBatchTools([{'name': 'get_weather', 'arguments': {'city': 'Tokyo'}}], clientId: 'weather'),
    ];
    
    print('💾 Manually flushing all pending batches...');
    await llmClient.flushBatchRequests();
    
    final flushResults = await Future.wait(pendingFutures);
    print('   Flushed results: ${flushResults.length} operations completed');

    print('\n🎉 All examples completed successfully!');
    print('\n💡 Key Benefits of 2025-03-26 Batch Processing:');
    print('   • Reduced network overhead through JSON-RPC 2.0 batching');
    print('   • Improved throughput for multiple operations');
    print('   • Better resource utilization across MCP clients');
    print('   • Automatic optimization with configurable batching');
    print('   • OAuth 2.1 authentication support for secure batch operations');

  } catch (e) {
    print('❌ Error during batch processing: $e');
  } finally {
    // Clean up resources
    await llmClient.close();
    print('\n🧹 Resources cleaned up');
  }
}