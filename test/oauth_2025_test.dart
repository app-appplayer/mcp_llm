import 'package:test/test.dart';
import 'package:mcp_llm/src/adapter/mcp_auth_adapter.dart';
import 'package:mcp_llm/src/adapter/llm_client_adapter.dart';
import 'package:mcp_llm/src/adapter/mcp_client_manager.dart';

/// Mock MCP client for testing
class MockMcpClient {
  bool _authenticationEnabled = false;
  
  bool get isAuthenticationEnabled => _authenticationEnabled;
  
  void enableAuthentication(TokenValidator validator) {
    _authenticationEnabled = true;
  }
  
  void disableAuthentication() {
    _authenticationEnabled = false;
  }
  
  Future<List<dynamic>> listTools() async {
    if (_authenticationEnabled) {
      return [
        {'name': 'secure_tool', 'description': 'A secure tool requiring OAuth'},
        {'name': 'public_tool', 'description': 'A public tool'},
      ];
    }
    return [
      {'name': 'public_tool', 'description': 'A public tool'},
    ];
  }
  
  Future<List<dynamic>> listPrompts() async {
    return [
      {'name': 'test_prompt', 'description': 'Test prompt', 'arguments': []},
    ];
  }
  
  Future<List<dynamic>> listResources() async {
    return [
      {'name': 'test_resource', 'description': 'Test resource', 'uri': 'test://resource'},
    ];
  }
  
  Future<dynamic> callTool(String name, Map<String, dynamic> args) async {
    if (name == 'secure_tool' && !_authenticationEnabled) {
      throw Exception('Authentication required for secure tool');
    }
    return {'result': 'Tool $name executed with args: $args'};
  }
  
  Future<dynamic> callPrompt(String name, Map<String, dynamic> args) async {
    return {'content': 'Prompt $name executed'};
  }
  
  Future<dynamic> readResource(String uri) async {
    return {'content': 'Resource content for $uri'};
  }
}

void main() {
  group('OAuth 2.1 Authentication Tests (2025-03-26)', () {
    late McpAuthAdapter authAdapter;
    late TokenValidator tokenValidator;
    late MockMcpClient mockClient;

    setUp(() {
      // Setup token validator with test tokens
      tokenValidator = ApiKeyValidator({
        'valid-token': {
          'scopes': ['tools:execute', 'resources:read', 'prompts:read'],
          'exp': DateTime.now().add(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          'client_id': 'test-client',
          'auto_refresh': true,
        },
        'expired-token': {
          'scopes': ['tools:execute'],
          'exp': DateTime.now().subtract(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          'client_id': 'expired-client',
        },
        'limited-token': {
          'scopes': ['resources:read'],
          'exp': DateTime.now().add(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          'client_id': 'limited-client',
        },
      });

      authAdapter = McpAuthAdapter(
        tokenValidator: tokenValidator,
        defaultConfig: const AuthConfig(
          autoRefresh: true,
          scopes: ['tools:execute', 'resources:read'],
        ),
      );

      mockClient = MockMcpClient();
    });

    tearDown(() {
      authAdapter.dispose();
    });

    group('McpAuthAdapter Tests', () {
      test('should authenticate with valid token', () async {
        final result = await authAdapter.authenticate('test-client', mockClient);
        
        expect(result.isAuthenticated, isTrue);
        expect(result.accessToken, isNotNull);
        expect(result.metadata['protocol_version'], equals('2025-03-26'));
        expect(result.metadata['auth_method'], contains('oauth_2_1'));
      });

      test('should detect 2025-03-26 MCP authentication support', () async {
        final result = await authAdapter.authenticate('test-client', mockClient);
        expect(result.isAuthenticated, isTrue);
        expect(mockClient.isAuthenticationEnabled, isTrue);
      });

      test('should validate token with correct scopes', () async {
        final result = await tokenValidator.validateToken(
          'valid-token',
          requiredScopes: ['tools:execute'],
        );
        
        expect(result.isAuthenticated, isTrue);
        expect(result.scopes, contains('tools:execute'));
      });

      test('should reject token with insufficient scopes', () async {
        final result = await tokenValidator.validateToken(
          'limited-token',
          requiredScopes: ['tools:execute'],
        );
        
        expect(result.isAuthenticated, isFalse);
        expect(result.error, contains('Insufficient scopes'));
      });

      test('should reject expired token', () async {
        final result = await tokenValidator.validateToken('expired-token');
        
        expect(result.isAuthenticated, isFalse);
        expect(result.error, contains('Token expired'));
      });

      test('should check OAuth 2.1 compliance', () async {
        final isCompliant = await authAdapter.checkOAuth21Compliance(mockClient);
        expect(isCompliant, isTrue);
      });

      test('should refresh tokens', () async {
        // First authenticate
        await authAdapter.authenticate('test-client', mockClient);
        
        // Then refresh
        await authAdapter.refreshToken('test-client');
        
        final context = authAdapter.getAuthContext('test-client');
        expect(context, isNotNull);
        expect(context!.isAuthenticated, isTrue);
      });

      test('should manage authentication context', () async {
        await authAdapter.authenticate('test-client', mockClient);
        
        expect(authAdapter.hasValidAuth('test-client'), isTrue);
        
        final context = authAdapter.getAuthContext('test-client');
        expect(context, isNotNull);
        expect(context!.metadata['client_id'], equals('test-client'));
        
        authAdapter.removeAuth('test-client');
        expect(authAdapter.hasValidAuth('test-client'), isFalse);
      });
    });

    group('LlmClientAdapter OAuth Tests', () {
      test('should create adapter with OAuth support', () {
        final adapter = LlmClientAdapter(
          mockClient,
          authAdapter: authAdapter,
          clientId: 'test-client',
        );
        
        expect(adapter.isAuthenticated, isFalse); // Not authenticated yet
      });

      test('should authenticate client through adapter', () async {
        final adapter = LlmClientAdapter(
          mockClient,
          authAdapter: authAdapter,
          clientId: 'test-client',
        );
        
        final success = await adapter.authenticateClient();
        expect(success, isTrue);
        expect(adapter.isAuthenticated, isTrue);
      });

      test('should enforce authentication for operations', () async {
        final adapter = LlmClientAdapter(
          mockClient,
          authAdapter: authAdapter,
          clientId: 'test-client',
        );
        
        // Without authentication, should auto-authenticate and succeed
        final tools = await adapter.getTools();
        expect(tools, isNotEmpty);
        expect(adapter.isAuthenticated, isTrue);
      });

      test('should provide authentication status', () async {
        final adapter = LlmClientAdapter(
          mockClient,
          authAdapter: authAdapter,
          clientId: 'test-client',
        );
        
        await adapter.authenticateClient();
        
        final status = adapter.getAuthStatus();
        expect(status['authenticated'], isTrue);
        expect(status['protocol_version'], equals('2025-03-26'));
        expect(status['client_id'], equals('test-client'));
      });

      test('should check OAuth 2.1 compliance', () async {
        final adapter = LlmClientAdapter(
          mockClient,
          authAdapter: authAdapter,
          clientId: 'test-client',
        );
        
        final isCompliant = await adapter.checkOAuth21Compliance();
        expect(isCompliant, isTrue);
      });

      test('should refresh token manually', () async {
        final adapter = LlmClientAdapter(
          mockClient,
          authAdapter: authAdapter,
          clientId: 'test-client',
        );
        
        await adapter.authenticateClient();
        final success = await adapter.refreshToken();
        expect(success, isTrue);
      });
    });

    group('McpClientManager OAuth Tests', () {
      test('should add client with OAuth authentication', () async {
        final manager = McpClientManager();
        
        await manager.addClientWithAuth(
          'test-client',
          mockClient,
          authConfig: const AuthConfig(scopes: ['tools:execute']),
          tokenValidator: tokenValidator,
        );
        
        expect(manager.clientIds, contains('test-client'));
        expect(manager.authenticatedClients, contains('test-client'));
      });

      test('should enable authentication for existing client', () async {
        final manager = McpClientManager();
        
        // Add client without auth first
        manager.addClient('test-client', mockClient);
        expect(manager.unauthenticatedClients, contains('test-client'));
        
        // Enable auth
        final success = await manager.enableAuthenticationForClient(
          'test-client',
          authConfig: const AuthConfig(scopes: ['tools:execute']),
          tokenValidator: tokenValidator,
        );
        
        expect(success, isTrue);
        expect(manager.authenticatedClients, contains('test-client'));
        expect(manager.unauthenticatedClients, isEmpty);
      });

      test('should disable authentication for client', () async {
        final manager = McpClientManager();
        
        await manager.addClientWithAuth(
          'test-client',
          mockClient,
          tokenValidator: tokenValidator,
        );
        
        expect(manager.authenticatedClients, contains('test-client'));
        
        manager.disableAuthenticationForClient('test-client');
        expect(manager.unauthenticatedClients, contains('test-client'));
        expect(manager.authenticatedClients, isEmpty);
      });

      test('should refresh all tokens', () async {
        final manager = McpClientManager();
        
        await manager.addClientWithAuth('client1', MockMcpClient(), tokenValidator: tokenValidator);
        await manager.addClientWithAuth('client2', MockMcpClient(), tokenValidator: tokenValidator);
        
        // This should complete without errors
        await manager.refreshAllTokens();
      });

      test('should provide authentication summary', () async {
        final manager = McpClientManager();
        
        manager.addClient('no-auth-client', MockMcpClient());
        await manager.addClientWithAuth('auth-client', MockMcpClient(), tokenValidator: tokenValidator);
        
        final summary = manager.getAuthSummary();
        expect(summary['total_clients'], equals(2));
        expect(summary['authenticated_clients'], equals(1));
        expect(summary['unauthenticated_clients'], equals(1));
        expect(summary['authentication_coverage'], equals(50));
        expect(summary['protocol_version'], equals('2025-03-26'));
        expect(summary['oauth_version'], equals('2.1'));
      });

      test('should check OAuth 2.1 compliance for all clients', () async {
        final manager = McpClientManager();
        
        await manager.addClientWithAuth('client1', MockMcpClient(), tokenValidator: tokenValidator);
        manager.addClient('client2', MockMcpClient());
        
        final compliance = await manager.checkOAuth21Compliance();
        expect(compliance['client1'], isTrue);
        expect(compliance['client2'], isTrue); // No auth = compliant
      });

      test('should get authentication status for all clients', () async {
        final manager = McpClientManager();
        
        await manager.addClientWithAuth('auth-client', MockMcpClient(), tokenValidator: tokenValidator);
        manager.addClient('no-auth-client', MockMcpClient());
        
        final status = manager.getAuthStatus();
        expect(status['auth-client']?['authenticated'], isTrue);
        expect(status['no-auth-client']?['authentication_required'], isFalse);
      });

      test('should ensure authentication for specific client', () async {
        final manager = McpClientManager();
        
        await manager.addClientWithAuth('test-client', mockClient, tokenValidator: tokenValidator);
        
        final success = await manager.ensureAuthenticated('test-client');
        expect(success, isTrue);
      });

      test('should handle OAuth operations with tools/prompts/resources', () async {
        final manager = McpClientManager();
        
        await manager.addClientWithAuth('test-client', mockClient, tokenValidator: tokenValidator);
        
        // These should work with authentication
        final tools = await manager.getTools('test-client');
        expect(tools, isNotEmpty);
        expect(tools.first['name'], equals('secure_tool')); // Should include secure tools
        
        final prompts = await manager.getPrompts('test-client');
        expect(prompts, isNotEmpty);
        
        final resources = await manager.getResources('test-client');
        expect(resources, isNotEmpty);
      });

      test('should dispose OAuth resources properly', () {
        final manager = McpClientManager();
        
        // Add some authenticated clients
        manager.addClientWithAuth('client1', MockMcpClient(), tokenValidator: tokenValidator);
        manager.addClientWithAuth('client2', MockMcpClient(), tokenValidator: tokenValidator);
        
        // Should not throw
        manager.dispose();
      });
    });

    group('Integration Tests', () {
      test('should work end-to-end with OAuth 2.1 flow', () async {
        final manager = McpClientManager();
        
        // 1. Add client with OAuth
        await manager.addClientWithAuth(
          'integration-client',
          mockClient,
          authConfig: const AuthConfig(
            scopes: ['tools:execute', 'resources:read'],
            autoRefresh: true,
          ),
          tokenValidator: tokenValidator,
        );
        
        // 2. Verify authentication status
        final summary = manager.getAuthSummary();
        expect(summary['authenticated_clients'], equals(1));
        
        // 3. Execute operations
        final tools = await manager.getTools('integration-client');
        expect(tools.length, equals(2)); // Should have both tools with auth
        
        final toolResult = await manager.executeTool(
          'secure_tool',
          {'param': 'value'},
          clientId: 'integration-client',
        );
        expect(toolResult['result'], contains('secure_tool'));
        
        // 4. Check compliance
        final compliance = await manager.checkOAuth21Compliance();
        expect(compliance['integration-client'], isTrue);
        
        // 5. Refresh tokens
        await manager.refreshAllTokens();
        
        // 6. Cleanup
        manager.dispose();
      });
    });
  });
}