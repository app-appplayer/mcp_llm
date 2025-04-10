import '../utils/logger.dart';

/// Adapter that converts MCP client instances to LLM compatible format
class LlmClientAdapter {
  final dynamic _mcpClient;
  final Logger _logger = Logger.getLogger('mcp_llm.client_adapter');

  LlmClientAdapter(this._mcpClient) {
    if (!_isValidClient(_mcpClient)) {
      _logger.warning(
          'The provided client may not be compatible with the expected interface');
    }
  }

  /// Check if the client implements the required methods
  bool _isValidClient(dynamic client) {
    return client != null;
  }

  /// Get the list of available tools from the client
  Future<List<Map<String, dynamic>>> getTools() async {
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

  /// Get the list of available prompts from the client
  Future<List<Map<String, dynamic>>> getPrompts() async {
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

  /// Get the list of available resources from the client
  Future<List<Map<String, dynamic>>> getResources() async {
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

  /// Execute a prompt using the MCP client
  Future<Map<String, dynamic>> executePrompt(String promptName,
      Map<String, dynamic> args) async {
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

  /// Read a resource using the MCP client
  Future<Map<String, dynamic>> readResource(String resourceUri) async {
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

  /// Execute a tool using the MCP client
  Future<Map<String, dynamic>> executeTool(String toolName,
      Map<String, dynamic> args) async {
    try {
      final result = await _mcpClient.callTool(toolName, args);

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
}

