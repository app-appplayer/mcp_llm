import '../utils/logger.dart';
import 'llm_server_adapter.dart';

/// Manages multiple MCP servers
class McpServerManager {
  /// Map of MCP server IDs to their instances
  final Map<String, dynamic> _mcpServers = {};

  /// Map of MCP server IDs to their adapters
  final Map<String, LlmServerAdapter> _adapters = {};

  /// Default server ID to use when none specified
  String? _defaultServerId;

  /// Logger instance
  final Logger _logger = Logger.getLogger('mcp_llm.mcp_server_manager');

  /// Create a new MCP server manager
  McpServerManager({dynamic defaultServer, String? defaultServerId}) {
    if (defaultServer != null) {
      final id = defaultServerId ?? 'default';
      addServer(id, defaultServer);
      _defaultServerId = id;
    }
  }

  /// Add a new MCP server
  void addServer(String serverId, dynamic mcpServer) {
    if (_mcpServers.containsKey(serverId)) {
      _logger.warning('Replacing existing MCP server with ID: $serverId');
    }

    _mcpServers[serverId] = mcpServer;
    _adapters[serverId] = LlmServerAdapter(mcpServer);

    // Set as default if this is the first server
    _defaultServerId ??= serverId;

    _logger.info('Added MCP server: $serverId');
  }

  /// Remove a server
  void removeServer(String serverId) {
    _mcpServers.remove(serverId);
    _adapters.remove(serverId);

    // Clear default if it was this server
    if (_defaultServerId == serverId) {
      _defaultServerId = _mcpServers.isNotEmpty ? _mcpServers.keys.first : null;
    }

    _logger.info('Removed MCP server: $serverId');
  }

  /// Set the default server
  void setDefaultServer(String serverId) {
    if (!_mcpServers.containsKey(serverId)) {
      throw StateError('Cannot set default: Server ID not found: $serverId');
    }

    _defaultServerId = serverId;
    _logger.info('Set default MCP server to: $serverId');
  }

  /// Get a server by ID
  dynamic getServer(String serverId) {
    return _mcpServers[serverId];
  }

  /// Get default server
  dynamic get defaultServer {
    if (_defaultServerId == null) {
      return null;
    }
    return _mcpServers[_defaultServerId];
  }

  /// Get an adapter by server ID
  LlmServerAdapter? getAdapter(String serverId) {
    return _adapters[serverId];
  }

  /// Get default adapter
  LlmServerAdapter? get defaultAdapter {
    if (_defaultServerId == null) {
      return null;
    }
    return _adapters[_defaultServerId];
  }

  /// Get all server IDs
  List<String> get serverIds {
    return _mcpServers.keys.toList();
  }

  /// Get count of servers
  int get serverCount {
    return _mcpServers.length;
  }

  /// Register a tool with the server
  Future<bool> registerTool({
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema,
    required ToolHandler handler,
    String? serverId,
    bool tryAllServers = false,
  }) async {
    final effectiveServerId = serverId ?? _defaultServerId;
    if (effectiveServerId == null) {
      _logger.error('No server specified and no default server set');
      return false;
    }

    final adapter = _adapters[effectiveServerId];
    if (adapter == null) {
      _logger.error('Server not found: $effectiveServerId');
      return false;
    }

    try {
      return await adapter.registerTool(
        name: name,
        description: description,
        inputSchema: inputSchema,
        handler: handler,
      );
    } catch (e) {
      _logger.error('Error registering tool on server $effectiveServerId: $e');
      return false;
    }
  }

  /// Register a prompt with the server
  Future<bool> registerPrompt({
    required String name,
    required String description,
    required List<dynamic> arguments,
    required PromptHandler handler,
    String? serverId,
  }) async {
    final effectiveServerId = serverId ?? _defaultServerId;
    if (effectiveServerId == null) {
      _logger.error('No server specified and no default server set');
      return false;
    }

    final adapter = _adapters[effectiveServerId];
    if (adapter == null) {
      _logger.error('Server not found: $effectiveServerId');
      return false;
    }

    try {
      return await adapter.registerPrompt(
        name: name,
        description: description,
        arguments: arguments,
        handler: handler,
      );
    } catch (e) {
      _logger.error('Error registering prompt on server $effectiveServerId: $e');
      return false;
    }
  }

  /// Register a resource with the server
  Future<bool> registerResource({
    required String uri,
    required String name,
    required String description,
    required String mimeType,
    required ResourceHandler handler,
    String? serverId,
  }) async {
    final effectiveServerId = serverId ?? _defaultServerId;
    if (effectiveServerId == null) {
      _logger.error('No server specified and no default server set');
      return false;
    }

    final adapter = _adapters[effectiveServerId];
    if (adapter == null) {
      _logger.error('Server not found: $effectiveServerId');
      return false;
    }

    try {
      return await adapter.registerResource(
        uri: uri,
        name: name,
        description: description,
        mimeType: mimeType,
        handler: handler,
      );
    } catch (e) {
      _logger.error('Error registering resource on server $effectiveServerId: $e');
      return false;
    }
  }

  /// Get tools from server(s)
  Future<List<Map<String, dynamic>>> getTools([String? serverId]) async {
    final allTools = <Map<String, dynamic>>[];

    // Get tools from specific server only
    if (serverId != null) {
      final adapter = _adapters[serverId];
      if (adapter == null) {
        _logger.warning('Server not found for getTools: $serverId');
        return [];
      }

      try {
        final tools = await adapter.getTools();
        return tools.map((tool) => {...tool, 'serverId': serverId}).toList();
      } catch (e) {
        _logger.error('Error getting tools from server $serverId: $e');
        return [];
      }
    }

    // Get tools from all servers
    for (final entry in _adapters.entries) {
      try {
        final serverTools = await entry.value.getTools();

        // Create a new map with serverId added
        final toolsWithServerId = serverTools.map((tool) =>
        {...tool, 'serverId': entry.key}
        ).toList();

        allTools.addAll(toolsWithServerId);
      } catch (e) {
        _logger.error('Error getting tools from server ${entry.key}: $e');
      }
    }

    return allTools;
  }

  /// Get prompts from server(s)
  Future<List<Map<String, dynamic>>> getPrompts([String? serverId]) async {
    final allPrompts = <Map<String, dynamic>>[];

    // Get prompts from specific server only
    if (serverId != null) {
      final adapter = _adapters[serverId];
      if (adapter == null) {
        _logger.warning('Server not found for getPrompts: $serverId');
        return [];
      }

      try {
        final prompts = await adapter.getPrompts();
        return prompts.map((prompt) => {...prompt, 'serverId': serverId}).toList();
      } catch (e) {
        _logger.error('Error getting prompts from server $serverId: $e');
        return [];
      }
    }

    // Get prompts from all servers
    for (final entry in _adapters.entries) {
      try {
        final serverPrompts = await entry.value.getPrompts();

        // Create a new map with serverId added
        final promptsWithServerId = serverPrompts.map((prompt) =>
        {...prompt, 'serverId': entry.key}
        ).toList();

        allPrompts.addAll(promptsWithServerId);
      } catch (e) {
        _logger.error('Error getting prompts from server ${entry.key}: $e');
      }
    }

    return allPrompts;
  }

  /// Get resources from server(s)
  Future<List<Map<String, dynamic>>> getResources([String? serverId]) async {
    final allResources = <Map<String, dynamic>>[];

    // Get resources from specific server only
    if (serverId != null) {
      final adapter = _adapters[serverId];
      if (adapter == null) {
        _logger.warning('Server not found for getResources: $serverId');
        return [];
      }

      try {
        final resources = await adapter.getResources();
        return resources.map((resource) => {...resource, 'serverId': serverId}).toList();
      } catch (e) {
        _logger.error('Error getting resources from server $serverId: $e');
        return [];
      }
    }

    // Get resources from all servers
    for (final entry in _adapters.entries) {
      try {
        final serverResources = await entry.value.getResources();

        // Create a new map with serverId added
        final resourcesWithServerId = serverResources.map((resource) =>
        {...resource, 'serverId': entry.key}
        ).toList();

        allResources.addAll(resourcesWithServerId);
      } catch (e) {
        _logger.error('Error getting resources from server ${entry.key}: $e');
      }
    }

    return allResources;
  }

  /// Get tools organized by server
  Future<Map<String, List<Map<String, dynamic>>>> getToolsByServer() async {
    final result = <String, List<Map<String, dynamic>>>{};

    for (final entry in _adapters.entries) {
      try {
        final serverTools = await entry.value.getTools();
        result[entry.key] = serverTools;
      } catch (e) {
        _logger.error('Error getting tools from server ${entry.key}: $e');
        result[entry.key] = [];
      }
    }

    return result;
  }

  /// Get prompts organized by server
  Future<Map<String, List<Map<String, dynamic>>>> getPromptsByServer() async {
    final result = <String, List<Map<String, dynamic>>>{};

    for (final entry in _adapters.entries) {
      try {
        final serverPrompts = await entry.value.getPrompts();
        result[entry.key] = serverPrompts;
      } catch (e) {
        _logger.error('Error getting prompts from server ${entry.key}: $e');
        result[entry.key] = [];
      }
    }

    return result;
  }

  /// Get resources organized by server
  Future<Map<String, List<Map<String, dynamic>>>> getResourcesByServer() async {
    final result = <String, List<Map<String, dynamic>>>{};

    for (final entry in _adapters.entries) {
      try {
        final serverResources = await entry.value.getResources();
        result[entry.key] = serverResources;
      } catch (e) {
        _logger.error('Error getting resources from server ${entry.key}: $e');
        result[entry.key] = [];
      }
    }

    return result;
  }

  /// Execute a tool on a specific server or try all servers
  Future<dynamic> executeTool(
      String toolName,
      Map<String, dynamic> args, {
        String? serverId,
        bool tryAllServers = false,
      }) async {
    // Try a specific server if provided
    if (serverId != null) {
      final adapter = _adapters[serverId];
      if (adapter == null) {
        if (!tryAllServers) {
          throw Exception('Server not found: $serverId');
        }
      } else {
        try {
          final result = await adapter.executeTool(toolName, args);
          return result;
        } catch (e) {
          _logger.warning('Error executing tool $toolName on server $serverId: $e');
          if (!tryAllServers) {
            throw Exception('Tool execution failed on specified server: $e');
          }
        }
      }
    }

    // Try default server if no specific server or default server wasn't already tried
    if (serverId == null && _defaultServerId != null && _defaultServerId != serverId) {
      final adapter = _adapters[_defaultServerId!];
      if (adapter != null) {
        try {
          final result = await adapter.executeTool(toolName, args);
          return result;
        } catch (e) {
          _logger.warning('Error executing tool $toolName on default server: $e');
          if (!tryAllServers) {
            throw Exception('Tool execution failed on default server: $e');
          }
        }
      }
    }

    // If tryAllServers is true, try all other servers
    if (tryAllServers) {
      Exception? lastError;

      for (final entry in _adapters.entries) {
        // Skip already tried servers
        if (entry.key == serverId || entry.key == _defaultServerId) {
          continue;
        }

        try {
          final result = await entry.value.executeTool(toolName, args);
          _logger.debug('Successfully executed tool $toolName on server ${entry.key}');
          return result;
        } catch (e) {
          _logger.warning('Error executing tool $toolName on server ${entry.key}: $e');
          lastError = Exception('Failed on server ${entry.key}: $e');
        }
      }

      // If we got here, all servers failed
      if (lastError != null) {
        throw lastError;
      }
    }

    throw Exception('Tool $toolName not found or execution failed');
  }

  /// Get a prompt from a specific server or try all servers
  Future<dynamic> getPrompt(
      String promptName,
      Map<String, dynamic> args, {
        String? serverId,
        bool tryAllServers = false,
      }) async {
    // Try a specific server if provided
    if (serverId != null) {
      final adapter = _adapters[serverId];
      if (adapter == null) {
        if (!tryAllServers) {
          throw Exception('Server not found: $serverId');
        }
      } else {
        try {
          final result = await adapter.getPrompt(promptName, args);
          return result;
        } catch (e) {
          _logger.warning('Error getting prompt $promptName from server $serverId: $e');
          if (!tryAllServers) {
            throw Exception('Getting prompt failed on specified server: $e');
          }
        }
      }
    }

    // Try default server if no specific server or default server wasn't already tried
    if (serverId == null && _defaultServerId != null && _defaultServerId != serverId) {
      final adapter = _adapters[_defaultServerId!];
      if (adapter != null) {
        try {
          final result = await adapter.getPrompt(promptName, args);
          return result;
        } catch (e) {
          _logger.warning('Error getting prompt $promptName from default server: $e');
          if (!tryAllServers) {
            throw Exception('Getting prompt failed on default server: $e');
          }
        }
      }
    }

    // If tryAllServers is true, try all other servers
    if (tryAllServers) {
      Exception? lastError;

      for (final entry in _adapters.entries) {
        // Skip already tried servers
        if (entry.key == serverId || entry.key == _defaultServerId) {
          continue;
        }

        try {
          final result = await entry.value.getPrompt(promptName, args);
          _logger.debug('Successfully got prompt $promptName from server ${entry.key}');
          return result;
        } catch (e) {
          _logger.warning('Error getting prompt $promptName from server ${entry.key}: $e');
          lastError = Exception('Failed on server ${entry.key}: $e');
        }
      }

      // If we got here, all servers failed
      if (lastError != null) {
        throw lastError;
      }
    }

    throw Exception('Prompt $promptName not found or getting prompt failed');
  }

  /// Read a resource from a specific server or try all servers
  Future<dynamic> readResource(
      String resourceUri,
      [Map<String, dynamic>? params,
        String? serverId,
        bool tryAllServers = false]) async {
    // Try a specific server if provided
    if (serverId != null) {
      final adapter = _adapters[serverId];
      if (adapter == null) {
        if (!tryAllServers) {
          throw Exception('Server not found: $serverId');
        }
      } else {
        try {
          final result = await adapter.readResource(resourceUri, params);
          return result;
        } catch (e) {
          _logger.warning('Error reading resource $resourceUri from server $serverId: $e');
          if (!tryAllServers) {
            throw Exception('Reading resource failed on specified server: $e');
          }
        }
      }
    }

    // Try default server if no specific server or default server wasn't already tried
    if (serverId == null && _defaultServerId != null && _defaultServerId != serverId) {
      final adapter = _adapters[_defaultServerId!];
      if (adapter != null) {
        try {
          final result = await adapter.readResource(resourceUri, params);
          return result;
        } catch (e) {
          _logger.warning('Error reading resource $resourceUri from default server: $e');
          if (!tryAllServers) {
            throw Exception('Reading resource failed on default server: $e');
          }
        }
      }
    }

    // If tryAllServers is true, try all other servers
    if (tryAllServers) {
      Exception? lastError;

      for (final entry in _adapters.entries) {
        // Skip already tried servers
        if (entry.key == serverId || entry.key == _defaultServerId) {
          continue;
        }

        try {
          final result = await entry.value.readResource(resourceUri, params);
          _logger.debug('Successfully read resource $resourceUri from server ${entry.key}');
          return result;
        } catch (e) {
          _logger.warning('Error reading resource $resourceUri from server ${entry.key}: $e');
          lastError = Exception('Failed on server ${entry.key}: $e');
        }
      }

      // If we got here, all servers failed
      if (lastError != null) {
        throw lastError;
      }
    }

    throw Exception('Resource $resourceUri not found or reading resource failed');
  }

  /// Execute a tool on all servers and collect results
  Future<Map<String, dynamic>> executeToolOnAllServers(
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
      String serverId,
      LlmServerAdapter adapter,
      String toolName,
      Map<String, dynamic> args
      ) async {
    try {
      return await adapter.executeTool(toolName, args);
    } catch (e) {
      _logger.error('Error executing tool $toolName on server $serverId: $e');
      return {'error': e.toString()};
    }
  }

  /// Find all servers that have a specific tool
  Future<List<String>> findServersWithTool(String toolName) async {
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

  // Helper method to check if server has a tool
  Future<bool> _hasToolSafe(
      String serverId,
      LlmServerAdapter adapter,
      String toolName
      ) async {
    try {
      final tools = await adapter.getTools();
      return tools.any((tool) => tool['name'] == toolName);
    } catch (e) {
      _logger.warning('Error checking tool $toolName for server $serverId: $e');
      return false;
    }
  }

  /// Find all servers that have a specific prompt
  Future<List<String>> findServersWithPrompt(String promptName) async {
    final result = <String>[];
    final futures = <Future<void>>[];

    for (final entry in _adapters.entries) {
      futures.add(
          _hasPromptSafe(entry.key, entry.value, promptName).then((hasPrompt) {
            if (hasPrompt) {
              result.add(entry.key);
            }
          })
      );
    }

    await Future.wait(futures);
    return result;
  }

  // Helper method to check if server has a prompt
  Future<bool> _hasPromptSafe(
      String serverId,
      LlmServerAdapter adapter,
      String promptName
      ) async {
    try {
      final prompts = await adapter.getPrompts();
      return prompts.any((prompt) => prompt['name'] == promptName);
    } catch (e) {
      _logger.warning('Error checking prompt $promptName for server $serverId: $e');
      return false;
    }
  }

  /// Find all servers that have a specific resource
  Future<List<String>> findServersWithResource(String resourceUri) async {
    final result = <String>[];
    final futures = <Future<void>>[];

    for (final entry in _adapters.entries) {
      futures.add(
          _hasResourceSafe(entry.key, entry.value, resourceUri).then((hasResource) {
            if (hasResource) {
              result.add(entry.key);
            }
          })
      );
    }

    await Future.wait(futures);
    return result;
  }

  // Helper method to check if server has a resource
  Future<bool> _hasResourceSafe(
      String serverId,
      LlmServerAdapter adapter,
      String resourceUri
      ) async {
    try {
      final resources = await adapter.getResources();
      return resources.any((resource) =>
      resource['uri'] == resourceUri ||
          resource['name'] == resourceUri);
    } catch (e) {
      _logger.warning('Error checking resource $resourceUri for server $serverId: $e');
      return false;
    }
  }

  /// Get server status information for all servers
  Map<String, Map<String, dynamic>> getServerStatus() {
    final result = <String, Map<String, dynamic>>{};

    for (final entry in _adapters.entries) {
      try {
        result[entry.key] = entry.value.getServerStatus();
      } catch (e) {
        result[entry.key] = {'error': e.toString(), 'running': false};
      }
    }

    return result;
  }
}