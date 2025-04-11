import '../../mcp_llm.dart';

/// Extension methods for LlmServer
/// Provides convenience methods for registering core LLM functionality as plugins
extension LlmServerPluginExtensions on LlmServer {
  /// Replacement for the existing registerLlmTools method
  ///
  /// Registers core LLM functionality as plugins and optionally with the server
  Future<bool> registerCoreLlmPlugins({
    bool registerCompletionTool = true,
    bool registerStreamingTool = true,
    bool registerEmbeddingTool = false,
    bool registerRetrievalTools = false,
    bool registerWithServer = true,
  }) async {
    try {
      // Register LLM core plugins with the plugin manager
      await CoreLlmPluginFactory.registerWithManager(
        pluginManager: pluginManager,
        llmProvider: llmProvider,
        retrievalManager: retrievalManager,
        includeCompletionPlugin: registerCompletionTool,
        includeStreamingPlugin: registerStreamingTool,
        includeEmbeddingPlugin: registerEmbeddingTool,
        includeRetrievalPlugins: registerRetrievalTools && hasRetrievalCapabilities,
      );

      // Whether to also register with the server
      if (registerWithServer && hasMcpServer) {
        return await registerPluginsWithServer(
          includeToolPlugins: true,
          includePromptPlugins: false,
          includeResourcePlugins: false,
        );
      }

      return true;
    } catch (e) {
      // Log error
      throw Exception('Failed to register core LLM plugins: $e');
    }
  }

  /// Get list of all tools registered with the server
  Future<List<Map<String, dynamic>>> getServerTools() async {
    if (!hasMcpServer) {
      return [];
    }

    try {
      return await serverAdapter!.listTools();
    } catch (e) {
      throw Exception('Failed to get server tools: $e');
    }
  }

  /// Get list of local tools
  List<String> getLocalTools() {
    return localTools.keys.toList();
  }

  /// Get list of plugin tools
  List<LlmTool> getPluginTools() {
    return pluginManager.getAllToolPlugins()
        .map((plugin) => plugin.getToolDefinition())
        .toList();
  }

  /// Get list of all available tools (server, local, plugin)
  Future<List<Map<String, dynamic>>> getAllAvailableTools() async {
    final allTools = <Map<String, dynamic>>[];

    // Add server tools
    if (hasMcpServer) {
      try {
        allTools.addAll(await serverAdapter!.listTools());
      } catch (e) {
        // Ignore errors and continue
      }
    }

    // Add local tools (not already registered with server)
    for (final name in localTools.keys) {
      if (!allTools.any((tool) => tool['name'] == name)) {
        allTools.add({
          'name': name,
          'description': 'Local tool',
          'source': 'local',
        });
      }
    }

    // Add plugin tools (not already added)
    for (final plugin in pluginManager.getAllToolPlugins()) {
      final toolDef = plugin.getToolDefinition();
      if (!allTools.any((tool) => tool['name'] == toolDef.name)) {
        allTools.add({
          'name': toolDef.name,
          'description': toolDef.description,
          'inputSchema': toolDef.inputSchema,
          'source': 'plugin',
        });
      }
    }

    return allTools;
  }
}

/// Additional helper methods
/// General extensions for LlmServer
extension LlmServerHelperExtensions on LlmServer {
  /// Get current server status information
  Map<String, dynamic> getServerInfo() {
    final info = <String, dynamic>{
      'hasServer': hasMcpServer,
      'hasRetrieval': hasRetrievalCapabilities,
      'sessionCount': chatSessions.length,
      'localToolCount': localTools.length,
      'pluginToolCount': pluginManager.getAllToolPlugins().length,
      'pluginResourceCount': pluginManager.getAllResourcePlugins().length,
    };

    if (hasMcpServer) {
      try {
        info['serverStatus'] = serverAdapter!.getServerStatus();
      } catch (e) {
        info['serverStatusError'] = e.toString();
      }
    }

    return info;
  }

  /// Session management helper
  Future<bool> clearSession(String sessionId) async {
    final session = chatSessions[sessionId];
    if (session == null) {
      return false;
    }

    session.clearHistory();
    return true;
  }

  /// Check if a specific tool is available
  Future<bool> isToolAvailable(String toolName) async {
    // Check local tools
    if (localTools.containsKey(toolName)) {
      return true;
    }

    // Check plugin tools
    if (pluginManager.getToolPlugin(toolName) != null) {
      return true;
    }

    // Check server tools
    if (hasMcpServer) {
      try {
        final tools = await serverAdapter!.listTools();
        return tools.any((tool) => tool['name'] == toolName);
      } catch (e) {
        // If error, assume not available
        return false;
      }
    }

    return false;
  }

  /// Check if a specific resource is available
  Future<bool> isResourceAvailable(String resourceUri) async {
    // Check plugin resources (by name or URI)
    final pluginResources = pluginManager.getAllResourcePlugins();
    if (pluginResources.any((p) => p.getResourceDefinition().uri == resourceUri ||
        p.getResourceDefinition().name == resourceUri)) {
      return true;
    }

    // Check server resources
    if (hasMcpServer) {
      try {
        final resources = await serverAdapter!.listResources();
        return resources.any((r) => r['uri'] == resourceUri || r['name'] == resourceUri);
      } catch (e) {
        // If error, assume not available
        return false;
      }
    }

    return false;
  }

  /// Read a resource (from plugin or server)
  Future<LlmReadResourceResult> readResource(String resourceUri, [Map<String, dynamic>? parameters]) async {
    final params = parameters ?? {};

    // Check plugin resources (by URI)
    final pluginResources = pluginManager.getAllResourcePlugins();
    for (final plugin in pluginResources) {
      final resourceDef = plugin.getResourceDefinition();
      if (resourceDef.uri == resourceUri || resourceDef.name == resourceUri) {
        return await plugin.read(params);
      }
    }

    // Check server resources
    if (hasMcpServer) {
      try {
        return await serverAdapter!.readResource(resourceUri, params);
      } catch (e) {
        throw Exception('Failed to read resource $resourceUri: $e');
      }
    }

    throw Exception('Resource not found: $resourceUri');
  }
}
