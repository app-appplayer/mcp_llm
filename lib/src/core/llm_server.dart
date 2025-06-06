import '../../mcp_llm.dart';
import '../adapter/llm_server_adapter.dart';
import 'dart:convert';
import 'dart:io';

import '../plugins/resource_plugin.dart';

/// Server for providing LLM capabilities
/// Enhanced with plugin-based tool management
class LlmServer {
  /// LLM provider
  final LlmInterface llmProvider;

  /// MCP server manager
  late final McpServerManager? serverManager;

  /// Storage manager
  final StorageManager? storageManager;

  /// Retrieval manager
  final RetrievalManager? retrievalManager;

  /// Plugin manager
  final PluginManager pluginManager;

  /// Performance monitor
  final PerformanceMonitor _performanceMonitor;

  /// Logger instance
  final Logger _logger = Logger('mcp_llm.llm_server');

  /// Registered local tools (name -> handler function)
  final Map<String, Function> localTools = {};

  /// Chat sessions for different contexts
  late final ChatSession chatSession;

  /// Create a new LLM server
  LlmServer({
    required this.llmProvider,
    dynamic mcpServer,  // Single server (backward compatibility)
    Map<String, dynamic>? mcpServers, // Multiple servers (new feature)
    this.storageManager,
    this.retrievalManager,
    required this.pluginManager,
    PerformanceMonitor? performanceMonitor,
  }) : serverManager = _initServerManager(mcpServer, mcpServers),
        _performanceMonitor = performanceMonitor ?? PerformanceMonitor() {
    // Initialize default chat session
    chatSession = ChatSession(
      llmProvider: llmProvider,
      storageManager: storageManager,
    );
  }

  /// Initialize the MCP server manager
  static McpServerManager? _initServerManager(
      dynamic mcpServer, Map<String, dynamic>? mcpServers) {
    if (mcpServer != null) {
      // Create manager with single server
      return McpServerManager(defaultServer: mcpServer);
    } else if (mcpServers != null && mcpServers.isNotEmpty) {
      // Create manager with multiple servers
      final manager = McpServerManager();
      mcpServers.forEach((id, server) {
        manager.addServer(id, server);
      });
      return manager;
    }

    // No MCP servers
    return null;
  }

  /// Get server adapter for the default server (for backward compatibility)
  LlmServerAdapter? get serverAdapter => serverManager?.defaultAdapter;

  /// Check if MCP server manager is available
  bool get hasMcpServer => serverManager != null && serverManager!.serverCount > 0;

  /// Check if retrieval capabilities are available
  bool get hasRetrievalCapabilities => retrievalManager != null;

  /// Add an MCP server
  void addMcpServer(String serverId, dynamic mcpServer) {
    serverManager ??= McpServerManager();
    serverManager!.addServer(serverId, mcpServer);
  }

  /// Remove an MCP server
  void removeMcpServer(String serverId) {
    if (serverManager != null) {
      serverManager!.removeServer(serverId);
    }
  }

  /// Set default MCP server
  void setDefaultMcpServer(String serverId) {
    if (serverManager == null) {
      throw StateError('MCP server manager is not initialized');
    }
    serverManager!.setDefaultServer(serverId);
  }

  /// Get all MCP server IDs
  List<String> getMcpServerIds() {
    return serverManager?.serverIds ?? [];
  }

  /// Register all plugins as server tools
  Future<bool> registerPluginsWithServer({
    bool includeToolPlugins = true,
    bool includePromptPlugins = true,
    bool includeResourcePlugins = true,
    String? serverId,
  }) async {
    if (!hasMcpServer) {
      _logger.warning('Cannot register plugins: MCP server is not available');
      return false;
    }

    bool success = true;

    if (includeToolPlugins) {
      success = success && await registerToolPluginsWithServer(serverId: serverId);
    }

    if (includePromptPlugins) {
      success = success && await registerPromptPluginsWithServer(serverId: serverId);
    }

    if (includeResourcePlugins) {
      success = success && await registerResourcePluginsWithServer(serverId: serverId);
    }

    return success;
  }

  /// Register tool plugins with the server
  Future<bool> registerToolPluginsWithServer({String? serverId}) async {
    if (!hasMcpServer) {
      _logger.warning('Cannot register tool plugins: MCP server is not available');
      return false;
    }

    bool success = true;
    final toolPlugins = pluginManager.getAllToolPlugins();

    for (final plugin in toolPlugins) {
      try {
        final toolDef = plugin.getToolDefinition();

        // Create adapter function that converts between plugin and server formats
        serverHandler(Map<String, dynamic> args) async {
          final pluginResult = await plugin.execute(args);
          // Plugin result is already in the correct format with dynamic typing
          return pluginResult;
        }

        final result = await serverManager!.registerTool(
          name: toolDef.name,
          description: toolDef.description,
          inputSchema: toolDef.inputSchema,
          handler: serverHandler,
          serverId: serverId,
        );

        if (result) {
          _logger.info('Registered tool plugin with server: ${toolDef.name}');
        } else {
          _logger.warning('Failed to register tool plugin with server: ${toolDef.name}');
          success = false;
        }
      } catch (e) {
        _logger.error('Error registering tool plugin ${plugin.name} with server: $e');
        success = false;
      }
    }

    return success;
  }

  /// Register prompt plugins with the server
  Future<bool> registerPromptPluginsWithServer({String? serverId}) async {
    if (!hasMcpServer) {
      _logger.warning('Cannot register prompt plugins: MCP server is not available');
      return false;
    }

    bool success = true;
    final promptPlugins = pluginManager.getAllPromptPlugins();

    for (final plugin in promptPlugins) {
      try {
        final promptDef = plugin.getPromptDefinition();

        // Create adapter function for prompt execution
        serverHandler(Map<String, dynamic> args) async {
          final pluginResult = await plugin.execute(args);
          // Plugin result is already in the correct format with dynamic typing
          return pluginResult;
        }

        // Convert arguments to the expected format
        final arguments = promptDef.arguments.map((arg) => {
          'name': arg.name,
          'description': arg.description,
          'required': arg.required,
          if (arg.defaultValue != null) 'default': arg.defaultValue,
        }).toList();

        final result = await serverManager!.registerPrompt(
          name: promptDef.name,
          description: promptDef.description,
          arguments: arguments,
          handler: serverHandler,
          serverId: serverId,
        );

        if (result) {
          _logger.info('Registered prompt plugin with server: ${promptDef.name}');
        } else {
          _logger.warning('Failed to register prompt plugin with server: ${promptDef.name}');
          success = false;
        }
      } catch (e) {
        _logger.error('Error registering prompt plugin ${plugin.name} with server: $e');
        success = false;
      }
    }

    return success;
  }

  /// Register resource plugins with the server
  Future<bool> registerResourcePluginsWithServer({String? serverId}) async {
    if (!hasMcpServer) {
      _logger.warning('Cannot register resource plugins: MCP server is not available');
      return false;
    }

    bool success = true;
    final resourcePlugins = pluginManager.getAllResourcePlugins();

    for (final plugin in resourcePlugins) {
      try {
        final resourceDef = plugin.getResourceDefinition();

        // Create adapter function that converts between plugin and server formats
        serverHandler(String uri, Map<String, dynamic> params) async {
          final pluginResult = await plugin.read(params);
          // Plugin result is already in the correct format
          return pluginResult;
        }

        // Ensure the MIME type is not null (use default if necessary)
        final mimeType = resourceDef.mimeType ?? 'application/octet-stream';

        final result = await serverManager!.registerResource(
          uri: resourceDef.uri,
          name: resourceDef.name,
          description: resourceDef.description,
          mimeType: mimeType,
          handler: serverHandler,
          serverId: serverId,
        );

        if (result) {
          _logger.info('Registered resource plugin with server: ${resourceDef.name}');
        } else {
          _logger.warning('Failed to register resource plugin with server: ${resourceDef.name}');
          success = false;
        }
      } catch (e) {
        _logger.error('Error registering resource plugin ${plugin.name} with server: $e');
        success = false;
      }
    }

    return success;
  }

  /// Ask LLM and get response (similar to chat in LlmClient)
  ///
  /// [prompt] - The prompt to send to the LLM
  /// [parameters] - Optional parameters for the LLM request
  /// [context] - Optional context information
  /// [sessionId] - Optional session ID for maintaining conversation history
  /// [systemPrompt] - Optional system prompt
  Future<LlmResponse> askLlm(String prompt, {
    Map<String, dynamic> parameters = const {},
    LlmContext? context,
    String sessionId = 'default',
    String? systemPrompt,
  }) async {
    try {
      // Update system prompt if provided
      if (systemPrompt != null) {
        // Clear existing system messages
        final nonSystemMessages = chatSession.messages
            .where((msg) => msg.role != 'system')
            .toList();

        chatSession.clearHistory();
        chatSession.addSystemMessage(systemPrompt);

        // Restore non-system messages
        for (final msg in nonSystemMessages) {
          if (msg.role == 'user') {
            chatSession.addUserMessage(msg.getTextContent());
          } else if (msg.role == 'assistant') {
            chatSession.addAssistantMessage(msg.getTextContent());
          }
        }
      }

      // Add user message to session
      chatSession.addUserMessage(prompt);

      // Create request with chat history
      final request = LlmRequest(
        prompt: prompt,
        history: chatSession.getMessagesForContext(),
        parameters: Map<String, dynamic>.from(parameters),
        context: context,
      );

      // Get completion
      final response = await llmProvider.complete(request);

      // Add assistant message to session
      chatSession.addAssistantMessage(response.text);

      return response;
    } catch (e) {
      _logger.error('Error asking LLM: $e');
      throw Exception('Failed to get LLM response: $e');
    }
  }

  /// Register a local tool that can be used directly or through LLM
  ///
  /// [name] - Tool name
  /// [description] - Tool description
  /// [inputSchema] - JSON schema for the tool's input
  /// [handler] - Function that implements the tool
  /// [registerWithServer] - Whether to also register with MCP server
  /// [serverId] - Optional specific server ID to register with
  Future<bool> registerLocalTool({
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema,
    required ToolHandler handler,
    bool registerWithServer = true,
    String? serverId,
  }) async {
    try {
      // Store locally
      localTools[name] = handler;
      _logger.info('Registered local tool: $name');

      // Register with server if requested and available
      if (registerWithServer && hasMcpServer) {
        final result = await serverManager!.registerTool(
          name: name,
          description: description,
          inputSchema: inputSchema,
          handler: handler,
          serverId: serverId,
        );

        if (!result) {
          _logger.warning('Failed to register tool with server, but kept locally: $name');
        }

        return result;
      }

      return true;
    } catch (e) {
      _logger.error('Error registering local tool: $e');
      return false;
    }
  }

  /// Execute a local tool
  ///
  /// [name] - Tool name
  /// [args] - Tool arguments
  Future<dynamic> executeLocalTool(String name, Map<String, dynamic> args) async {
    if (!localTools.containsKey(name)) {
      throw Exception('Local tool not found: $name');
    }

    try {
      _logger.debug('Executing local tool: $name');
      return await localTools[name]!(args);
    } catch (e) {
      _logger.error('Error executing local tool: $e');
      throw Exception('Failed to execute local tool "$name": $e');
    }
  }

  /// Generate and register a tool based on LLM's design as a plugin
  ///
  /// [description] - Natural language description of the tool to create
  /// [registerWithServer] - Whether to register the tool with MCP server
  /// [sessionId] - Optional session ID for maintaining conversation context
  /// [serverId] - Optional specific server ID to register with
  Future<bool> generateAndRegisterTool(String description, {
    bool registerWithServer = true,
    String sessionId = 'default',
    String? serverId,
  }) async {
    try {
      // Prompt for the LLM to design a tool
      final prompt = '''
      You are a tool designer for an AI system. Please create a tool based on this description:
      "$description"
      
      Respond in JSON format only with the following structure:
      {
        "name": "tool_name_in_snake_case",
        "description": "A clear description of the tool's purpose",
        "inputSchema": {
          "type": "object",
          "properties": {
            "param1": {
              "type": "string",
              "description": "Description of this parameter"
            },
            // Additional parameters as needed
          },
          "required": ["list", "of", "required", "parameters"]
        },
        "outputFormat": "Description of the expected output format",
        "processingLogic": "Detailed description of how the tool should process the input"
      }
      ''';

      // Get tool definition from LLM
      final response = await askLlm(prompt, sessionId: sessionId);

      // Parse JSON response
      Map<String, dynamic> toolDefinition;
      try {
        // Extract JSON from response if needed
        String jsonStr = response.text;

        // Extract JSON portion if surrounded by other text
        final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
        if (jsonMatch != null) {
          jsonStr = jsonMatch.group(0)!;
        }

        toolDefinition = jsonDecode(jsonStr);
      } catch (e) {
        _logger.error('Failed to parse tool definition JSON: $e');
        _logger.debug('Response was: ${response.text}');
        return false;
      }

      // Extract tool properties
      final toolName = toolDefinition['name'] as String;
      final toolDescription = toolDefinition['description'] as String;
      final inputSchema = toolDefinition['inputSchema'] as Map<String, dynamic>;
      final processingLogic = toolDefinition['processingLogic'] as String;

      // Create a dynamic tool plugin instance
      final dynamicToolPlugin = DynamicToolPlugin(
        name: toolName,
        description: toolDescription,
        inputSchema: inputSchema,
        processingLogic: processingLogic,
        llmServer: this,
        sessionId: '${sessionId}_$toolName',
      );

      // Register with plugin manager
      await pluginManager.registerPlugin(dynamicToolPlugin);
      _logger.info('Registered dynamic tool as plugin: $toolName');

      // Register with server if requested
      if (registerWithServer && hasMcpServer) {
        final serverSuccess = await serverManager!.registerTool(
          name: toolName,
          description: toolDescription,
          inputSchema: inputSchema,
          handler: (args) async => await dynamicToolPlugin.execute(args),
          serverId: serverId,
        );

        if (!serverSuccess) {
          _logger.warning('Failed to register dynamic tool with server: $toolName');
        } else {
          _logger.info('Registered dynamic tool with server: $toolName');
        }

        return serverSuccess;
      }

      return true;
    } catch (e) {
      _logger.error('Error generating and registering tool: $e');
      return false;
    }
  }

  /// Generate and register a prompt template based on LLM's design as a plugin
  ///
  /// [description] - Natural language description of the prompt to create
  /// [registerWithServer] - Whether to register the prompt with MCP server
  /// [sessionId] - Optional session ID for maintaining conversation context
  /// [serverId] - Optional specific server ID to register with
  Future<bool> generateAndRegisterPrompt(String description, {
    bool registerWithServer = true,
    String sessionId = 'default',
    String? serverId,
  }) async {
    if (!hasMcpServer && registerWithServer) {
      _logger.warning('Cannot register prompt with server: MCP server is not available');
      return false;
    }

    try {
      // Prompt for the LLM to design a prompt template
      final designPrompt = '''
      You are a prompt designer for an AI system. Please create a prompt template based on this description:
      "$description"
      
      Respond in JSON format only with the following structure:
      {
        "name": "prompt_name_in_snake_case",
        "description": "A clear description of the prompt's purpose",
        "arguments": [
          {
            "name": "param1",
            "description": "Description of this parameter",
            "required": true
          },
          // Additional arguments as needed
        ],
        "systemPrompt": "The system prompt that should be used with this template",
        "userPromptTemplate": "The user prompt template with {param1} placeholders"
      }
      ''';

      // Get prompt definition from LLM
      final response = await askLlm(designPrompt, sessionId: sessionId);

      // Parse JSON response
      Map<String, dynamic> promptDefinition;
      try {
        // Extract JSON from response
        String jsonStr = response.text;

        // Extract JSON portion if surrounded by other text
        final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
        if (jsonMatch != null) {
          jsonStr = jsonMatch.group(0)!;
        }

        promptDefinition = jsonDecode(jsonStr);
      } catch (e) {
        _logger.error('Failed to parse prompt definition JSON: $e');
        _logger.debug('Response was: ${response.text}');
        return false;
      }

      // Extract prompt properties
      final promptName = promptDefinition['name'] as String;
      final promptDescription = promptDefinition['description'] as String;
      final arguments = promptDefinition['arguments'] as List<dynamic>;
      final systemPrompt = promptDefinition['systemPrompt'] as String;
      final userPromptTemplate = promptDefinition['userPromptTemplate'] as String;

      // Convert arguments to LlmPromptArgument objects
      final promptArgs = arguments.map((arg) => LlmPromptArgument(
        name: arg['name'],
        description: arg['description'],
        required: arg['required'] ?? false,
        defaultValue: arg['default'],
      )).toList();

      // Create a dynamic prompt plugin
      final dynamicPromptPlugin = DynamicPromptPlugin(
        name: promptName,
        description: promptDescription,
        arguments: promptArgs,
        systemPrompt: systemPrompt,
        userPromptTemplate: userPromptTemplate,
      );

      // Register with plugin manager
      await pluginManager.registerPlugin(dynamicPromptPlugin);
      _logger.info('Registered dynamic prompt as plugin: $promptName');

      // Register with server if requested
      if (registerWithServer && hasMcpServer) {
        // Convert arguments to format expected by server
        final serverArgs = promptArgs.map((arg) => {
          'name': arg.name,
          'description': arg.description,
          'required': arg.required,
          if (arg.defaultValue != null) 'default': arg.defaultValue,
        }).toList();

        final serverSuccess = await serverManager!.registerPrompt(
          name: promptName,
          description: promptDescription,
          arguments: serverArgs,
          handler: (args) async => await dynamicPromptPlugin.execute(args),
          serverId: serverId,
        );

        if (!serverSuccess) {
          _logger.warning('Failed to register dynamic prompt with server: $promptName');
        } else {
          _logger.info('Registered dynamic prompt with server: $promptName');
        }

        return serverSuccess;
      }

      return true;
    } catch (e) {
      _logger.error('Error generating and registering prompt: $e');
      return false;
    }
  }

  /// Generate and register a resource based on LLM's design as a plugin
  ///
  /// [description] - Natural language description of the resource to create
  /// [registerWithServer] - Whether to register the resource with MCP server
  /// [sessionId] - Optional session ID for maintaining conversation context
  /// [serverId] - Optional specific server ID to register with
  Future<bool> generateAndRegisterResource(String description, {
    bool registerWithServer = true,
    String sessionId = 'default',
    String? serverId,
  }) async {
    try {
      // Prompt for the LLM to design a resource
      final prompt = '''
    You are a resource designer for an AI system. Please create a resource based on this description:
    "$description"
    
    Respond in JSON format only with the following structure:
    {
      "name": "resource_name_in_snake_case",
      "description": "A clear description of the resource's purpose",
      "uri": "resource://{type}/{identifier}",
      "mimeType": "appropriate/mime-type",
      "type": "file" or "documentation" or "data",
      "content": "Sample or default content of the resource if applicable"
    }
    ''';

      // Get resource definition from LLM
      final response = await askLlm(prompt, sessionId: sessionId);

      // Parse JSON response
      Map<String, dynamic> resourceDefinition;
      try {
        // Extract JSON from response if needed
        String jsonStr = response.text;

        // Extract JSON portion if surrounded by other text
        final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
        if (jsonMatch != null) {
          jsonStr = jsonMatch.group(0)!;
        }

        resourceDefinition = jsonDecode(jsonStr);
      } catch (e) {
        _logger.error('Failed to parse resource definition JSON: $e');
        _logger.debug('Response was: ${response.text}');
        return false;
      }

      // Extract resource properties
      final resourceName = resourceDefinition['name'] as String;
      final resourceDescription = resourceDefinition['description'] as String;
      final resourceUri = resourceDefinition['uri'] as String;
      final resourceMimeType = resourceDefinition['mimeType'] as String?;
      final resourceType = resourceDefinition['type'] as String;
      final resourceContent = resourceDefinition['content'] as String?;

      // Create dynamic resource plugin based on type
      ResourcePlugin dynamicResourcePlugin;

      if (resourceType == 'documentation') {
        // Create documentation resource
        final sections = <String, String>{};

        if (resourceContent != null) {
          sections['index'] = resourceContent;
        } else {
          // Generate index content if none provided
          final indexPrompt = '''
        Create documentation index content for a resource with this description:
        "$resourceDescription"
        
        Keep it concise but informative.
        ''';

          final indexResponse = await askLlm(indexPrompt, sessionId: '${sessionId}_${resourceName}_index');
          sections['index'] = indexResponse.text;
        }

        dynamicResourcePlugin = DocumentationResourcePlugin(
          name: resourceName,
          description: resourceDescription,
          sections: sections,
        );
      } else if (resourceType == 'file') {
        // Create file resource
        dynamicResourcePlugin = DynamicFileResourcePlugin(
          name: resourceName,
          description: resourceDescription,
          uri: resourceUri,
          mimeType: resourceMimeType,
          content: resourceContent ?? '',
          llmServer: this,
          sessionId: '${sessionId}_$resourceName',
        );
      } else {
        // Create generic resource
        dynamicResourcePlugin = DynamicResourcePlugin(
          name: resourceName,
          description: resourceDescription,
          uri: resourceUri,
          mimeType: resourceMimeType,
          content: resourceContent ?? '',
          llmServer: this,
          sessionId: '${sessionId}_$resourceName',
        );
      }

      // Register with plugin manager
      await pluginManager.registerPlugin(dynamicResourcePlugin);
      _logger.info('Registered dynamic resource as plugin: $resourceName');

      // Register with server if requested
      if (registerWithServer && hasMcpServer) {
        final serverSuccess = await serverManager!.registerResource(
          uri: resourceUri,
          name: resourceName,
          description: resourceDescription,
          mimeType: resourceMimeType ?? 'application/octet-stream',
          handler: (uri, params) async => await dynamicResourcePlugin.read(params),
          serverId: serverId,
        );

        if (!serverSuccess) {
          _logger.warning('Failed to register dynamic resource with server: $resourceName');
        } else {
          _logger.info('Registered dynamic resource with server: $resourceName');
        }

        return serverSuccess;
      }

      return true;
    } catch (e) {
      _logger.error('Error generating and registering resource: $e');
      return false;
    }
  }

  /// Register capabilities (tools, prompts, resources) from a description file
  /// Creates plugins for all capabilities
  ///
  /// [filePath] - Path to the description file
  /// [serverId] - Optional specific server ID to register with
  Future<bool> registerCapabilitiesFromFile(String filePath, {String? serverId}) async {
    try {
      // Read the file
      final file = File(filePath);
      if (!await file.exists()) {
        _logger.error('Capabilities file not found: $filePath');
        return false;
      }

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      int successCount = 0;
      int totalCount = 0;

      // Process tools
      if (data.containsKey('tools') && data['tools'] is List) {
        final tools = data['tools'] as List;
        for (final toolDesc in tools) {
          totalCount++;
          final success = await generateAndRegisterTool(
              toolDesc.toString(),
              serverId: serverId
          );
          if (success) successCount++;
        }
      }

      // Process prompts
      if (data.containsKey('prompts') && data['prompts'] is List) {
        final prompts = data['prompts'] as List;
        for (final promptDesc in prompts) {
          totalCount++;
          final success = await generateAndRegisterPrompt(
              promptDesc.toString(),
              serverId: serverId
          );
          if (success) successCount++;
        }
      }

      // Process resources
      if (data.containsKey('resources') && data['resources'] is List) {
        final resources = data['resources'] as List;
        for (final resourceDesc in resources) {
          totalCount++;
          final success = await generateAndRegisterResource(
              resourceDesc.toString(),
              serverId: serverId
          );
          if (success) successCount++;
        }
      }

      _logger.info('Registered $successCount/$totalCount capabilities from file');
      return successCount > 0;
    } catch (e) {
      _logger.error('Error registering capabilities from file: $e');
      return false;
    }
  }

  /// Process a query using LLM with optional tool augmentation
  ///
  /// Similar to LlmClient.chat but on the server side
  /// [query] - The user query to process
  /// [useLocalTools] - Whether to allow LLM to use registered local tools
  /// [usePluginTools] - Whether to allow LLM to use plugin tools
  /// [parameters] - Optional parameters for the LLM request
  /// [sessionId] - Optional session ID for maintaining conversation context
  /// [systemPrompt] - Optional system prompt to use
  /// [sendToolResultsToLlm] - Whether to send tool results back to LLM or return directly
  /// [serverId] - Optional specific server ID to use for tool execution
  Future<Map<String, dynamic>> processQuery({
    required String query,
    bool useLocalTools = true,
    bool usePluginTools = true,
    Map<String, dynamic> parameters = const {},
    String sessionId = 'default',
    String? systemPrompt,
    bool sendToolResultsToLlm = true,
    String? serverId,
  }) async {
    final requestId = _performanceMonitor.startRequest('process_query');

    try {
      // Update system prompt if provided
      if (systemPrompt != null) {
        // Save non-system messages
        final nonSystemMessages = chatSession.messages
            .where((msg) => msg.role != 'system')
            .toList();

        // Clear history and add new system message
        chatSession.clearHistory();
        chatSession.addSystemMessage(systemPrompt);

        // Restore non-system messages
        for (final msg in nonSystemMessages) {
          if (msg.role == 'user') {
            chatSession.addUserMessage(msg.getTextContent());
          } else if (msg.role == 'assistant') {
            chatSession.addAssistantMessage(msg.getTextContent());
          }
        }
      }

      // Add user message to session
      chatSession.addUserMessage(query);

      // Get available tools if needed
      Map<String, dynamic> effectiveParameters = Map<String, dynamic>.from(parameters);
      if ((useLocalTools && localTools.isNotEmpty) ||
          (usePluginTools && pluginManager.getAllToolPlugins().isNotEmpty)) {

        final toolDescriptions = <Map<String, dynamic>>[];

        // Get registered tools from server if available
        if (hasMcpServer) {
          try {
            final serverTools = await serverManager!.getTools(serverId);
            for (final tool in serverTools) {
              toolDescriptions.add({
                'name': tool['name'],
                'description': tool['description'],
                'parameters': tool['inputSchema'] ?? tool['schema'],
              });
            }
          } catch (e) {
            _logger.warning('Error getting server tools: $e');
          }
        }

        // Add local tools
        if (useLocalTools) {
          for (final name in localTools.keys) {
            // Skip if already added from server
            if (toolDescriptions.any((t) => t['name'] == name)) {
              continue;
            }

            // Add basic description (without schema)
            toolDescriptions.add({
              'name': name,
              'description': 'Local tool: $name',
            });
          }
        }

        // Add plugin tools
        if (usePluginTools) {
          for (final plugin in pluginManager.getAllToolPlugins()) {
            // Skip if already added
            if (toolDescriptions.any((t) => t['name'] == plugin.name)) {
              continue;
            }

            final toolDef = plugin.getToolDefinition();
            toolDescriptions.add({
              'name': toolDef.name,
              'description': toolDef.description,
              'parameters': toolDef.inputSchema,
            });
          }
        }

        // Add tool descriptions to parameters
        if (toolDescriptions.isNotEmpty) {
          effectiveParameters['tools'] = toolDescriptions;
        }
      }

      // Create request
      final request = LlmRequest(
        prompt: query,
        history: chatSession.getMessagesForContext(),
        parameters: effectiveParameters,
      );

      // Send request to LLM
      LlmResponse response = await llmProvider.complete(request);

      // Add to chat session only if there's initial text
      String initialResponse = '';
      if (response.text.isNotEmpty) {
        chatSession.addAssistantMessage(response.text);
        initialResponse = response.text;
      }

      // Check for tool calls
      if (response.toolCalls != null && response.toolCalls!.isNotEmpty) {
        final toolCalls = response.toolCalls!;
        final toolResults = <String, dynamic>{};
        final toolErrors = <String, String>{};

        // Execute all tools
        for (final toolCall in toolCalls) {
          final toolId = toolCall.id ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
          final toolName = toolCall.name;

          try {
            // Try server tool first if available
            if (hasMcpServer) {
              try {
                final result = await serverManager!.executeTool(
                    toolName,
                    toolCall.arguments,
                    serverId: serverId,
                    tryAllServers: serverId == null
                );
                toolResults[toolId] = result;
                continue;
              } catch (e) {
                _logger.debug('Server tool execution failed, trying local: $e');
                // Continue to other options
              }
            }

            // Try local tool if enabled
            if (useLocalTools && localTools.containsKey(toolName)) {
              final result = await executeLocalTool(toolName, toolCall.arguments);
              toolResults[toolId] = result;
              continue;
            }

            // Try plugin tool if enabled
            if (usePluginTools) {
              final plugin = pluginManager.getToolPlugin(toolName);
              if (plugin != null) {
                final result = await plugin.execute(toolCall.arguments);
                toolResults[toolId] = result;
                continue;
              }
            }

            // No matching tool found
            throw Exception('Tool not found: $toolName');
          } catch (e) {
            _logger.error('Error executing tool $toolName: $e');
            toolErrors[toolId] = e.toString();
          }
        }

        // If there are tool errors but no results, return error
        if (toolResults.isEmpty && toolErrors.isNotEmpty) {
          final firstError = toolErrors.entries.first;
          _performanceMonitor.endRequest(requestId, success: false);

          return {
            'initialResponse': initialResponse,
            'error': 'Tool execution failed: ${firstError.value}',
            'toolCallId': firstError.key,
          };
        }

        // If we have tool results and should send to LLM, create follow-up request
        if (toolResults.isNotEmpty && sendToolResultsToLlm) {
          final toolResultsInfo = toolResults.entries.map((entry) =>
          "Tool result for call ${entry.key}: ${jsonEncode(entry.value)}"
          ).join("\n");

          // Create follow-up request
          final followUpRequest = LlmRequest(
            prompt: "Based on the tool results, answer the original question: \"$query\"\n\nTool results:\n$toolResultsInfo",
            history: chatSession.getMessagesForContext(),
            parameters: parameters,
          );

          // Get follow-up response
          try {
            final followUpResponse = await llmProvider.complete(followUpRequest);

            // Add to chat session
            if (followUpResponse.text.isNotEmpty) {
              chatSession.addAssistantMessage(followUpResponse.text);
            }

            _performanceMonitor.endRequest(requestId, success: true);

            // Return combined response
            return {
              'initialResponse': initialResponse,
              'toolResults': toolResults,
              'finalResponse': followUpResponse.text,
              'combinedResponse': initialResponse.isNotEmpty
                  ? "$initialResponse\n\n${followUpResponse.text}"
                  : followUpResponse.text,
            };
          } catch (e) {
            _logger.error('Error getting follow-up response: $e');
            _performanceMonitor.endRequest(requestId, success: false);

            return {
              'initialResponse': initialResponse,
              'toolResults': toolResults,
              'error': 'Error generating final response: $e',
            };
          }
        } else if (toolResults.isNotEmpty) {
          // Return tool results directly without sending back to LLM
          _performanceMonitor.endRequest(requestId, success: true);

          return {
            'initialResponse': initialResponse,
            'toolResults': toolResults,
            'directToolResponse': true,
          };
        }
      }

      // Return original response if no tool calls or no tool results
      _performanceMonitor.endRequest(requestId, success: true);

      return {
        'response': response.text,
        'metadata': response.metadata,
      };
    } catch (e) {
      _logger.error('Error processing query: $e');
      _performanceMonitor.endRequest(requestId, success: false);

      return {
        'error': 'Error processing query: $e',
      };
    }
  }

  /// Stream process a query using LLM with optional tool augmentation
  ///
  /// [query] - The user query to process
  /// [useLocalTools] - Whether to allow LLM to use registered local tools
  /// [usePluginTools] - Whether to allow LLM to use plugin tools
  /// [parameters] - Optional parameters for the LLM request
  /// [sessionId] - Optional session ID for maintaining conversation context
  /// [systemPrompt] - Optional system prompt to use
  /// [serverId] - Optional specific server ID to use for tool execution
  Stream<Map<String, dynamic>> streamProcessQuery({
    required String query,
    bool useLocalTools = true,
    bool usePluginTools = true,
    Map<String, dynamic> parameters = const {},
    String sessionId = 'default',
    String? systemPrompt,
    String? serverId,
  }) async* {
    try {
      // Update system prompt if provided
      if (systemPrompt != null) {
        // Save non-system messages
        final nonSystemMessages = chatSession.messages
            .where((msg) => msg.role != 'system')
            .toList();

        // Clear history and add new system message
        chatSession.clearHistory();
        chatSession.addSystemMessage(systemPrompt);

        // Restore non-system messages
        for (final msg in nonSystemMessages) {
          if (msg.role == 'user') {
            chatSession.addUserMessage(msg.getTextContent());
          } else if (msg.role == 'assistant') {
            chatSession.addAssistantMessage(msg.getTextContent());
          }
        }
      }

      // Add user message to session
      chatSession.addUserMessage(query);

      // Get available tools if needed
      Map<String, dynamic> effectiveParameters = Map<String, dynamic>.from(parameters);
      if ((useLocalTools && localTools.isNotEmpty) ||
          (usePluginTools && pluginManager.getAllToolPlugins().isNotEmpty)) {

        final toolDescriptions = <Map<String, dynamic>>[];

        // Get registered tools from server if available
        if (hasMcpServer) {
          try {
            final serverTools = await serverManager!.getTools(serverId);
            for (final tool in serverTools) {
              toolDescriptions.add({
                'name': tool['name'],
                'description': tool['description'],
                'parameters': tool['inputSchema'] ?? tool['schema'],
              });
            }
          } catch (e) {
            _logger.warning('Error getting server tools: $e');
          }
        }

        // Add local tools
        if (useLocalTools) {
          for (final name in localTools.keys) {
            // Skip if already added from server
            if (toolDescriptions.any((t) => t['name'] == name)) {
              continue;
            }

            // Add basic description (without schema)
            toolDescriptions.add({
              'name': name,
              'description': 'Local tool: $name',
            });
          }
        }

        // Add plugin tools
        if (usePluginTools) {
          for (final plugin in pluginManager.getAllToolPlugins()) {
            // Skip if already added
            if (toolDescriptions.any((t) => t['name'] == plugin.name)) {
              continue;
            }

            final toolDef = plugin.getToolDefinition();
            toolDescriptions.add({
              'name': toolDef.name,
              'description': toolDef.description,
              'parameters': toolDef.inputSchema,
            });
          }
        }

        // Add tool descriptions to parameters
        if (toolDescriptions.isNotEmpty) {
          effectiveParameters['tools'] = toolDescriptions;
        }
      }

      // Create request
      final request = LlmRequest(
        prompt: query,
        history: chatSession.getMessagesForContext(),
        parameters: effectiveParameters,
      );

      // Stream response from LLM
      final responseBuffer = StringBuffer();

      await for (final chunk in llmProvider.streamComplete(request)) {
        yield {
          'chunk': chunk.textChunk,
          'isDone': chunk.isDone,
          'metadata': chunk.metadata,
        };

        responseBuffer.write(chunk.textChunk);

        if (chunk.isDone) {
          // Add the complete response to the chat history
          chatSession.addAssistantMessage(responseBuffer.toString());
        }
      }
    } catch (e) {
      _logger.error('Error streaming process query: $e');
      yield {
        'error': 'Error streaming process query: $e',
        'isDone': true,
      };
    }
  }

  /// Get all available tools from all servers
  Future<List<Map<String, dynamic>>> getAllServerTools() async {
    if (!hasMcpServer) {
      return [];
    }

    return await serverManager!.getTools();
  }

  /// Get all available prompts from all servers
  Future<List<Map<String, dynamic>>> getAllServerPrompts() async {
    if (!hasMcpServer) {
      return [];
    }

    return await serverManager!.getPrompts();
  }

  /// Get all available resources from all servers
  Future<List<Map<String, dynamic>>> getAllServerResources() async {
    if (!hasMcpServer) {
      return [];
    }

    return await serverManager!.getResources();
  }

  /// Get tools from a specific server
  Future<List<Map<String, dynamic>>> getServerTools(String serverId) async {
    if (!hasMcpServer) {
      return [];
    }

    return await serverManager!.getTools(serverId);
  }

  /// Get prompts from a specific server
  Future<List<Map<String, dynamic>>> getServerPrompts(String serverId) async {
    if (!hasMcpServer) {
      return [];
    }

    return await serverManager!.getPrompts(serverId);
  }

  /// Get resources from a specific server
  Future<List<Map<String, dynamic>>> getServerResources(String serverId) async {
    if (!hasMcpServer) {
      return [];
    }

    return await serverManager!.getResources(serverId);
  }

  /// Execute a tool on all servers and collect results
  Future<Map<String, dynamic>> executeToolOnAllServers(String toolName, Map<String, dynamic> args) async {
    if (!hasMcpServer) {
      throw StateError('MCP server manager is not initialized');
    }

    return await serverManager!.executeToolOnAllServers(toolName, args);
  }

  /// Find all servers that have a specific tool
  Future<List<String>> findServersWithTool(String toolName) async {
    if (!hasMcpServer) {
      return [];
    }

    return await serverManager!.findServersWithTool(toolName);
  }

  /// Close and release resources
  Future<void> close() async {
    // Close LLM provider
    await llmProvider.close();

    // Close the retrieval manager if present
    if (retrievalManager != null) {
      await retrievalManager!.close();
    }
  }
}

/// Dynamic tool plugin generated by LLM
class DynamicToolPlugin extends BaseToolPlugin {
  final String processingLogic;
  final LlmServer llmServer;
  final String sessionId;
  final Logger _logger = Logger('mcp_llm.dynamic_tool_plugin');

  DynamicToolPlugin({
    required super.name,
    required super.description,
    required super.inputSchema,
    required this.processingLogic,
    required this.llmServer,
    required this.sessionId,
  }) : super(
    version: '1.0.0',
  );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> arguments) async {
    // Create a prompt for processing the tool request
    final handlerPrompt = '''
    You are executing the "$name" tool with these parameters:
    ${jsonEncode(arguments)}
    
    Processing logic:
    $processingLogic
    
    Respond with only the result in valid JSON format. Do not include any explanations or extra text.
    ''';

    // Execute through LLM
    try {
      final handlerResponse = await llmServer.askLlm(handlerPrompt, sessionId: sessionId);

      // Parse response - allow for both JSON object and plain text response
      String result = handlerResponse.text.trim();

      // Try to parse as JSON first
      try {
        // Check for JSON format
        if (result.startsWith('{') || result.startsWith('[')) {
          return LlmCallToolResult([LlmTextContent(text: result)]);
        }
      } catch (_) {
        // Not valid JSON, return as text
      }

      // Return as plain text
      return LlmCallToolResult([LlmTextContent(text: result)]);
    } catch (e) {
      _logger.error('Error executing dynamic tool $name: $e');
      return LlmCallToolResult(
        [LlmTextContent(text: 'Error: Failed to execute tool: $e')],
        isError: true,
      );
    }
  }
}

/// Dynamic prompt plugin generated by LLM
class DynamicPromptPlugin extends BasePromptPlugin {
  final String systemPrompt;
  final String userPromptTemplate;
  final Logger _logger = Logger('mcp_llm.dynamic_prompt_plugin');

  DynamicPromptPlugin({
    required super.name,
    required super.description,
    required super.arguments,
    required this.systemPrompt,
    required this.userPromptTemplate,
  }) : super(
    version: '1.0.0',
  );

  @override
  Future<LlmGetPromptResult> onExecute(Map<String, dynamic> arguments) async {
    try {
      // Replace placeholders in template
      String filledPrompt = userPromptTemplate;

      // Replace each {parameter} with its value
      arguments.forEach((key, value) {
        filledPrompt = filledPrompt.replaceAll('{$key}', value.toString());
      });

      // Create messages array for the prompt
      final messages = [
        LlmMessage.system(systemPrompt),
        LlmMessage.user(filledPrompt),
      ];

      return LlmGetPromptResult(
        description: description,
        messages: messages,
      );
    } catch (e) {
      _logger.error('Error processing prompt template: $e');
      return LlmGetPromptResult(
        description: 'Error',
        messages: [LlmMessage.system('Failed to process prompt template: $e')],
      );
    }
  }
}

/// Dynamic resource plugin generated by LLM
class DynamicResourcePlugin extends BaseResourcePlugin {
  final String content;
  final LlmServer llmServer;
  final String sessionId;
  final Logger _logger = Logger('mcp_llm.dynamic_resource_plugin');

  DynamicResourcePlugin({
    required super.name,
    required super.description,
    required super.uri,
    required this.content,
    required this.llmServer,
    required this.sessionId,
    super.mimeType,
    super.uriTemplate,
  }) : super(
    version: '1.0.0',
  );

  @override
  Future<LlmReadResourceResult> onRead(Map<String, dynamic> parameters) async {
    // Return initial content for simple read
    if (parameters.isEmpty || (parameters.length == 1 && parameters.containsKey('format'))) {
      return LlmReadResourceResult(
        content: content,
        mimeType: mimeType ?? 'application/octet-stream',
        contents: [LlmTextContent(text: content)],
      );
    }

    // For parameterized reads, use LLM to generate appropriate response
    final handlerPrompt = '''
    You are providing access to the "$name" resource with these parameters:
    ${jsonEncode(parameters)}
    
    Resource description: $description
    Resource baseline content: 
    """
    $content
    """
    
    Generate appropriate content based on the parameters provided.
    Respond with only the content in the appropriate format. Do not include explanations.
    ''';

    // Execute through LLM
    try {
      final handlerResponse = await llmServer.askLlm(handlerPrompt, sessionId: sessionId);
      return LlmReadResourceResult(
        content: handlerResponse.text,
        mimeType: mimeType ?? 'application/octet-stream',
        contents: [LlmTextContent(text: handlerResponse.text)],
      );
    } catch (e) {
      _logger.error('Error generating dynamic resource content for $name: $e');
      return LlmReadResourceResult(
        content: 'Error: Failed to generate resource content: $e',
        mimeType: 'text/plain',
        contents: [LlmTextContent(text: 'Error: Failed to generate resource content: $e')],
      );
    }
  }
}

/// Dynamic file resource plugin that can generate file content on demand
class DynamicFileResourcePlugin extends BaseResourcePlugin {
  final String content;
  final LlmServer llmServer;
  final String sessionId;
  final Logger _logger = Logger('mcp_llm.dynamic_file_resource_plugin');

  DynamicFileResourcePlugin({
    required super.name,
    required super.description,
    required super.uri,
    required this.content,
    required this.llmServer,
    required this.sessionId,
    super.mimeType,
    super.uriTemplate,
  }) : super(
    version: '1.0.0',
  );

  @override
  Future<LlmReadResourceResult> onRead(Map<String, dynamic> parameters) async {
    // Handle file format transformations
    String targetFormat = parameters['format'] as String? ?? '';
    String path = parameters['path'] as String? ?? '';

    // If no special processing needed, return base content
    if (targetFormat.isEmpty && path.isEmpty) {
      return LlmReadResourceResult(
        content: content,
        mimeType: mimeType ?? 'application/octet-stream',
        contents: [LlmTextContent(text: content)],
      );
    }

    // Create prompt based on parameters
    String handlerPrompt;

    if (path.isNotEmpty) {
      // Handle path-based request (virtual file system)
      handlerPrompt = '''
      You are providing access to the "$name" file resource with path: "$path"
      
      Base directory structure is derived from this content:
      """
      $content
      """
      
      If the requested path exists in the context of this resource, provide its content.
      If the path does not exist, respond with "File not found: $path"
      
      Respond with only the file content or error message. Do not include explanations.
      ''';
    } else if (targetFormat.isNotEmpty) {
      // Handle format conversion
      handlerPrompt = '''
      You are providing access to the "$name" file resource and need to convert it to "$targetFormat" format.
      
      Original content:
      """
      $content
      """
      
      Convert this content to $targetFormat format and respond with only the converted content.
      ''';
    } else {
      // Default case (shouldn't happen but for safety)
      return LlmReadResourceResult(
        content: content,
        mimeType: mimeType ?? 'application/octet-stream',
        contents: [LlmTextContent(text: content)],
      );
    }

    // Execute through LLM
    try {
      final handlerResponse = await llmServer.askLlm(handlerPrompt, sessionId: sessionId);

      // Determine appropriate MIME type for format conversion
      String effectiveMimeType = mimeType ?? 'application/octet-stream';
      if (targetFormat.isNotEmpty) {
        effectiveMimeType = _getMimeTypeForFormat(targetFormat);
      }

      return LlmReadResourceResult(
        content: handlerResponse.text,
        mimeType: effectiveMimeType,
        contents: [LlmTextContent(text: handlerResponse.text)],
      );
    } catch (e) {
      _logger.error('Error processing file resource $name: $e');
      return LlmReadResourceResult(
        content: 'Error: Failed to process file resource: $e',
        mimeType: 'text/plain',
        contents: [LlmTextContent(text: 'Error: Failed to process file resource: $e')],
      );
    }
  }

  /// Map format to MIME type
  String _getMimeTypeForFormat(String format) {
    final formatMap = {
      'json': 'application/json',
      'xml': 'application/xml',
      'html': 'text/html',
      'markdown': 'text/markdown',
      'md': 'text/markdown',
      'text': 'text/plain',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'yaml': 'application/x-yaml',
      'yml': 'application/x-yaml',
    };

    return formatMap[format.toLowerCase()] ?? (mimeType ?? 'application/octet-stream');
  }
}