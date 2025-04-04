import '../../mcp_llm.dart';
import '../adapter/llm_client_adapter.dart';

/// Client for interacting with LLM providers
class LlmClient {
  /// LLM provider
  final LlmInterface llmProvider;

  /// MCP client adapter
  final LlmClientAdapter? _clientAdapter;

  /// Raw MCP client instance
  final dynamic _mcpClient;

  /// Storage manager
  final StorageManager? storageManager;

  /// Retrieval manager for RAG
  final RetrievalManager? retrievalManager;

  /// Plugin manager
  final PluginManager pluginManager;

  /// Performance monitor
  final PerformanceMonitor _performanceMonitor;

  /// Chat session for maintaining conversation
  late final ChatSession chatSession;

  /// Logger instance
  final Logger _logger = Logger.getLogger('mcp_llm.llm_client');

  /// Create a new LLM client
  LlmClient({
    required this.llmProvider,
    dynamic mcpClient,
    this.storageManager,
    this.retrievalManager,
    PluginManager? pluginManager,
    PerformanceMonitor? performanceMonitor,
  }) : _mcpClient = mcpClient,
        _clientAdapter = mcpClient != null ? LlmClientAdapter(mcpClient) : null,
        pluginManager = pluginManager ?? PluginManager(),
        _performanceMonitor = performanceMonitor ?? PerformanceMonitor() {
    chatSession = ChatSession(
      llmProvider: llmProvider,
      storageManager: storageManager,
    );
  }


  /// Check if MCP client is available
  bool get hasMcpClient => _mcpClient != null && _clientAdapter != null;

  /// Send chat message and get response
  Future<LlmResponse> chat(String userInput, {
    bool enableTools = true,
    bool enablePlugins = true,
    Map<String, dynamic> parameters = const {},
    LlmContext? context,
  }) async {
    final requestId = _performanceMonitor.startRequest('chat');

    try {
      // Add user message to session
      chatSession.addUserMessage(userInput);

      // Collect available tools
      final availableTools = await _collectAvailableTools(
        enableMcpTools: enableTools,
        enablePlugins: enablePlugins,
      );

      // Create LLM request
      final request = LlmRequest(
        prompt: userInput,
        history: chatSession.getMessagesForContext(),
        parameters: parameters,
        context: context,
      );

      // Add tools information if available
      if (availableTools.isNotEmpty) {
        final toolDescriptions = availableTools.map((tool) => {
          'name': tool['name'],
          'description': tool['description'],
          'parameters': tool['inputSchema'],
        }).toList();

        request.parameters['tools'] = toolDescriptions;
      }

      // Send request to LLM
      LlmResponse response = await llmProvider.complete(request);

      // Handle tool calls if any
      if (response.toolCalls != null && response.toolCalls!.isNotEmpty) {
        response = await _handleToolCalls(
            response,
            userInput,
            enableTools,
            enablePlugins,
            parameters,
            context
        );
      }

      // Add assistant message to session
      chatSession.addAssistantMessage(response.text);

      _performanceMonitor.endRequest(requestId, success: true);
      return response;
    } catch (e) {
      _logger.error('Error in chat: $e');
      _performanceMonitor.endRequest(requestId, success: false);

      // Return error response
      final errorResponse = LlmResponse(
        text: 'Error: Unable to process your request. $e',
        metadata: {'error': e.toString()},
      );

      chatSession.addAssistantMessage(errorResponse.text);
      return errorResponse;
    }
  }

  /// Handle tool calls in response
  Future<LlmResponse> _handleToolCalls(
      LlmResponse response,
      String userInput,
      bool enableTools,
      bool enablePlugins,
      Map<String, dynamic> parameters,
      LlmContext? context,
      ) async {
    for (final toolCall in response.toolCalls!) {
      try {
        // Try executing the tool
        final toolResult = await _executeTool(
          toolCall.name,
          toolCall.arguments,
          enableMcpTools: enableTools,
          enablePlugins: enablePlugins,
        );

        // Add tool result to session
        chatSession.addToolResult(
          toolCall.name,
          toolCall.arguments,
          [toolResult],
        );

        // Create follow-up request
        final followUpRequest = LlmRequest(
          prompt: "Based on the tool result, answer the original question: \"$userInput\"",
          history: chatSession.getMessagesForContext(),
          parameters: parameters,
          context: context,
        );

        // Get follow-up response
        response = await llmProvider.complete(followUpRequest);
      } catch (e) {
        _logger.error('Error executing tool ${toolCall.name}: $e');
        chatSession.addToolError(toolCall.name, e.toString());

        // Create error response
        response = LlmResponse(
          text: "I tried to use a tool called '${toolCall.name}', but encountered an error: $e",
          metadata: {'error': e.toString()},
        );
      }
    }

    return response;
  }

  /// Collect available tools from MCP client and plugins
  Future<List<Map<String, dynamic>>> _collectAvailableTools({
    bool enableMcpTools = true,
    bool enablePlugins = true,
  }) async {
    final tools = <Map<String, dynamic>>[];

    // Get tools from MCP client
    if (enableMcpTools && _clientAdapter != null) {
      try {
        final mcpTools = await _clientAdapter.getTools();
        tools.addAll(mcpTools);
      } catch (e) {
        _logger.warning('Failed to get tools from MCP client: $e');
      }
    }

    // Get tools from plugins
    if (enablePlugins) {
      try {
        final plugins = pluginManager.getAllToolPlugins();
        for (final plugin in plugins) {
          final toolDef = plugin.getToolDefinition();
          tools.add({
            'name': toolDef.name,
            'description': toolDef.description,
            'inputSchema': toolDef.inputSchema,
          });
        }
      } catch (e) {
        _logger.warning('Failed to get tools from plugins: $e');
      }
    }

    return tools;
  }

  /// Execute tool using MCP client or plugins
  Future<dynamic> _executeTool(
      String toolName,
      Map<String, dynamic> args, {
        bool enableMcpTools = true,
        bool enablePlugins = true,
      }) async {
    // Try MCP client first
    if (enableMcpTools && _clientAdapter != null) {
      try {
        final result = await _clientAdapter.executeTool(toolName, args);
        if (!result.containsKey('error')) {
          return result;
        }
      } catch (e) {
        _logger.warning('MCP tool execution failed: $e');
        // Continue to try plugins
      }
    }

    // Try plugins
    if (enablePlugins) {
      try {
        final plugin = pluginManager.getToolPlugin(toolName);
        if (plugin != null) {
          final result = await plugin.execute(args);
          return result.content;
        }
      } catch (e) {
        _logger.warning('Plugin tool execution failed: $e');
      }
    }

    throw Exception('Tool not found or execution failed: $toolName');
  }

  /// Stream chat responses
  Stream<LlmResponseChunk> streamChat(String userInput, {
    bool enableTools = true,
    bool enablePlugins = true,
    Map<String, dynamic> parameters = const {},
    LlmContext? context,
  }) async* {
    // Implementation similar to chat() but using streamComplete
    // This is a skeleton - full implementation would be more complex

    chatSession.addUserMessage(userInput);

    final availableTools = await _collectAvailableTools(
      enableMcpTools: enableTools,
      enablePlugins: enablePlugins,
    );

    final request = LlmRequest(
      prompt: userInput,
      history: chatSession.getMessagesForContext(),
      parameters: parameters,
      context: context,
    );

    if (availableTools.isNotEmpty) {
      final toolDescriptions = availableTools.map((tool) => {
        'name': tool['name'],
        'description': tool['description'],
        'parameters': tool['inputSchema'],
      }).toList();

      request.parameters['tools'] = toolDescriptions;
    }

    final responseBuffer = StringBuffer();

    await for (final chunk in llmProvider.streamComplete(request)) {
      yield chunk;
      responseBuffer.write(chunk.textChunk);
    }

    // Add the complete response to the chat history
    chatSession.addAssistantMessage(responseBuffer.toString());
  }

  /// Close and clean up resources
  Future<void> close() async {
    await llmProvider.close();
    _performanceMonitor.stopMonitoring();
  }
}