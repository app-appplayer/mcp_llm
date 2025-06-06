import '../../mcp_llm.dart';
import '../adapter/llm_server_adapter.dart';

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
    String? serverId,
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
          serverId: serverId,
        );
      }

      return true;
    } catch (e) {
      // Log error
      throw Exception('Failed to register core LLM plugins: $e');
    }
  }

  /// Get list of all tools registered with servers
  Future<List<Map<String, dynamic>>> getServerTools() async {
    if (!hasMcpServer) {
      return [];
    }

    try {
      return await getAllServerTools();
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
        allTools.addAll(await getAllServerTools());
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

  /// Get list of all prompts registered with servers
  Future<List<Map<String, dynamic>>> getServerPrompts() async {
    if (!hasMcpServer) {
      return [];
    }

    try {
      return await getAllServerPrompts();
    } catch (e) {
      throw Exception('Failed to get server prompts: $e');
    }
  }

  /// Get list of plugin prompts
  List<LlmPrompt> getPluginPrompts() {
    return pluginManager.getAllPromptPlugins()
        .map((plugin) => plugin.getPromptDefinition())
        .toList();
  }

  /// Get list of all available prompts (server, plugin)
  Future<List<Map<String, dynamic>>> getAllAvailablePrompts() async {
    final allPrompts = <Map<String, dynamic>>[];

    // Add server prompts
    if (hasMcpServer) {
      try {
        allPrompts.addAll(await getAllServerPrompts());
      } catch (e) {
        // Ignore errors and continue
      }
    }

    // Add plugin prompts (not already added)
    for (final plugin in pluginManager.getAllPromptPlugins()) {
      final promptDef = plugin.getPromptDefinition();
      if (!allPrompts.any((prompt) => prompt['name'] == promptDef.name)) {
        final arguments = promptDef.arguments.map((arg) => {
          'name': arg.name,
          'description': arg.description,
          'required': arg.required,
          if (arg.defaultValue != null) 'default': arg.defaultValue,
        }).toList();

        allPrompts.add({
          'name': promptDef.name,
          'description': promptDef.description,
          'arguments': arguments,
          'source': 'plugin',
        });
      }
    }

    return allPrompts;
  }

  /// Get list of all resources registered with servers
  Future<List<Map<String, dynamic>>> getServerResources() async {
    if (!hasMcpServer) {
      return [];
    }

    try {
      return await getAllServerResources();
    } catch (e) {
      throw Exception('Failed to get server resources: $e');
    }
  }

  /// Get list of plugin resources
  List<LlmResource> getPluginResources() {
    return pluginManager.getAllResourcePlugins()
        .map((plugin) => plugin.getResourceDefinition())
        .toList();
  }

  /// Get list of all available resources (server, plugin)
  Future<List<Map<String, dynamic>>> getAllAvailableResources() async {
    final allResources = <Map<String, dynamic>>[];

    // Add server resources
    if (hasMcpServer) {
      try {
        allResources.addAll(await getAllServerResources());
      } catch (e) {
        // Ignore errors and continue
      }
    }

    // Add plugin resources (not already added)
    for (final plugin in pluginManager.getAllResourcePlugins()) {
      final resourceDef = plugin.getResourceDefinition();
      if (!allResources.any((resource) => resource['uri'] == resourceDef.uri)) {
        allResources.add({
          'name': resourceDef.name,
          'description': resourceDef.description,
          'uri': resourceDef.uri,
          'mimeType': resourceDef.mimeType ?? 'application/octet-stream',
          'source': 'plugin',
        });
      }
    }

    return allResources;
  }
}

/// Additional helper methods
/// General extensions for LlmServer
extension LlmServerHelperExtensions on LlmServer {
  /// Get current server status information
  Future<Map<String, dynamic>> getServerInfo() async {
    final info = <String, dynamic>{
      'hasServer': hasMcpServer,
      'hasRetrieval': hasRetrievalCapabilities,
      'localToolCount': localTools.length,
      'pluginToolCount': pluginManager.getAllToolPlugins().length,
      'pluginResourceCount': pluginManager.getAllResourcePlugins().length,
    };

    if (hasMcpServer) {
      try {
        info['serverIds'] = getMcpServerIds();
        info['serverStatuses'] = serverManager?.getServerStatus();
      } catch (e) {
        info['serverStatusError'] = e.toString();
      }
    }

    return info;
  }

  /// Session management helper
  Future<bool> clearSession(String sessionId) async {
    chatSession.clearHistory();
    return true;
  }

  /// Check if a specific tool is available
  Future<bool> isToolAvailable(String toolName, {String? serverId}) async {
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
        final tools = await serverManager!.getTools(serverId);
        return tools.any((tool) => tool['name'] == toolName);
      } catch (e) {
        // If error, assume not available
        return false;
      }
    }

    return false;
  }

  /// Check if a specific prompt is available
  Future<bool> isPromptAvailable(String promptName, {String? serverId}) async {
    // Check plugin prompts
    if (pluginManager.getPromptPlugin(promptName) != null) {
      return true;
    }

    // Check server prompts
    if (hasMcpServer) {
      try {
        final prompts = await serverManager!.getPrompts(serverId);
        return prompts.any((prompt) => prompt['name'] == promptName);
      } catch (e) {
        // If error, assume not available
        return false;
      }
    }

    return false;
  }

  /// Get a prompt (from plugin or server)
  Future<dynamic> getPrompt(String promptName, Map<String, dynamic> arguments, {String? serverId}) async {
    // Check plugin prompts
    final promptPlugin = pluginManager.getPromptPlugin(promptName);
    if (promptPlugin != null) {
      return await promptPlugin.execute(arguments);
    }

    // Check server prompts
    if (hasMcpServer) {
      try {
        return await serverManager!.getPrompt(
            promptName,
            arguments,
            serverId: serverId,
            tryAllServers: serverId == null
        );
      } catch (e) {
        throw Exception('Failed to get prompt $promptName: $e');
      }
    }

    throw Exception('Prompt not found: $promptName');
  }

  /// Check if a specific resource is available
  Future<bool> isResourceAvailable(String resourceUri, {String? serverId}) async {
    // Check plugin resources (by name or URI)
    final pluginResources = pluginManager.getAllResourcePlugins();
    if (pluginResources.any((p) => p.getResourceDefinition().uri == resourceUri ||
        p.getResourceDefinition().name == resourceUri)) {
      return true;
    }

    // Check server resources
    if (hasMcpServer) {
      try {
        final resources = await serverManager!.getResources(serverId);
        return resources.any((r) => r['uri'] == resourceUri || r['name'] == resourceUri);
      } catch (e) {
        // If error, assume not available
        return false;
      }
    }

    return false;
  }

  /// Read a resource (from plugin or server)
  Future<dynamic> readResource(
      String resourceUri,
      [Map<String, dynamic>? parameters,
        String? serverId]) async {
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
        return await serverManager!.readResource(
            resourceUri,
            params,
            serverId,
            serverId == null // tryAllServers if no specific server ID provided
        );
      } catch (e) {
        throw Exception('Failed to read resource $resourceUri: $e');
      }
    }

    throw Exception('Resource not found: $resourceUri');
  }

  /// Find servers that have specific capabilities
  Future<Map<String, List<String>>> findServersWithCapabilities({
    List<String>? toolNames,
    List<String>? promptNames,
    List<String>? resourceUris,
  }) async {
    final results = <String, List<String>>{
      'tools': <String>[],
      'prompts': <String>[],
      'resources': <String>[],
    };

    if (!hasMcpServer) {
      return results;
    }

    // Find servers with specific tools
    if (toolNames != null && toolNames.isNotEmpty) {
      for (final toolName in toolNames) {
        final servers = await serverManager!.findServersWithTool(toolName);
        results['tools']!.addAll(servers);
      }
    }

    // Find servers with specific prompts
    if (promptNames != null && promptNames.isNotEmpty) {
      for (final promptName in promptNames) {
        final servers = await serverManager!.findServersWithPrompt(promptName);
        results['prompts']!.addAll(servers);
      }
    }

    // Find servers with specific resources
    if (resourceUris != null && resourceUris.isNotEmpty) {
      for (final resourceUri in resourceUris) {
        final servers = await serverManager!.findServersWithResource(resourceUri);
        results['resources']!.addAll(servers);
      }
    }

    // Remove duplicates
    results['tools'] = results['tools']!.toSet().toList();
    results['prompts'] = results['prompts']!.toSet().toList();
    results['resources'] = results['resources']!.toSet().toList();

    return results;
  }

  /// Get common capabilities across multiple servers
  /// Returns capabilities that are available on all specified servers
  Future<Map<String, List<Map<String, dynamic>>>> getCommonCapabilities(List<String> serverIds) async {
    if (!hasMcpServer || serverIds.isEmpty) {
      return {
        'tools': [],
        'prompts': [],
        'resources': [],
      };
    }

    final common = <String, List<Map<String, dynamic>>>{
      'tools': [],
      'prompts': [],
      'resources': [],
    };

    // Get capabilities from first server as baseline
    final firstServerId = serverIds.first;
    Map<String, List<Map<String, dynamic>>> firstServerCapabilities = {
      'tools': await serverManager!.getTools(firstServerId),
      'prompts': await serverManager!.getPrompts(firstServerId),
      'resources': await serverManager!.getResources(firstServerId),
    };

    // For single server case, just return its capabilities
    if (serverIds.length == 1) {
      return firstServerCapabilities;
    }

    // Start with first server's capabilities
    common['tools'] = List.from(firstServerCapabilities['tools']!);
    common['prompts'] = List.from(firstServerCapabilities['prompts']!);
    common['resources'] = List.from(firstServerCapabilities['resources']!);

    // Check against all other servers
    for (int i = 1; i < serverIds.length; i++) {
      final serverId = serverIds[i];

      // Get capabilities for this server
      final tools = await serverManager!.getTools(serverId);
      final prompts = await serverManager!.getPrompts(serverId);
      final resources = await serverManager!.getResources(serverId);

      // Filter tools to only include those in both lists
      common['tools'] = common['tools']!.where((tool) =>
          tools.any((t) => t['name'] == tool['name'])).toList();

      // Filter prompts to only include those in both lists
      common['prompts'] = common['prompts']!.where((prompt) =>
          prompts.any((p) => p['name'] == prompt['name'])).toList();

      // Filter resources to only include those in both lists (by URI)
      common['resources'] = common['resources']!.where((resource) =>
          resources.any((r) => r['uri'] == resource['uri'])).toList();
    }

    return common;
  }

  /// Helper to check if results are consistent across servers
  bool _areResultsConsistent(List<dynamic> results) {
    if (results.length <= 1) {
      return true;
    }

    // Convert to strings for comparison
    final stringResults = results.map((r) => r.toString()).toList();
    final firstResult = stringResults.first;

    // Check if all results match the first one
    return stringResults.every((result) => result == firstResult);
  }
}

/// Extensions for advanced server operations
extension LlmServerAdvancedExtensions on LlmServer {
  /// Execute a tool across multiple servers and compare results
  Future<Map<String, dynamic>> compareToolResults(
      String toolName,
      Map<String, dynamic> args,
      List<String> serverIds) async {
    if (!hasMcpServer) {
      throw StateError('MCP server manager is not initialized');
    }

    if (serverIds.isEmpty) {
      throw ArgumentError('Must provide at least one server ID');
    }

    final results = <String, dynamic>{};
    final errors = <String, String>{};

    // Execute the tool on each server
    for (final serverId in serverIds) {
      try {
        final result = await serverManager!.executeTool(
            toolName,
            args,
            serverId: serverId,
            tryAllServers: false
        );
        results[serverId] = result;
      } catch (e) {
        errors[serverId] = e.toString();
      }
    }

    // Return combined results
    return {
      'results': results,
      'errors': errors,
      'consistent': _areResultsConsistent(results.values.toList()),
    };
  }

  /// Register the same tool on multiple servers
  Future<Map<String, bool>> registerToolOnMultipleServers({
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema,
    required ToolHandler handler,
    required List<String> serverIds,
  }) async {
    if (!hasMcpServer) {
      throw StateError('MCP server manager is not initialized');
    }

    final results = <String, bool>{};

    for (final serverId in serverIds) {
      try {
        final success = await serverManager!.registerTool(
          name: name,
          description: description,
          inputSchema: inputSchema,
          handler: handler,
          serverId: serverId,
        );
        results[serverId] = success;
      } catch (e) {
        results[serverId] = false;
      }
    }

    return results;
  }

  /// Deploy multiple capabilities to a set of servers
  /// Registers tools, prompts, and resources on multiple servers
  Future<Map<String, Map<String, int>>> deployCapabilities({
    List<Map<String, dynamic>> tools = const [],
    List<Map<String, dynamic>> prompts = const [],
    List<Map<String, dynamic>> resources = const [],
    required List<String> serverIds,
  }) async {
    if (!hasMcpServer) {
      throw StateError('MCP server manager is not initialized');
    }

    final results = <String, Map<String, int>>{};

    // Initialize results structure
    for (final serverId in serverIds) {
      results[serverId] = {
        'tools': 0,
        'tools_total': tools.length,
        'prompts': 0,
        'prompts_total': prompts.length,
        'resources': 0,
        'resources_total': resources.length,
      };
    }

    // Deploy tools
    for (final tool in tools) {
      final handler = tool['handler'] as ToolHandler?;
      if (handler == null) continue;

      for (final serverId in serverIds) {
        final success = await serverManager!.registerTool(
          name: tool['name'],
          description: tool['description'],
          inputSchema: tool['inputSchema'],
          handler: handler,
          serverId: serverId,
        );

        if (success) {
          results[serverId]!['tools'] = (results[serverId]!['tools'] as int) + 1;
        }
      }
    }

    // Deploy prompts
    for (final prompt in prompts) {
      final handler = prompt['handler'] as PromptHandler?;
      if (handler == null) continue;

      for (final serverId in serverIds) {
        final success = await serverManager!.registerPrompt(
          name: prompt['name'],
          description: prompt['description'],
          arguments: prompt['arguments'],
          handler: handler,
          serverId: serverId,
        );

        if (success) {
          results[serverId]!['prompts'] = (results[serverId]!['prompts'] as int) + 1;
        }
      }
    }

    // Deploy resources
    for (final resource in resources) {
      final handler = resource['handler'] as ResourceHandler?;
      if (handler == null) continue;

      for (final serverId in serverIds) {
        final success = await serverManager!.registerResource(
          uri: resource['uri'],
          name: resource['name'],
          description: resource['description'],
          mimeType: resource['mimeType'] ?? 'application/octet-stream',
          handler: handler,
          serverId: serverId,
        );

        if (success) {
          results[serverId]!['resources'] = (results[serverId]!['resources'] as int) + 1;
        }
      }
    }

    return results;
  }

  /// Synchronize capabilities between servers
  /// Copies tools, prompts, and resources from source to target servers
  Future<Map<String, int>> synchronizeServers({
    required String sourceServerId,
    required List<String> targetServerIds,
    bool syncTools = true,
    bool syncPrompts = true,
    bool syncResources = true,
  }) async {
    if (!hasMcpServer) {
      throw StateError('MCP server manager is not initialized');
    }

    final results = <String, int>{
      'tools': 0,
      'prompts': 0,
      'resources': 0,
    };

    // Synchronize tools
    if (syncTools) {
      final sourceTools = await serverManager!.getTools(sourceServerId);

      for (final tool in sourceTools) {
        // Create a handler that forwards the request to the source server
        Future<LlmCallToolResult> forwardHandler(Map<String, dynamic> args) async {
          return await serverManager!.executeTool(
              tool['name'],
              args,
              serverId: sourceServerId
          );
        }

        int successCount = 0;
        for (final targetId in targetServerIds) {
          if (targetId == sourceServerId) continue; // Skip self

          final success = await serverManager!.registerTool(
            name: tool['name'],
            description: tool['description'],
            inputSchema: tool['inputSchema'] ?? {},
            handler: forwardHandler,
            serverId: targetId,
          );

          if (success) successCount++;
        }

        if (successCount > 0) {
          results['tools'] = (results['tools'] ?? 0) + 1;
        }
      }
    }

    // Synchronize prompts
    if (syncPrompts) {
      final sourcePrompts = await serverManager!.getPrompts(sourceServerId);

      for (final prompt in sourcePrompts) {
        // Create a handler that forwards the request to the source server
        Future<LlmGetPromptResult> forwardHandler(Map<String, dynamic> args) async {
          return await serverManager!.getPrompt(
              prompt['name'],
              args,
              serverId: sourceServerId
          );
        }

        int successCount = 0;
        for (final targetId in targetServerIds) {
          if (targetId == sourceServerId) continue; // Skip self

          final success = await serverManager!.registerPrompt(
            name: prompt['name'],
            description: prompt['description'],
            arguments: prompt['arguments'] ?? [],
            handler: forwardHandler,
            serverId: targetId,
          );

          if (success) successCount++;
        }

        if (successCount > 0) {
          results['prompts'] = (results['prompts'] ?? 0) + 1;
        }
      }
    }

    // Synchronize resources
    if (syncResources) {
      final sourceResources = await serverManager!.getResources(sourceServerId);

      for (final resource in sourceResources) {
        // Create a handler that forwards the request to the source server
        Future<LlmReadResourceResult> forwardHandler(String uri, Map<String, dynamic> params) async {
          return await serverManager!.readResource(
              resource['uri'],
              params,
              sourceServerId
          );
        }

        int successCount = 0;
        for (final targetId in targetServerIds) {
          if (targetId == sourceServerId) continue; // Skip self

          final success = await serverManager!.registerResource(
            uri: resource['uri'],
            name: resource['name'],
            description: resource['description'],
            mimeType: resource['mimeType'] ?? 'application/octet-stream',
            handler: forwardHandler,
            serverId: targetId,
          );

          if (success) successCount++;
        }

        if (successCount > 0) {
          results['resources'] = (results['resources'] ?? 0) + 1;
        }
      }
    }

    return results;
  }
}