import '../utils/logger.dart';

/// Adapter for converting MCP client instances to LLM-compatible format
class LlmClientAdapter {
  final dynamic _mcpClient;
  final Logger _logger = Logger.getLogger('mcp_llm.client.adapter');

  LlmClientAdapter(this._mcpClient) {
    if (!_isValidClient(_mcpClient)) {
      _logger.warning('Provided client may not be compatible with expected interface');
    }
  }

  /// Check if client implements necessary methods
  bool _isValidClient(dynamic client) {
    return client != null &&
        (_hasMethod(client, 'listTools') || _hasMethod(client, 'getTools')) &&
        (_hasMethod(client, 'executeTool') || _hasMethod(client, 'callTool'));
  }

  /// Check if object has a specific method
  bool _hasMethod(dynamic obj, String methodName) {
    try {
      return obj != null &&
          obj.runtimeType.toString().contains(methodName);
    } catch (_) {
      return false;
    }
  }

  /// Get available tools from client
  Future<List<Map<String, dynamic>>> getTools() async {
    try {
      List<dynamic> toolsList;

      if (_hasMethod(_mcpClient, 'listTools')) {
        toolsList = await _mcpClient.listTools();
      } else if (_hasMethod(_mcpClient, 'getTools')) {
        toolsList = await _mcpClient.getTools();
      } else {
        _logger.error('Client does not support tool listing');
        return [];
      }

      // Convert tools to map format
      return toolsList.map<Map<String, dynamic>>((tool) {
        return _convertToolToMap(tool);
      }).toList();
    } catch (e) {
      _logger.error('Error getting tools from client: $e');
      return [];
    }
  }

  /// Execute a tool on the MCP client
  Future<Map<String, dynamic>> executeTool(String toolName, Map<String, dynamic> args) async {
    try {
      dynamic result;

      if (_hasMethod(_mcpClient, 'executeTool')) {
        result = await _mcpClient.executeTool(toolName, args);
      } else if (_hasMethod(_mcpClient, 'callTool')) {
        result = await _mcpClient.callTool(name: toolName, arguments: args);
      } else {
        _logger.error('Client does not support tool execution');
        return {'error': 'Tool execution not supported'};
      }

      return _convertResultToMap(result);
    } catch (e) {
      _logger.error('Error executing tool: $e');
      return {'error': e.toString()};
    }
  }

  /// Convert tool object to map
  Map<String, dynamic> _convertToolToMap(dynamic tool) {
    try {
      return {
        'name': _getProperty(tool, ['name', 'id']) ?? 'Unknown',
        'description': _getProperty(tool, ['description', 'desc']) ?? '',
        'inputSchema': _getProperty(tool, ['inputSchema', 'schema', 'parameters']) ?? {},
        'version': _getProperty(tool, ['version']) ?? '1.0.0',
      };
    } catch (e) {
      _logger.warning('Error converting tool to map: $e');
      return {'name': 'Unknown', 'description': 'Error parsing tool'};
    }
  }

  /// Convert result object to map
  Map<String, dynamic> _convertResultToMap(dynamic result) {
    if (result == null) return {};
    if (result is Map) return Map<String, dynamic>.from(result);

    try {
      return {
        'content': _getProperty(result, ['content', 'result']),
        'success': _getProperty(result, ['success', 'isSuccess']) ?? true,
        'error': _getProperty(result, ['error', 'errorMessage']),
      };
    } catch (e) {
      return {'content': result.toString()};
    }
  }

  /// Get a property from an object using multiple possible names
  dynamic _getProperty(dynamic obj, List<String> possibleNames) {
    if (obj == null) return null;

    for (final name in possibleNames) {
      try {
        dynamic value;

        // Try accessing as map
        if (obj is Map) {
          value = obj[name];
        } else {
          // Try accessing as property
          value = obj.$name;
        }

        if (value != null) return value;
      } catch (_) {
        // Property not found with this name, try next
      }
    }

    return null;
  }
}