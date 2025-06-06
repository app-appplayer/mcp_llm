import '../utils/logger.dart';
import 'mcp_auth_adapter.dart';

/// Adapter that converts MCP client instances to LLM compatible format with OAuth 2.1 support
class LlmClientAdapter {
  final dynamic _mcpClient;
  final McpAuthAdapter? _authAdapter;
  final String? _clientId;
  final Logger _logger = Logger('mcp_llm.client_adapter');

  LlmClientAdapter(
    this._mcpClient, {
    McpAuthAdapter? authAdapter,
    String? clientId,
  }) : _authAdapter = authAdapter,
       _clientId = clientId {
    if (!_isValidClient(_mcpClient)) {
      _logger.warning(
          'The provided client may not be compatible with the expected interface');
    }
    
    // Log OAuth 2.1 support status
    if (_authAdapter != null) {
      _logger.info('OAuth 2.1 authentication adapter configured for client: $_clientId');
    }
  }

  /// Check if the client implements the required methods
  bool _isValidClient(dynamic client) {
    return client != null;
  }

  /// Authenticate the MCP client using OAuth 2.1 (2025-03-26)
  Future<bool> authenticateClient({AuthConfig? authConfig}) async {
    if (_authAdapter == null || _clientId == null) {
      _logger.warning('OAuth adapter or client ID not configured');
      return false;
    }

    try {
      final result = await _authAdapter.authenticate(_clientId, _mcpClient, config: authConfig);
      if (result.isAuthenticated) {
        _logger.info('OAuth 2.1 authentication successful for client: $_clientId');
        return true;
      } else {
        _logger.warning('OAuth 2.1 authentication failed: ${result.error}');
        return false;
      }
    } catch (e) {
      _logger.error('OAuth 2.1 authentication error: $e');
      return false;
    }
  }

  /// Check if client has valid OAuth 2.1 authentication
  bool get isAuthenticated {
    if (_authAdapter == null || _clientId == null) return true; // No auth required
    return _authAdapter.hasValidAuth(_clientId);
  }

  /// Get OAuth 2.1 authentication context
  AuthResult? get authContext {
    if (_authAdapter == null || _clientId == null) return null;
    return _authAdapter.getAuthContext(_clientId);
  }

  /// Ensure authentication before operations (2025-03-26 compliance)
  Future<bool> _ensureAuthenticated() async {
    if (_authAdapter == null || _clientId == null) return true; // No auth required
    
    if (!isAuthenticated) {
      _logger.info('Authentication required, attempting OAuth 2.1 authentication');
      return await authenticateClient();
    }
    
    return true;
  }

  /// Get the list of available tools from the client with OAuth 2.1 authentication
  Future<List<Map<String, dynamic>>> getTools() async {
    // Ensure OAuth 2.1 authentication for 2025-03-26 compliance
    if (!await _ensureAuthenticated()) {
      _logger.error('OAuth 2.1 authentication failed for getTools operation');
      return [];
    }

    try {
      final List<dynamic> toolsList = await _mcpClient.listTools();
      _logger.info('listTools method was called successfully');

      if (toolsList.isNotEmpty) {
        _logger.debug('First tool format: ${toolsList.first.runtimeType}');
      }

      return toolsList.map<Map<String, dynamic>>((tool) {
        if (tool is Map<String, dynamic>) {
          return tool;
        } else {
          try {
            // Try toJson for non-Map objects
            // ignore: avoid_dynamic_calls
            return tool.toJson();
          } catch (e) {
            _logger.warning('Failed to convert tool to Map: $e');
            return {
              'name': tool.toString(),
              'description': '',
              'inputSchema': {}
            };
          }
        }
      }).toList();
    } catch (e) {
      _logger.error('Failed to retrieve tool list: $e');
      return [];
    }
  }

  /// Get the list of available prompts from the client with OAuth 2.1 authentication
  Future<List<Map<String, dynamic>>> getPrompts() async {
    // Ensure OAuth 2.1 authentication for 2025-03-26 compliance
    if (!await _ensureAuthenticated()) {
      _logger.error('OAuth 2.1 authentication failed for getPrompts operation');
      return [];
    }

    try {
      final List<dynamic> promptsList = await _mcpClient.listPrompts();
      _logger.info('listPrompts method was called successfully');

      if (promptsList.isNotEmpty) {
        _logger.debug('First prompt format: ${promptsList.first.runtimeType}');
      }

      return promptsList.map<Map<String, dynamic>>((prompt) {
        if (prompt is Map<String, dynamic>) {
          return prompt;
        } else {
          try {
            // Try toJson for non-Map objects
            // ignore: avoid_dynamic_calls
            return prompt.toJson();
          } catch (e) {
            _logger.warning('Failed to convert prompt to Map: $e');
            return {
              'name': prompt.toString(),
              'description': '',
              'arguments': []
            };
          }
        }
      }).toList();
    } catch (e) {
      _logger.error('Failed to retrieve prompt list: $e');
      return [];
    }
  }

  /// Get the list of available resources from the client with OAuth 2.1 authentication
  Future<List<Map<String, dynamic>>> getResources() async {
    // Ensure OAuth 2.1 authentication for 2025-03-26 compliance
    if (!await _ensureAuthenticated()) {
      _logger.error('OAuth 2.1 authentication failed for getResources operation');
      return [];
    }

    try {
      final List<dynamic> resourcesList = await _mcpClient.listResources();
      _logger.info('listResources method was called successfully');

      if (resourcesList.isNotEmpty) {
        _logger.debug('First resource format: ${resourcesList.first.runtimeType}');
      }

      return resourcesList.map<Map<String, dynamic>>((resource) {
        if (resource is Map<String, dynamic>) {
          return resource;
        } else {
          try {
            // Try toJson for non-Map objects
            // ignore: avoid_dynamic_calls
            return resource.toJson();
          } catch (e) {
            _logger.warning('Failed to convert resource to Map: $e');
            return {
              'name': resource.toString(),
              'description': '',
              'uri': '',
              'mimeType': ''
            };
          }
        }
      }).toList();
    } catch (e) {
      _logger.error('Failed to retrieve resource list: $e');
      return [];
    }
  }

  /// Execute a prompt using the MCP client with OAuth 2.1 authentication
  Future<Map<String, dynamic>> executePrompt(String promptName,
      Map<String, dynamic> args) async {
    // Ensure OAuth 2.1 authentication for 2025-03-26 compliance
    if (!await _ensureAuthenticated()) {
      _logger.error('OAuth 2.1 authentication failed for executePrompt operation');
      return {'error': 'OAuth 2.1 authentication required'};
    }

    try {
      final result = await _mcpClient.callPrompt(promptName, args);

      // Return as is if it's already Map<String, dynamic>
      if (result is Map<String, dynamic>) {
        return result;
      }
      // If it's a Map but with different type
      else if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      // If it's an object with toJson method
      else {
        try {
          // ignore: avoid_dynamic_calls
          return result.toJson();
        } catch (e) {
          // Convert to string
          return {'content': result.toString()};
        }
      }
    } catch (e) {
      _logger.error('Failed to execute prompt: $e');
      return {'error': e.toString()};
    }
  }

  /// Read a resource using the MCP client with OAuth 2.1 authentication
  Future<Map<String, dynamic>> readResource(String resourceUri) async {
    // Ensure OAuth 2.1 authentication for 2025-03-26 compliance
    if (!await _ensureAuthenticated()) {
      _logger.error('OAuth 2.1 authentication failed for readResource operation');
      return {'error': 'OAuth 2.1 authentication required'};
    }

    try {
      final result = await _mcpClient.readResource(resourceUri);

      // Return as is if it's already Map<String, dynamic>
      if (result is Map<String, dynamic>) {
        return result;
      }
      // If it's a Map but with different type
      else if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      // If it's an object with toJson method
      else {
        try {
          // ignore: avoid_dynamic_calls
          return result.toJson();
        } catch (e) {
          // Convert to string
          return {'content': result.toString()};
        }
      }
    } catch (e) {
      _logger.error('Failed to read resource: $e');
      return {'error': e.toString()};
    }
  }

  /// Execute a tool using the MCP client with OAuth 2.1 authentication
  Future<Map<String, dynamic>> executeTool(String toolName,
      Map<String, dynamic> args) async {
    // Ensure OAuth 2.1 authentication for 2025-03-26 compliance
    if (!await _ensureAuthenticated()) {
      _logger.error('OAuth 2.1 authentication failed for executeTool operation');
      return {'error': 'OAuth 2.1 authentication required'};
    }

    try {
      final result = await _mcpClient.callTool(toolName, args);

      // Handle different return types
      if (result is Map<String, dynamic>) {
        return result;
      } else if (result is Map) {
        return Map<String, dynamic>.from(result);
      } else {
        try {
          return result.toJson();
        } catch (e) {
          // Convert to string
          return {'content': result.toString()};
        }
      }
    } catch (e) {
      _logger.error('Failed to execute tool: $e');
      return {'error': e.toString()};
    }
  }

  /// Refresh OAuth 2.1 token manually
  Future<bool> refreshToken() async {
    if (_authAdapter == null || _clientId == null) {
      _logger.warning('OAuth adapter or client ID not configured for token refresh');
      return false;
    }

    try {
      await _authAdapter.refreshToken(_clientId);
      _logger.info('OAuth 2.1 token refreshed successfully for client: $_clientId');
      return true;
    } catch (e) {
      _logger.error('OAuth 2.1 token refresh failed: $e');
      return false;
    }
  }

  /// Check OAuth 2.1 compliance of the MCP client
  Future<bool> checkOAuth21Compliance() async {
    if (_authAdapter == null) {
      _logger.info('No OAuth adapter configured, skipping compliance check');
      return true; // No auth required = compliant
    }

    try {
      return await _authAdapter.checkOAuth21Compliance(_mcpClient);
    } catch (e) {
      _logger.error('OAuth 2.1 compliance check failed: $e');
      return false;
    }
  }

  /// Get OAuth 2.1 authentication status
  Map<String, dynamic> getAuthStatus() {
    if (_authAdapter == null || _clientId == null) {
      return {
        'authentication_required': false,
        'status': 'no_auth_configured',
        'protocol_version': '2025-03-26',
      };
    }

    final context = authContext;
    return {
      'authentication_required': true,
      'authenticated': isAuthenticated,
      'client_id': _clientId,
      'access_token_expires_at': context?.expiresAt?.toIso8601String(),
      'scopes': context?.scopes ?? [],
      'auth_method': context?.metadata['auth_method'],
      'protocol_version': context?.metadata['protocol_version'] ?? '2025-03-26',
      'needs_refresh': context?.needsRefresh ?? false,
      'last_error': context?.error,
    };
  }

  /// Remove OAuth 2.1 authentication
  void removeAuthentication() {
    if (_authAdapter != null && _clientId != null) {
      _authAdapter.removeAuth(_clientId);
      _logger.info('OAuth 2.1 authentication removed for client: $_clientId');
    }
  }
}

