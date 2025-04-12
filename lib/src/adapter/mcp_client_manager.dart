import '../utils/logger.dart';
import 'llm_client_adapter.dart';

/// Manages multiple MCP clients for a single LLM client
class McpClientManager {
  /// Map of MCP client IDs to their instances
  final Map<String, dynamic> _mcpClients = {};

  /// Map of MCP client IDs to their adapters
  final Map<String, LlmClientAdapter> _adapters = {};

  /// Default client ID to use when none specified
  String? _defaultClientId;

  /// Logger instance
  final Logger _logger = Logger.getLogger('mcp_llm.mcp_client_manager');

  /// Create a new MCP client manager
  McpClientManager({dynamic defaultClient, String? defaultClientId}) {
    if (defaultClient != null) {
      final id = defaultClientId ?? 'default';
      addClient(id, defaultClient);
      _defaultClientId = id;
    }
  }

  /// Add a new MCP client
  void addClient(String clientId, dynamic mcpClient) {
    if (_mcpClients.containsKey(clientId)) {
      _logger.warning('Replacing existing MCP client with ID: $clientId');
    }

    _mcpClients[clientId] = mcpClient;
    _adapters[clientId] = LlmClientAdapter(mcpClient);

    // Set as default if this is the first client
    _defaultClientId ??= clientId;

    _logger.info('Added MCP client: $clientId');
  }

  /// Remove a client
  void removeClient(String clientId) {
    _mcpClients.remove(clientId);
    _adapters.remove(clientId);

    // Clear default if it was this client
    if (_defaultClientId == clientId) {
      _defaultClientId = _mcpClients.isNotEmpty ? _mcpClients.keys.first : null;
    }

    _logger.info('Removed MCP client: $clientId');
  }

  /// Set the default client
  void setDefaultClient(String clientId) {
    if (!_mcpClients.containsKey(clientId)) {
      throw StateError('Cannot set default: Client ID not found: $clientId');
    }

    _defaultClientId = clientId;
    _logger.info('Set default MCP client to: $clientId');
  }

  /// Get a client by ID
  dynamic getClient(String clientId) {
    return _mcpClients[clientId];
  }

  /// Get default client
  dynamic get defaultClient {
    if (_defaultClientId == null) {
      return null;
    }
    return _mcpClients[_defaultClientId];
  }

  /// Get an adapter by client ID
  LlmClientAdapter? getAdapter(String clientId) {
    return _adapters[clientId];
  }

  /// Get default adapter
  LlmClientAdapter? get defaultAdapter {
    if (_defaultClientId == null) {
      return null;
    }
    return _adapters[_defaultClientId];
  }

  /// Get all client IDs
  List<String> get clientIds {
    return _mcpClients.keys.toList();
  }

  /// Get count of clients
  int get clientCount {
    return _mcpClients.length;
  }

  /// Get available tools from all clients or a specific client
  Future<List<Map<String, dynamic>>> getTools([String? clientId]) async {
    final allTools = <Map<String, dynamic>>[];

    // Get tools from specific client only
    if (clientId != null) {
      final adapter = _adapters[clientId];
      if (adapter == null) {
        _logger.warning('Client not found for getTools: $clientId');
        return [];
      }

      try {
        final tools = await adapter.getTools();
        return tools.map((tool) => {...tool, 'clientId': clientId}).toList();
      } catch (e) {
        _logger.error('Error getting tools from client $clientId: $e');
        return [];
      }
    }

    // Get tools from all clients
    for (final entry in _adapters.entries) {
      try {
        final clientTools = await entry.value.getTools();

        // Create a new map with clientId added
        final toolsWithClientId = clientTools.map((tool) =>
        {...tool, 'clientId': entry.key}
        ).toList();

        allTools.addAll(toolsWithClientId);
      } catch (e) {
        _logger.error('Error getting tools from client ${entry.key}: $e');
      }
    }

    return allTools;
  }

  /// Get available prompts from all clients or a specific client
  Future<List<Map<String, dynamic>>> getPrompts([String? clientId]) async {
    final allPrompts = <Map<String, dynamic>>[];

    // Get prompts from specific client only
    if (clientId != null) {
      final adapter = _adapters[clientId];
      if (adapter == null) {
        _logger.warning('Client not found for getPrompts: $clientId');
        return [];
      }

      try {
        final prompts = await adapter.getPrompts();
        return prompts.map((prompt) => {...prompt, 'clientId': clientId}).toList();
      } catch (e) {
        _logger.error('Error getting prompts from client $clientId: $e');
        return [];
      }
    }

    // Get prompts from all clients
    for (final entry in _adapters.entries) {
      try {
        final clientPrompts = await entry.value.getPrompts();

        // Create a new map with clientId added
        final promptsWithClientId = clientPrompts.map((prompt) =>
        {...prompt, 'clientId': entry.key}
        ).toList();

        allPrompts.addAll(promptsWithClientId);
      } catch (e) {
        _logger.error('Error getting prompts from client ${entry.key}: $e');
      }
    }

    return allPrompts;
  }

  /// Get available resources from all clients or a specific client
  Future<List<Map<String, dynamic>>> getResources([String? clientId]) async {
    final allResources = <Map<String, dynamic>>[];

    // Get resources from specific client only
    if (clientId != null) {
      final adapter = _adapters[clientId];
      if (adapter == null) {
        _logger.warning('Client not found for getResources: $clientId');
        return [];
      }

      try {
        final resources = await adapter.getResources();
        return resources.map((resource) => {...resource, 'clientId': clientId}).toList();
      } catch (e) {
        _logger.error('Error getting resources from client $clientId: $e');
        return [];
      }
    }

    // Get resources from all clients
    for (final entry in _adapters.entries) {
      try {
        final clientResources = await entry.value.getResources();

        // Create a new map with clientId added
        final resourcesWithClientId = clientResources.map((resource) =>
        {...resource, 'clientId': entry.key}
        ).toList();

        allResources.addAll(resourcesWithClientId);
      } catch (e) {
        _logger.error('Error getting resources from client ${entry.key}: $e');
      }
    }

    return allResources;
  }

  /// Get prompts organized by client
  Future<Map<String, List<Map<String, dynamic>>>> getPromptsByClient() async {
    final result = <String, List<Map<String, dynamic>>>{};

    for (final entry in _adapters.entries) {
      try {
        final clientPrompts = await entry.value.getPrompts();
        result[entry.key] = clientPrompts;
      } catch (e) {
        _logger.error('Error getting prompts from client ${entry.key}: $e');
        result[entry.key] = [];
      }
    }

    return result;
  }

  /// Get resources organized by client
  Future<Map<String, List<Map<String, dynamic>>>> getResourcesByClient() async {
    final result = <String, List<Map<String, dynamic>>>{};

    for (final entry in _adapters.entries) {
      try {
        final clientResources = await entry.value.getResources();
        result[entry.key] = clientResources;
      } catch (e) {
        _logger.error('Error getting resources from client ${entry.key}: $e');
        result[entry.key] = [];
      }
    }

    return result;
  }

  /// Get tools organized by client
  Future<Map<String, List<Map<String, dynamic>>>> getToolsByClient() async {
    final result = <String, List<Map<String, dynamic>>>{};

    for (final entry in _adapters.entries) {
      try {
        final clientTools = await entry.value.getTools();
        result[entry.key] = clientTools;
      } catch (e) {
        _logger.error('Error getting tools from client ${entry.key}: $e');
        result[entry.key] = [];
      }
    }

    return result;
  }

  /// Execute a tool on a specific client or try all clients
  Future<dynamic> executeTool(
      String toolName,
      Map<String, dynamic> args, {
        String? clientId,
        bool tryAllClients = false,
      }) async {
    // Try a specific client if provided
    if (clientId != null) {
      final adapter = _adapters[clientId];
      if (adapter == null) {
        if (!tryAllClients) {
          throw Exception('Client not found: $clientId');
        }
      } else {
        try {
          final result = await adapter.executeTool(toolName, args);
          if (!result.containsKey('error')) {
            return result;
          }
          if (!tryAllClients) {
            return result; // Return result even with error if not trying all clients
          }
        } catch (e) {
          _logger.warning('Error executing tool $toolName on client $clientId: $e');
          if (!tryAllClients) {
            throw Exception('Tool execution failed on specified client: $e');
          }
        }
      }
    }

    // Try default client if no specific client or default client wasn't already tried
    if (clientId == null && _defaultClientId != null && _defaultClientId != clientId) {
      final adapter = _adapters[_defaultClientId!];
      if (adapter != null) {
        try {
          final result = await adapter.executeTool(toolName, args);
          if (!result.containsKey('error')) {
            return result;
          }
          if (!tryAllClients) {
            return result;
          }
        } catch (e) {
          _logger.warning('Error executing tool $toolName on default client: $e');
          if (!tryAllClients) {
            throw Exception('Tool execution failed on default client: $e');
          }
        }
      }
    }

    // If tryAllClients is true, try all other clients
    if (tryAllClients) {
      Exception? lastError;

      for (final entry in _adapters.entries) {
        // Skip already tried clients
        if (entry.key == clientId || entry.key == _defaultClientId) {
          continue;
        }

        try {
          final result = await entry.value.executeTool(toolName, args);
          if (!result.containsKey('error')) {
            _logger.debug('Successfully executed tool $toolName on client ${entry.key}');
            return result;
          }
        } catch (e) {
          _logger.warning('Error executing tool $toolName on client ${entry.key}: $e');
          lastError = Exception('Failed on client ${entry.key}: $e');
        }
      }

      // If we got here, all clients failed
      if (lastError != null) {
        throw lastError;
      }
    }

    throw Exception('Tool $toolName not found or execution failed');
  }

  /// Execute a tool on all clients and collect results
  Future<Map<String, dynamic>> executeToolOnAllClients(
      String toolName,
      Map<String, dynamic> args
      ) async {
    final results = <String, dynamic>{};
    final futures = <Future<void>>[];

    for (final entry in _adapters.entries) {
      futures.add(_executeToolSafe(entry.key, entry.value, toolName, args)
          .then((result) {
        results[entry.key] = result;
      }));
    }

    await Future.wait(futures);
    return results;
  }

  // Helper method to safely execute tool
  Future<dynamic> _executeToolSafe(
      String clientId,
      LlmClientAdapter adapter,
      String toolName,
      Map<String, dynamic> args
      ) async {
    try {
      return await adapter.executeTool(toolName, args);
    } catch (e) {
      _logger.error('Error executing tool $toolName on client $clientId: $e');
      return {'error': e.toString()};
    }
  }

  /// Find all clients that have a specific tool
  Future<List<String>> findClientsWithTool(String toolName) async {
    final result = <String>[];
    final futures = <Future<void>>[];

    for (final entry in _adapters.entries) {
      futures.add(
          _hasToolSafe(entry.key, entry.value, toolName).then((hasTool) {
            if (hasTool) {
              result.add(entry.key);
            }
          })
      );
    }

    await Future.wait(futures);
    return result;
  }

  // Helper method to check if client has a tool
  Future<bool> _hasToolSafe(
      String clientId,
      LlmClientAdapter adapter,
      String toolName
      ) async {
    try {
      final tools = await adapter.getTools();
      return tools.any((tool) => tool['name'] == toolName);
    } catch (e) {
      _logger.warning('Error checking tool $toolName for client $clientId: $e');
      return false;
    }
  }

  /// Execute a prompt using MCP clients
  Future<Map<String, dynamic>> executePrompt(
      String promptName,
      Map<String, dynamic> args, {
        String? clientId,
        bool tryAllClients = false,
      }) async {
    // Try a specific client if provided
    if (clientId != null) {
      final adapter = _adapters[clientId];
      if (adapter == null) {
        if (!tryAllClients) {
          throw Exception('Client not found: $clientId');
        }
      } else {
        try {
          final result = await adapter.executePrompt(promptName, args);
          if (!result.containsKey('error')) {
            return result;
          }
          if (!tryAllClients) {
            return result; // Return result even with error if not trying all clients
          }
        } catch (e) {
          _logger.warning('Error executing prompt $promptName on client $clientId: $e');
          if (!tryAllClients) {
            throw Exception('Prompt execution failed on specified client: $e');
          }
        }
      }
    }

    // Try default client if no specific client or default client wasn't already tried
    if (clientId == null && _defaultClientId != null && _defaultClientId != clientId) {
      final adapter = _adapters[_defaultClientId!];
      if (adapter != null) {
        try {
          final result = await adapter.executePrompt(promptName, args);
          if (!result.containsKey('error')) {
            return result;
          }
          if (!tryAllClients) {
            return result;
          }
        } catch (e) {
          _logger.warning('Error executing prompt $promptName on default client: $e');
          if (!tryAllClients) {
            throw Exception('Prompt execution failed on default client: $e');
          }
        }
      }
    }

    // If tryAllClients is true, try all other clients
    if (tryAllClients) {
      Exception? lastError;

      for (final entry in _adapters.entries) {
        // Skip already tried clients
        if (entry.key == clientId || entry.key == _defaultClientId) {
          continue;
        }

        try {
          final result = await entry.value.executePrompt(promptName, args);
          if (!result.containsKey('error')) {
            _logger.debug('Successfully executed prompt $promptName on client ${entry.key}');
            return result;
          }
        } catch (e) {
          _logger.warning('Error executing prompt $promptName on client ${entry.key}: $e');
          lastError = Exception('Failed on client ${entry.key}: $e');
        }
      }

      // If we got here, all clients failed
      if (lastError != null) {
        throw lastError;
      }
    }

    throw Exception('Prompt $promptName not found or execution failed');
  }

  /// Read a resource using MCP clients
  Future<Map<String, dynamic>> readResource(
      String resourceUri, {
        String? clientId,
        bool tryAllClients = false,
      }) async {
    // Try a specific client if provided
    if (clientId != null) {
      final adapter = _adapters[clientId];
      if (adapter == null) {
        if (!tryAllClients) {
          throw Exception('Client not found: $clientId');
        }
      } else {
        try {
          final result = await adapter.readResource(resourceUri);
          if (!result.containsKey('error')) {
            return result;
          }
          if (!tryAllClients) {
            return result; // Return result even with error if not trying all clients
          }
        } catch (e) {
          _logger.warning('Error reading resource $resourceUri on client $clientId: $e');
          if (!tryAllClients) {
            throw Exception('Resource reading failed on specified client: $e');
          }
        }
      }
    }

    // Try default client if no specific client or default client wasn't already tried
    if (clientId == null && _defaultClientId != null && _defaultClientId != clientId) {
      final adapter = _adapters[_defaultClientId!];
      if (adapter != null) {
        try {
          final result = await adapter.readResource(resourceUri);
          if (!result.containsKey('error')) {
            return result;
          }
          if (!tryAllClients) {
            return result;
          }
        } catch (e) {
          _logger.warning('Error reading resource $resourceUri on default client: $e');
          if (!tryAllClients) {
            throw Exception('Resource reading failed on default client: $e');
          }
        }
      }
    }

    // If tryAllClients is true, try all other clients
    if (tryAllClients) {
      Exception? lastError;

      for (final entry in _adapters.entries) {
        // Skip already tried clients
        if (entry.key == clientId || entry.key == _defaultClientId) {
          continue;
        }

        try {
          final result = await entry.value.readResource(resourceUri);
          if (!result.containsKey('error')) {
            _logger.debug('Successfully read resource ${entry.key}');
            return result;
          }
        } catch (e) {
          _logger.warning('Error read resource ${entry.key}: $e');
          lastError = Exception('Failed on client ${entry.key}: $e');
        }
      }

      // If we got here, all clients failed
      if (lastError != null) {
        throw lastError;
      }
    }

    throw Exception('Resource $resourceUri not found or reading failed');
  }
}
