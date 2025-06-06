import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

/// Simple OAuth test with working mock
class WorkingMockMcpClient {
  bool _authenticationEnabled = false;
  
  bool get isAuthenticationEnabled => _authenticationEnabled;
  
  void enableAuthentication(TokenValidator validator) {
    _authenticationEnabled = true;
    print('Authentication enabled in mock client');
  }
  
  Future<List<dynamic>> listTools() async {
    await Future.delayed(Duration(milliseconds: 10));
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
  
  Future<dynamic> callTool(String name, Map<String, dynamic> args) async {
    await Future.delayed(Duration(milliseconds: 10));
    if (name == 'secure_tool' && !_authenticationEnabled) {
      throw Exception('Authentication required for secure tool');
    }
    return {'result': 'Tool $name executed with args: $args'};
  }
}

void main() {
  group('OAuth 2.1 Simple Tests (2025-03-26)', () {
    late McpAuthAdapter authAdapter;
    late TokenValidator tokenValidator;
    late WorkingMockMcpClient mockClient;

    setUp(() {
      // Setup working token validator
      tokenValidator = ApiKeyValidator({
        'valid-token': {
          'scopes': ['tools:execute', 'resources:read', 'prompts:read'],
          'exp': DateTime.now().add(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          'client_id': 'test-client',
          'auto_refresh': true,
        },
      });

      authAdapter = McpAuthAdapter(
        tokenValidator: tokenValidator,
        defaultConfig: const AuthConfig(
          scopes: ['tools:execute'],
        ),
      );

      mockClient = WorkingMockMcpClient();
    });

    tearDown(() {
      authAdapter.dispose();
    });

    test('should authenticate successfully', () async {
      print('Starting authentication test...');
      final result = await authAdapter.authenticate('test-client', mockClient);
      
      print('Authentication result: ${result.isAuthenticated}');
      print('Authentication error: ${result.error}');
      print('Mock client auth enabled: ${mockClient.isAuthenticationEnabled}');
      
      expect(result.isAuthenticated, isTrue);
      expect(mockClient.isAuthenticationEnabled, isTrue);
    });

    test('should validate token correctly', () async {
      final result = await tokenValidator.validateToken(
        'valid-token',
        requiredScopes: ['tools:execute'],
      );
      
      expect(result.isAuthenticated, isTrue);
      expect(result.scopes, contains('tools:execute'));
    });

    test('should work with LlmClientAdapter', () async {
      final adapter = LlmClientAdapter(
        mockClient,
        authAdapter: authAdapter,
        clientId: 'test-client',
      );
      
      // Authenticate
      final success = await adapter.authenticateClient();
      expect(success, isTrue);
      expect(adapter.isAuthenticated, isTrue);
      
      // Test operations
      final tools = await adapter.getTools();
      expect(tools, isNotEmpty);
      expect(tools.first['name'], equals('secure_tool')); // Should include secure tools
    });

    test('should check OAuth compliance', () async {
      final isCompliant = await authAdapter.checkOAuth21Compliance(mockClient);
      expect(isCompliant, isTrue);
    });

    test('should manage authentication context', () async {
      await authAdapter.authenticate('test-client', mockClient);
      
      expect(authAdapter.hasValidAuth('test-client'), isTrue);
      
      final context = authAdapter.getAuthContext('test-client');
      expect(context, isNotNull);
      expect(context!.isAuthenticated, isTrue);
      
      authAdapter.removeAuth('test-client');
      expect(authAdapter.hasValidAuth('test-client'), isFalse);
    });

    test('should work with McpClientManager', () async {
      final manager = McpClientManager();
      
      await manager.addClientWithAuth(
        'test-client',
        mockClient,
        tokenValidator: tokenValidator,
      );
      
      expect(manager.clientIds, contains('test-client'));
      expect(manager.authenticatedClients, contains('test-client'));
      
      final summary = manager.getAuthSummary();
      expect(summary['authenticated_clients'], equals(1));
      expect(summary['protocol_version'], equals('2025-03-26'));
      
      manager.dispose();
    });
  });
}