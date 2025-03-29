import '../utils/logger.dart';

/// Adapter for interfacing with MCP server instances
class LlmServerAdapter {
  final dynamic _mcpServer;
  final Logger _logger = Logger.getLogger('mcp_llm.server.adapter');

  LlmServerAdapter(this._mcpServer) {
    if (!_isValidServer(_mcpServer)) {
      _logger.warning('Provided server may not be compatible with expected interface');
    }
  }

  /// Check if server implements necessary methods
  bool _isValidServer(dynamic server) {
    return server != null &&
        (_hasMethod(server, 'addTool') ||
            _hasMethod(server, 'registerTool') ||
            _hasMethod(server, 'createTool'));
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

  /// Register a tool with the server
  Future<bool> registerTool({
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema,
    required Function handler,
    bool isStreaming = false,
  }) async {
    try {
      // Try different method signatures
      if (_hasMethod(_mcpServer, 'addTool')) {
        await _mcpServer.addTool(
          name,
          description,
          inputSchema,
          handler,
          isStreaming: isStreaming,
        );
      } else if (_hasMethod(_mcpServer, 'registerTool')) {
        await _mcpServer.registerTool(
          name: name,
          description: description,
          schema: inputSchema,
          handler: handler,
          streaming: isStreaming,
        );
      } else if (_hasMethod(_mcpServer, 'createTool')) {
        await _mcpServer.createTool({
          'name': name,
          'description': description,
          'schema': inputSchema,
          'handler': handler,
          'isStreaming': isStreaming,
        });
      } else {
        _logger.error('Server does not support tool registration');
        return false;
      }

      return true;
    } catch (e) {
      _logger.error('Error registering tool: $e');
      return false;
    }
  }

  /// Get server status information
  Map<String, dynamic> getServerStatus() {
    try {
      if (_hasMethod(_mcpServer, 'getStatus')) {
        final status = _mcpServer.getStatus();
        return _convertStatusToMap(status);
      }

      return {
        'running': _mcpServer != null,
        'tools': _getToolCount(),
      };
    } catch (e) {
      _logger.error('Error getting server status: $e');
      return {'running': false, 'error': e.toString()};
    }
  }

  /// Get number of registered tools
  int _getToolCount() {
    try {
      if (_hasMethod(_mcpServer, 'listTools')) {
        final tools = _mcpServer.listTools();
        return tools.length;
      }

      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// Convert status object to map
  Map<String, dynamic> _convertStatusToMap(dynamic status) {
    if (status == null) return {};
    if (status is Map) return Map<String, dynamic>.from(status);

    try {
      return {
        'running': _getProperty(status, ['running', 'isRunning']) ?? false,
        'uptime': _getProperty(status, ['uptime', 'uptimeSeconds']),
        'connectedClients': _getProperty(status, ['connectedClients', 'clients']),
        'tools': _getProperty(status, ['registeredTools', 'tools']),
      };
    } catch (_) {
      return {'running': status.toString().contains('running')};
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