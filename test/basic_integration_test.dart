import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

/// Very simple mock for basic integration test
class BasicMockClient {
  bool _authenticationEnabled = false;
  
  bool get isAuthenticationEnabled => _authenticationEnabled;
  
  void enableAuthentication(TokenValidator validator) {
    _authenticationEnabled = true;
  }
  
  Future<List<dynamic>> listTools() async {
    return [{'name': 'test_tool', 'description': 'Test tool'}];
  }
  
  Future<dynamic> callTool(String name, Map<String, dynamic> args) async {
    return {'result': 'Tool $name executed', 'args': args};
  }
}

/// Simple LLM provider
class BasicMockLlmProvider implements LlmInterface {
  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return LlmResponse(
      text: 'Mock response for: ${request.prompt}',
      metadata: {'provider': 'basic_mock'},
    );
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    yield LlmResponseChunk(
      textChunk: 'Streaming response',
      isDone: true,
      metadata: {'provider': 'basic_mock'},
    );
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return [0.1, 0.2, 0.3];
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
  group('Basic Integration Tests', () {
    test('should create LlmClient with 2025-03-26 features', () async {
      final client = LlmClient(
        llmProvider: BasicMockLlmProvider(),
        mcpClients: {
          'test': BasicMockClient(),
        },
        enableHealthMonitoring: true,
        enableCapabilityManagement: true,
        enableEnhancedErrorHandling: true,
      );

      // Test basic functionality
      expect(client.hasMcpClientManager, isTrue);
      
      // Test feature status
      final featureStatus = client.featureStatus;
      expect(featureStatus['health_monitoring'], isTrue);
      expect(featureStatus['capability_management'], isTrue);
      expect(featureStatus['enhanced_error_handling'], isTrue);

      // Test basic chat
      final response = await client.chat('Hello!');
      expect(response.text, contains('Mock response'));

      await client.close();
    });

    test('should work with basic OAuth authentication', () async {
      final tokenValidator = ApiKeyValidator({
        'valid-token': {
          'scopes': ['tools:execute'],
          'exp': DateTime.now().add(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          'client_id': 'test-client',
        },
      });

      final authAdapter = McpAuthAdapter(
        tokenValidator: tokenValidator,
        defaultConfig: const AuthConfig(scopes: ['tools:execute']),
      );

      final mockClient = BasicMockClient();
      final result = await authAdapter.authenticate('test-client', mockClient);

      expect(result.isAuthenticated, isTrue);
      expect(result.scopes, contains('tools:execute'));

      authAdapter.dispose();
    });

    test('should validate tokens correctly', () async {
      final tokenValidator = ApiKeyValidator({
        'valid-token': {
          'scopes': ['tools:execute', 'resources:read'],
          'exp': DateTime.now().add(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          'client_id': 'test-client',
        },
        'expired-token': {
          'scopes': ['tools:execute'],
          'exp': DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          'client_id': 'expired-client',
        },
      });

      // Valid token
      final validResult = await tokenValidator.validateToken('valid-token');
      expect(validResult.isAuthenticated, isTrue);
      expect(validResult.scopes, contains('tools:execute'));

      // Expired token
      final expiredResult = await tokenValidator.validateToken('expired-token');
      expect(expiredResult.isAuthenticated, isFalse);
      expect(expiredResult.error, contains('expired'));

      // Invalid token
      final invalidResult = await tokenValidator.validateToken('invalid-token');
      expect(invalidResult.isAuthenticated, isFalse);
      expect(invalidResult.error, contains('Invalid'));
    });

    test('should perform health checks', () async {
      final client = LlmClient(
        llmProvider: BasicMockLlmProvider(),
        mcpClients: {
          'test': BasicMockClient(),
        },
        enableHealthMonitoring: true,
        healthConfig: const HealthCheckConfig(timeout: Duration(seconds: 5)),
      );

      final healthReport = await client.performHealthCheck();
      expect(healthReport.overallStatus, equals(HealthStatus.healthy));
      expect(healthReport.componentResults, isNotEmpty);

      final healthStats = client.getHealthStatistics();
      expect(healthStats['total_clients'], equals(1));
      expect(healthStats['healthy'], equals(1));

      await client.close();
    });

    test('should manage capabilities', () async {
      final client = LlmClient(
        llmProvider: BasicMockLlmProvider(),
        mcpClients: {
          'test': BasicMockClient(),
        },
        enableCapabilityManagement: true,
      );

      // Get capabilities
      final capabilities = client.getAllCapabilities();
      expect(capabilities, isNotEmpty);

      // Generate request ID
      final requestId = client.generateCapabilityRequestId();
      expect(requestId, isNotEmpty);

      await client.close();
    });
  });
}