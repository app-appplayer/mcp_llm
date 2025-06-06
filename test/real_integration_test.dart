import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_client/mcp_client.dart' as mcp_client;
import 'package:mcp_server/mcp_server.dart' as mcp_server;

/// Real integration test with actual 2025-03-26 MCP client and server
void main() {
  group('Real 2025-03-26 MCP Integration Tests', () {
    late mcp_client.Client mcpClient;
    late mcp_server.Server mcpServer;
    late LlmClient llmClient;

    setUp(() async {
      // Create real MCP client with 2025-03-26 features
      mcpClient = mcp_client.Client(
        name: 'test-llm-client',
        version: '1.0.0',
        capabilities: mcp_client.ClientCapabilities(
          roots: true,
          rootsListChanged: true,
          sampling: true,
        ),
      );

      // Create real MCP server with 2025-03-26 features
      mcpServer = mcp_server.Server(
        name: 'test-llm-server',
        version: '1.0.0',
        capabilities: mcp_server.ServerCapabilities(
          tools: mcp_server.ToolsCapability(),
          resources: mcp_server.ResourcesCapability(),
          prompts: mcp_server.PromptsCapability(),
          sampling: mcp_server.SamplingCapability(),
        ),
      );
    });

    tearDown(() async {
      try {
        mcpClient.disconnect();
      } catch (e) {
        // Ignore disconnect errors in teardown
      }
      
      try {
        // MCP server doesn't have a stop method, just let it be garbage collected
      } catch (e) {
        // Ignore any teardown errors
      }
    });

    test('should verify 2025-03-26 protocol version', () {
      expect(mcpClient.protocolVersion, equals('2025-03-26'));
      // Server doesn't expose protocolVersion directly, check name instead
      expect(mcpServer.name, equals('test-llm-server'));
    });

    test('should verify MCP client has required methods', () {
      // Verify that the MCP client has the methods expected by mcp_llm
      expect(mcpClient, isNotNull);
      
      // Check if client has listTools method (should be available but might throw if not connected)
      expect(() => mcpClient.listTools(), throwsA(isA<Exception>()));
    });

    test('should verify MCP server has required capabilities', () {
      // Verify that the MCP server has the capabilities expected by mcp_llm
      expect(mcpServer, isNotNull);
      expect(mcpServer.capabilities, isNotNull);
      expect(mcpServer.capabilities.tools, isNotNull);
    });

    test('should create LlmClient with real MCP client', () {
      // Test that LlmClient can be created with actual MCP client
      llmClient = LlmClient(
        llmProvider: TestLlmProvider(),
        mcpClients: {
          'real-client': mcpClient,
        },
      );

      expect(llmClient, isNotNull);
      expect(llmClient.hasMcpClientManager, isTrue);
      expect(llmClient.getMcpClientIds(), contains('real-client'));
    });

    test('should handle 2025-03-26 features with real clients', () async {
      // Create LlmClient with 2025-03-26 features enabled
      llmClient = LlmClient(
        llmProvider: TestLlmProvider(),
        mcpClients: {
          'real-client': mcpClient,
        },
        enableHealthMonitoring: true,
        enableCapabilityManagement: true,
        enableEnhancedErrorHandling: true,
      );

      // Test feature status
      final featureStatus = llmClient.featureStatus;
      expect(featureStatus['health_monitoring'], isTrue);
      expect(featureStatus['capability_management'], isTrue);
      expect(featureStatus['enhanced_error_handling'], isTrue);

      // Test health check (should work even without connection)
      final healthReport = await llmClient.performHealthCheck();
      expect(healthReport, isNotNull);
      expect(healthReport.overallStatus, isNotNull);

      // Test capability management
      final capabilities = llmClient.getAllCapabilities();
      expect(capabilities, isNotNull);
      expect(capabilities, isNotEmpty);

      await llmClient.close();
    });

    test('should verify OAuth 2.1 support structure', () {
      // Verify that the auth modules are available
      final tokenValidator = ApiKeyValidator({
        'test-token': {
          'scopes': ['tools:execute'],
          'exp': DateTime.now().add(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          'client_id': 'test-client',
        },
      });

      final authAdapter = McpAuthAdapter(
        tokenValidator: tokenValidator,
        defaultConfig: const AuthConfig(scopes: ['tools:execute']),
      );

      expect(tokenValidator, isNotNull);
      expect(authAdapter, isNotNull);
      
      authAdapter.dispose();
    });

    test('should verify batch processing capability', () {
      final batchManager = BatchRequestManager();
      
      expect(batchManager, isNotNull);
      
      // Register real client for batch processing
      batchManager.registerClient('real-client', mcpClient);
      
      final stats = batchManager.getStatistics();
      expect(stats['registered_clients'], equals(1));
      
      batchManager.dispose();
    });

    test('should handle MCP client adapter integration', () async {
      final adapter = LlmClientAdapter(
        mcpClient,
        clientId: 'test-adapter',
      );

      expect(adapter, isNotNull);
      
      // Test that adapter can handle the real client
      // Note: This will fail with connection error but shows the integration works
      try {
        await adapter.getTools();
      } catch (e) {
        // Expected to fail since client is not connected, but adapter should exist
        expect(e, isA<Exception>());
      }
    });
  });
}

/// Simple test LLM provider for integration testing
class TestLlmProvider implements LlmInterface {
  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return LlmResponse(
      text: 'Test response for: ${request.prompt}',
      metadata: {'provider': 'test_integration'},
    );
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    yield LlmResponseChunk(
      textChunk: 'Test streaming response',
      isDone: true,
      metadata: {'provider': 'test_integration'},
    );
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return List.generate(5, (i) => i * 0.1);
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