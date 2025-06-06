import 'package:mcp_llm/mcp_llm.dart';

/// Simple mock LLM provider for testing
class SimpleMockLlmProvider implements LlmInterface {
  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return LlmResponse(
      text: 'Mock response for: ${request.prompt}',
      metadata: {'provider': 'simple_mock'},
    );
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    yield LlmResponseChunk(
      textChunk: 'Simple mock response',
      isDone: true,
      metadata: {'provider': 'simple_mock'},
    );
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return List.generate(10, (i) => i * 0.1);
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

/// Simple mock MCP client
class SimpleMockMcpClient {
  bool _authenticationEnabled = false;

  bool get isAuthenticationEnabled => _authenticationEnabled;

  void enableAuthentication(TokenValidator validator) {
    _authenticationEnabled = true;
  }

  Future<List<dynamic>> listTools() async {
    return [
      {'name': 'test_tool', 'description': 'A test tool'},
    ];
  }

  Future<dynamic> callTool(String name, Map<String, dynamic> args) async {
    return {'result': 'Tool $name executed with args: $args'};
  }
}

void main() async {
  print('🚀 Simple MCP LLM 2025-03-26 Test\n');

  // Create simple mock client
  final mockClient = SimpleMockMcpClient();

  // Create LLM client with 2025-03-26 features
  final llmClient = LlmClient(
    llmProvider: SimpleMockLlmProvider(),
    mcpClients: {
      'test': mockClient,
    },
    // Enable basic 2025-03-26 features
    batchConfig: const BatchConfig(maxBatchSize: 5),
    enableHealthMonitoring: true,
    enableCapabilityManagement: true,
    enableEnhancedErrorHandling: true,
  );

  print('✅ LLM Client created with 2025-03-26 features');

  // Test feature status
  final featureStatus = llmClient.featureStatus;
  print('📊 Feature Status:');
  featureStatus.forEach((feature, enabled) {
    final status = enabled.toString() == 'true' ? '✅' : '❌';
    print('   $status ${feature.replaceAll('_', ' ').toUpperCase()}');
  });

  // Test basic chat functionality
  print('\n💬 Testing basic chat...');
  final response = await llmClient.chat('Hello, test!');
  print('   Response: ${response.text}');

  // Test batch statistics
  print('\n📈 Batch Statistics:');
  final batchStats = llmClient.getBatchStatistics();
  print('   Registered clients: ${batchStats['registered_clients']}');

  // Test health monitoring
  print('\n🏥 Health Monitoring:');
  final healthReport = await llmClient.performHealthCheck();
  print('   Overall status: ${healthReport.overallStatus.name}');
  print('   Components checked: ${healthReport.componentResults.length}');

  // Cleanup
  await llmClient.close();
  print('\n✅ Test completed successfully!');
}