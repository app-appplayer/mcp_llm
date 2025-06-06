import '../utils/logger.dart';
import 'llm_server_adapter.dart';
import 'mcp_auth_adapter.dart';
import '../lifecycle/lifecycle_manager.dart';
import '../capabilities/capability_manager.dart';
import '../health/health_monitor.dart';
import '../core/models.dart';

/// Manages multiple MCP servers
class McpServerManager {
  /// Map of MCP server IDs to their instances
  final Map<String, dynamic> _mcpServers = {};

  /// Map of MCP server IDs to their adapters
  final Map<String, LlmServerAdapter> _adapters = {};

  /// Map of MCP server IDs to their auth adapters
  final Map<String, McpAuthAdapter> _authAdapters = {};

  /// Default server ID to use when none specified
  String? _defaultServerId;

  /// Logger instance
  final Logger _logger = Logger('mcp_llm.mcp_server_manager');

  /// Lifecycle manager for 2025-03-26 MCP server lifecycle management
  late final ServerLifecycleManager _lifecycleManager;

  /// Capability manager for 2025-03-26 MCP capability management
  late final McpCapabilityManager _capabilityManager;

  /// Health monitor for 2025-03-26 MCP health checking
  late final McpHealthMonitor _healthMonitor;

  /// Create a new MCP server manager
  McpServerManager({
    dynamic defaultServer, 
    String? defaultServerId,
    HealthCheckConfig? healthConfig,
  }) {
    // Initialize lifecycle manager
    _lifecycleManager = ServerLifecycleManager();
    
    // Initialize capability manager
    _capabilityManager = McpCapabilityManager();
    
    // Initialize health monitor
    _healthMonitor = McpHealthMonitor(config: healthConfig ?? const HealthCheckConfig());
    
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

    // Register with lifecycle manager
    _lifecycleManager.registerServer(serverId, mcpServer);
    
    // Register with capability manager
    _capabilityManager.registerClient(serverId, mcpServer);
    
    // Register with health monitor
    _healthMonitor.registerClient(serverId, mcpServer);

    // Set as default if this is the first server
    _defaultServerId ??= serverId;

    _logger.info('Added MCP server: $serverId with 2025-03-26 features');
  }

  /// Remove a server
  void removeServer(String serverId) {
    _mcpServers.remove(serverId);
    _adapters.remove(serverId);
    
    // Remove OAuth authentication if exists
    final authAdapter = _authAdapters.remove(serverId);
    if (authAdapter != null) {
      authAdapter.removeAuth(serverId);
    }

    // Unregister from lifecycle manager
    _lifecycleManager.unregisterServer(serverId);
    
    // Unregister from capability manager
    _capabilityManager.unregisterClient(serverId);
    
    // Unregister from health monitor
    _healthMonitor.unregisterClient(serverId);

    // Clear default if it was this server
    if (_defaultServerId == serverId) {
      _defaultServerId = _mcpServers.isNotEmpty ? _mcpServers.keys.first : null;
    }

    _logger.info('Removed MCP server: $serverId from all 2025-03-26 managers');
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

  // ===== 2025-03-26 MCP Server Features =====

  /// Add a server with OAuth 2.1 authentication
  Future<void> addServerWithAuth(String serverId, dynamic mcpServer, {
    AuthConfig? authConfig,
    TokenValidator? tokenValidator,
  }) async {
    if (_mcpServers.containsKey(serverId)) {
      _logger.warning('Replacing existing MCP server with ID: $serverId');
    }

    // Create OAuth auth adapter
    final authAdapter = McpAuthAdapter(
      tokenValidator: tokenValidator,
      defaultConfig: authConfig ?? const AuthConfig(),
    );
    
    _mcpServers[serverId] = mcpServer;
    _authAdapters[serverId] = authAdapter;
    _adapters[serverId] = LlmServerAdapter(mcpServer);

    // Register with managers
    _lifecycleManager.registerServer(serverId, mcpServer);
    _capabilityManager.registerClient(serverId, mcpServer, authAdapter: authAdapter);
    _healthMonitor.registerClient(serverId, mcpServer);

    // Set as default if this is the first server
    _defaultServerId ??= serverId;

    _logger.info('Added MCP server with OAuth 2.1 authentication: $serverId');

    // Attempt automatic authentication
    try {
      final authResult = await authAdapter.authenticate(serverId, mcpServer, config: authConfig);
      if (authResult.isAuthenticated) {
        _logger.info('OAuth 2.1 authentication successful for server: $serverId');
      } else {
        _logger.warning('OAuth 2.1 authentication failed for server $serverId: ${authResult.error}');
      }
    } catch (e) {
      _logger.error('OAuth 2.1 authentication error for server $serverId: $e');
    }
  }

  /// Start a server with lifecycle management
  Future<void> startServer(String serverId, {
    LifecycleTransitionReason? reason,
  }) async {
    await _lifecycleManager.startServer(
      serverId,
      reason: reason ?? LifecycleTransitionReason.userRequest,
    );
  }

  /// Stop a server with lifecycle management
  Future<void> stopServer(String serverId, {
    LifecycleTransitionReason? reason,
  }) async {
    await _lifecycleManager.stopServer(
      serverId,
      reason: reason ?? LifecycleTransitionReason.userRequest,
    );
  }

  /// Pause a server
  Future<void> pauseServer(String serverId, {
    LifecycleTransitionReason? reason,
  }) async {
    await _lifecycleManager.pauseServer(
      serverId,
      reason: reason ?? LifecycleTransitionReason.userRequest,
    );
  }

  /// Resume a paused server
  Future<void> resumeServer(String serverId, {
    LifecycleTransitionReason? reason,
  }) async {
    await _lifecycleManager.resumeServer(
      serverId,
      reason: reason ?? LifecycleTransitionReason.userRequest,
    );
  }

  /// Get server lifecycle state
  ServerLifecycleState? getServerState(String serverId) {
    return _lifecycleManager.getServerState(serverId);
  }

  /// Get all server states
  Map<String, ServerLifecycleState> getAllServerStates() {
    final states = <String, ServerLifecycleState>{};
    for (final serverId in _mcpServers.keys) {
      final state = _lifecycleManager.getServerState(serverId);
      if (state != null) {
        states[serverId] = state;
      }
    }
    return states;
  }

  /// Perform health check on servers
  Future<HealthReport> performHealthCheck({
    List<String>? serverIds,
    bool includeSystemMetrics = true,
  }) {
    return _healthMonitor.performHealthCheck(
      clientIds: serverIds,
      includeSystemMetrics: includeSystemMetrics,
    );
  }

  /// Get health status for a specific server
  HealthCheckResult? getServerHealth(String serverId) {
    return _healthMonitor.getClientHealth(serverId);
  }

  /// Check if all servers are healthy
  bool get allServersHealthy => _healthMonitor.allClientsHealthy;

  /// Get list of unhealthy servers
  List<String> get unhealthyServers => _healthMonitor.unhealthyClients;

  /// Get health statistics
  Map<String, dynamic> getHealthStatistics() {
    return _healthMonitor.getHealthStatistics();
  }

  /// Get capabilities for a specific server
  Map<String, McpCapability> getServerCapabilities(String serverId) {
    return _capabilityManager.getClientCapabilities(serverId);
  }

  /// Get all capabilities across all servers
  Map<String, Map<String, McpCapability>> getAllCapabilities() {
    return _capabilityManager.getAllCapabilities();
  }

  /// Update capabilities for a server
  Future<CapabilityUpdateResponse> updateCapabilities(CapabilityUpdateRequest request) {
    return _capabilityManager.updateCapabilities(request);
  }

  /// Get capability statistics
  Map<String, dynamic> getCapabilityStatistics() {
    return _capabilityManager.getCapabilityStatistics();
  }

  /// Get lifecycle statistics
  Map<String, dynamic> getLifecycleStatistics() {
    final states = getAllServerStates();
    final statistics = <String, dynamic>{
      'total_servers': _mcpServers.length,
      'stopped': states.values.where((s) => s == ServerLifecycleState.stopped).length,
      'starting': states.values.where((s) => s == ServerLifecycleState.starting).length,
      'running': states.values.where((s) => s == ServerLifecycleState.running).length,
      'pausing': states.values.where((s) => s == ServerLifecycleState.pausing).length,
      'paused': states.values.where((s) => s == ServerLifecycleState.paused).length,
      'stopping': states.values.where((s) => s == ServerLifecycleState.stopping).length,
      'error': states.values.where((s) => s == ServerLifecycleState.error).length,
    };
    return statistics;
  }

  /// Subscribe to lifecycle events
  Stream<LifecycleEvent> get lifecycleEvents => _lifecycleManager.events;

  /// Subscribe to capability events
  Stream<CapabilityEvent> get capabilityEvents => _capabilityManager.events;

  /// Get authenticated servers
  List<String> get authenticatedServers {
    return _authAdapters.keys.toList();
  }

  /// Get unauthenticated servers
  List<String> get unauthenticatedServers {
    return _mcpServers.keys
        .where((serverId) => !_authAdapters.containsKey(serverId))
        .toList();
  }

  /// Get authentication summary
  Map<String, dynamic> getAuthSummary() {
    final authenticated = authenticatedServers;
    final unauthenticated = unauthenticatedServers;
    final total = _mcpServers.length;
    
    return {
      'total_servers': total,
      'authenticated_servers': authenticated.length,
      'unauthenticated_servers': unauthenticated.length,
      'authentication_coverage': total > 0 ? (authenticated.length / total * 100).round() : 0,
      'protocol_version': '2025-03-26',
      'oauth_version': '2.1',
    };
  }

  /// Dispose of all resources
  void dispose() {
    // Dispose auth adapters
    for (final authAdapter in _authAdapters.values) {
      authAdapter.dispose();
    }
    _authAdapters.clear();
    
    // Dispose lifecycle manager
    _lifecycleManager.dispose();
    
    // Dispose capability manager
    _capabilityManager.dispose();
    
    // Dispose health monitor
    _healthMonitor.dispose();
    
    _logger.info('Disposed all MCP server manager resources and 2025-03-26 managers');
  }
}