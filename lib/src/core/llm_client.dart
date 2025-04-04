// lib/src/core/llm_client.dart

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

  /// Plugin manager
  final PluginManager pluginManager;

  /// Performance monitor
  final PerformanceMonitor _performanceMonitor;

  /// Retrieval manager for RAG capabilities
  final RetrievalManager? retrievalManager;

  /// Chat session for maintaining conversation
  late final ChatSession chatSession;

  /// Logger instance
  final Logger _logger = Logger.getLogger('mcp_llm.llm_client');

  /// Create a new LLM client
  LlmClient({
    required this.llmProvider,
    dynamic mcpClient,
    this.storageManager,
    PluginManager? pluginManager,
    PerformanceMonitor? performanceMonitor,
    this.retrievalManager,
  })
      : _mcpClient = mcpClient,
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

  /// Check if retrieval capabilities are available
  bool get hasRetrievalCapabilities => retrievalManager != null;

  /// Send chat message and get response
  Future<LlmResponse> chat(String userInput, {
    bool enableTools = true,
    bool enablePlugins = true,
    Map<String, dynamic> parameters = const {},
    LlmContext? context,
    bool useRetrieval = false,
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

      // Handle retrieval-augmented generation if enabled and available
      if (useRetrieval && retrievalManager != null) {
        final ragResponse = await _handleRetrievalAugmentedResponse(
            userInput,
            parameters,
            context
        );

        // Add assistant message to session
        chatSession.addAssistantMessage(ragResponse.text);

        _performanceMonitor.endRequest(requestId, success: true);
        return ragResponse;
      }

      // Create LLM request
      final request = LlmRequest(
        prompt: userInput,
        history: chatSession.getMessagesForContext(),
        parameters: parameters,
        context: context,
      );

      // Add tools information if available
      if (availableTools.isNotEmpty) {
        final toolDescriptions = availableTools.map((tool) =>
        {
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

  /// Handle Retrieval-Augmented Generation (RAG)
  Future<LlmResponse> _handleRetrievalAugmentedResponse(String userInput,
      Map<String, dynamic> parameters,
      LlmContext? context,) async {
    try {
      _logger.debug(
          'Using retrieval-augmented generation for input: $userInput');

      // Get conversation history for context-aware search
      final previousQueries = chatSession.userMessages
          .map((msg) => msg.getTextContent())
          .where((text) => text.isNotEmpty)
          .toList();

      // Remove current query from previous queries
      if (previousQueries.isNotEmpty && previousQueries.last == userInput) {
        previousQueries.removeLast();
      }

      // Generate RAG response
      final ragText = await retrievalManager!.retrieveAndGenerate(
        userInput,
        topK: 5,
        generationParams: parameters,
        previousQueries: previousQueries,
        useHybridSearch: true,
      );

      return LlmResponse(
        text: ragText,
        metadata: {
          'rag_enabled': true,
          'context_size': previousQueries.length,
        },
      );
    } catch (e) {
      _logger.error('Error in retrieval-augmented generation: $e');
      throw Exception('Failed to generate retrieval-augmented response: $e');
    }
  }

  /// Handle tool calls in response
  Future<LlmResponse> _handleToolCalls(LlmResponse response,
      String userInput,
      bool enableTools,
      bool enablePlugins,
      Map<String, dynamic> parameters,
      LlmContext? context,) async {
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
          text: "I tried to use a tool called '${toolCall
              .name}', but encountered an error: $e",
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
  Future<dynamic> _executeTool(String toolName,
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
    bool useRetrieval = false,
  }) async* {
    // Add user message to session
    chatSession.addUserMessage(userInput);

    // Handle RAG if enabled
    if (useRetrieval && retrievalManager != null) {
      // Streaming not fully supported with RAG, use non-streaming version
      try {
        final ragResponse = await _handleRetrievalAugmentedResponse(
            userInput,
            parameters,
            context
        );

        // Add assistant message to session
        chatSession.addAssistantMessage(ragResponse.text);

        // Simulate streaming with the full response
        yield LlmResponseChunk(
          textChunk: ragResponse.text,
          isDone: true,
          metadata: {'rag_enabled': true},
        );

        return;
      } catch (e) {
        _logger.error('Error in retrieval-augmented generation: $e');
        yield LlmResponseChunk(
          textChunk: 'Error with retrieval-augmented generation: $e',
          isDone: true,
          metadata: {'error': e.toString()},
        );
        return;
      }
    }

    // Collect available tools
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
      final toolDescriptions = availableTools.map((tool) =>
      {
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

  /// Retrieve relevant documents for a query
  Future<List<Document>> retrieveRelevantDocuments(String query, {
    int topK = 5,
    double? minimumScore,
    String? namespace,
    Map<String, dynamic> filters = const {},
    bool useCache = true,
  }) async {
    if (retrievalManager == null) {
      throw StateError('Retrieval manager is not configured for this client');
    }

    return await retrievalManager!.retrieveRelevant(
      query,
      topK: topK,
      minimumScore: minimumScore,
      namespace: namespace,
      filters: filters,
      useCache: useCache,
    );
  }

  /// Add document to retrieval system
  Future<String> addDocument(Document document) async {
    if (retrievalManager == null) {
      throw StateError('Retrieval manager is not configured for this client');
    }

    return await retrievalManager!.addDocument(document);
  }

  /// Add multiple documents to retrieval system
  Future<List<String>> addDocuments(List<Document> documents) async {
    if (retrievalManager == null) {
      throw StateError('Retrieval manager is not configured for this client');
    }

    return await retrievalManager!.addDocuments(documents);
  }

  /// Generate embeddings for text
  Future<List<double>> generateEmbeddings(String text) async {
    return await llmProvider.getEmbeddings(text);
  }

  /// Close and clean up resources
  Future<void> close() async {
    await llmProvider.close();

    // Close retrieval manager if exists
    if (retrievalManager != null) {
      await retrievalManager!.close();
    }

    _performanceMonitor.stopMonitoring();
  }
}