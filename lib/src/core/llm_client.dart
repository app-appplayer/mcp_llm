import 'dart:convert';

import '../../mcp_llm.dart';

/// Client for interacting with LLM providers
class LlmClient {
  /// LLM provider
  final LlmInterface llmProvider;

  /// MCP client manager for multiple clients
  late final McpClientManager? _mcpClientManager;

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
    dynamic mcpClient,  // Single client (backward compatibility)
    Map<String, dynamic>? mcpClients, // Multiple clients (new feature)
    this.storageManager,
    PluginManager? pluginManager,
    PerformanceMonitor? performanceMonitor,
    this.retrievalManager,
  })
      : _mcpClientManager = _initMcpClientManager(mcpClient, mcpClients),
        pluginManager = pluginManager ?? PluginManager(),
        _performanceMonitor = performanceMonitor ?? PerformanceMonitor() {
    chatSession = ChatSession(
      llmProvider: llmProvider,
      storageManager: storageManager,
    );
  }

  /// Initialize the MCP client manager
  static McpClientManager? _initMcpClientManager(
      dynamic mcpClient, Map<String, dynamic>? mcpClients) {
    if (mcpClient != null) {
      // Create manager with single client
      return McpClientManager(defaultClient: mcpClient);
    } else if (mcpClients != null && mcpClients.isNotEmpty) {
      // Create manager with multiple clients
      final manager = McpClientManager();
      mcpClients.forEach((id, client) {
        manager.addClient(id, client);
      });
      return manager;
    }

    // No MCP clients
    return null;
  }

  /// Check if MCP client manager is available
  bool get hasMcpClientManager => _mcpClientManager != null;

  /// Add an MCP client
  void addMcpClient(String clientId, dynamic mcpClient) {
    _logger.error('addMcpClient');

    // Initialize manager if it doesn't exist
    _mcpClientManager ??= McpClientManager();
    _mcpClientManager!.addClient(clientId, mcpClient);
  }

  /// Remove an MCP client
  void removeMcpClient(String clientId) {
    if (_mcpClientManager != null) {
      _mcpClientManager.removeClient(clientId);
    }
  }

  /// Set default MCP client
  void setDefaultMcpClient(String clientId) {
    if (_mcpClientManager == null) {
      throw StateError('MCP client manager is not initialized');
    }
    _mcpClientManager.setDefaultClient(clientId);
  }

  /// Get all MCP client IDs
  List<String> getMcpClientIds() {
    return _mcpClientManager?.clientIds ?? [];
  }

  /// Check if retrieval capabilities are available
  bool get hasRetrievalCapabilities => retrievalManager != null;

  // Method to set system prompt
  void setSystemPrompt(String systemPrompt) {
    // Save non-system messages temporarily to remove existing system messages
    final nonSystemMessages = chatSession.messages
        .where((msg) => msg.role != 'system')
        .toList();

    // Clear conversation history
    chatSession.clearHistory();

    // Add new system message
    chatSession.addSystemMessage(systemPrompt);

    // Restore non-system messages
    for (final msg in nonSystemMessages) {
      if (msg.role == 'user') {
        chatSession.addUserMessage(msg.getTextContent());
      } else if (msg.role == 'assistant') {
        chatSession.addAssistantMessage(msg.getTextContent());
      }
    }

    _logger.debug('System prompt updated');
  }

  /// Add MCP information to system prompt
  Future<String> createEnhancedSystemPrompt({
    String? basePrompt,
    bool includeSystemPrompt = true,
  }) async {
    // Use existing system messages if base prompt not provided
    String effectiveBasePrompt = basePrompt ?? '';
    if (basePrompt == null) {
      final systemMessages = chatSession.messages
          .where((msg) => msg.role == 'system')
          .toList();

      if (systemMessages.isNotEmpty) {
        effectiveBasePrompt = systemMessages.first.getTextContent();
      }
    }

    final enhancedPrompt = StringBuffer(effectiveBasePrompt);

    // Include tool information
    final availableTools = await _collectAvailableTools(
      enableMcpTools: true,
      enablePlugins: true,
    );

    if (includeSystemPrompt &&  availableTools.isNotEmpty) {
      enhancedPrompt.write('\n\nGuidelines for Effective and Accurate Tool Use:\n');

      enhancedPrompt.write('1. **Use Tools When Appropriate**:\n');
      enhancedPrompt.write('   - Prefer tool invocation for tasks involving computation, structured data retrieval, or external logic.\n');
      enhancedPrompt.write('   - Use internal reasoning only when a tool is clearly not applicable or unavailable.\n\n');
      enhancedPrompt.write('2. **Avoid Guesswork for Tool-Suitable Tasks**:\n');
      enhancedPrompt.write('   - Do not simulate or approximate tool results when the tool is available and usable.\n');
      enhancedPrompt.write('   - If a tool fails, explain the failure transparently rather than simulating a result.\n\n');
      enhancedPrompt.write('3. **Follow Tool Schemas Accurately**:\n');
      enhancedPrompt.write('   - Use the correct tool name and provide all required input fields clearly.\n');
      enhancedPrompt.write('   - Avoid vague or partial calls that might cause errors.\n\n');
      enhancedPrompt.write('4. **Handle Tool Errors Gracefully**:\n');
      enhancedPrompt.write('   - If a tool call results in an error, show a clear and concise error message to the user.\n');
      enhancedPrompt.write('   - Avoid retrying internally unless instructed by the user.\n\n');
      enhancedPrompt.write('5. **Clarity in Tool Usage Reporting**:\n');
      enhancedPrompt.write('   - Indicate clearly in the response whether a tool was used.\n');
      enhancedPrompt.write('   - If no tool was used, a short explanation is helpful.\n\n');
      enhancedPrompt.write('6. **When in Doubt, Prefer Tools**:\n');
      enhancedPrompt.write('   - If the prompt may involve calculation or structured data, prefer using a tool.\n');
      enhancedPrompt.write('   - But do not force tool use when it is clearly irrelevant (e.g., casual chat).\n');
      enhancedPrompt.write('7. Evaluate Tool Results Critically:\n');
      enhancedPrompt.write('   - Do not blindly accept tool output as final. Evaluate whether the result makes sense in context.\n');
      enhancedPrompt.write('   - If the tool result seems incorrect, inconsistent, or unexpected, include it in the response and offer an alternative explanation, interpretation, or next steps.\n');
      enhancedPrompt.write('   - Clearly indicate that you are providing commentary or context **in addition to** the tool’s output, not replacing it.\n\n');

      enhancedPrompt.write('\n\nAvailable tools list:\n');
      for (int i = 0; i < availableTools.length; i++) {
        final tool = availableTools[i];
        enhancedPrompt.write('${i+1}. ${tool['name']} - ${tool['description']}\n');

        // Add input parameter information
        final inputSchema = tool['inputSchema'] as Map<String, dynamic>?;
        if (inputSchema != null && inputSchema.containsKey('properties')) {
          final properties = inputSchema['properties'] as Map<String, dynamic>?;
          if (properties != null && properties.isNotEmpty) {
            enhancedPrompt.write('   Parameters:\n');
            properties.forEach((key, value) {
              final propMap = value as Map<String, dynamic>;
              final description = propMap['description'] as String? ?? '';
              final type = propMap['type'] as String? ?? 'any';
              enhancedPrompt.write('   - $key ($type): $description\n');
            });
          }
        }
        enhancedPrompt.write('\n');
      }
    }

    // Include prompt information
    final availablePrompts = await _collectAvailablePrompts(
      enableMcpPrompts: true,
      enablePlugins: true,
    );

    if (includeSystemPrompt && availablePrompts.isNotEmpty) {
      enhancedPrompt.write('\nPrompt usage guidelines:\n');
      enhancedPrompt.write('1. When the user requests prompt templates, show them the above list with details.\n');
      enhancedPrompt.write('2. When using prompt templates, ask for the required parameter values.\n');

      enhancedPrompt.write('\n\nAvailable prompt templates:\n');
      for (int i = 0; i < availablePrompts.length; i++) {
        final mcpPrompt = availablePrompts[i];
        enhancedPrompt.write('${i+1}. ${mcpPrompt['name']} - ${mcpPrompt['description']}\n');

        // Add prompt parameter information
        final args = mcpPrompt['arguments'] as List<dynamic>?;
        if (args != null && args.isNotEmpty) {
          enhancedPrompt.write('   Parameters:\n');
          for (final arg in args) {
            final argName = arg['name'] as String;
            final description = arg['description'] as String;
            final required = arg['required'] as bool? ?? false;
            enhancedPrompt.write('   - $argName: $description ${required ? "(Required)" : "(Optional)"}\n');
          }
        }
        enhancedPrompt.write('\n');
      }
    }

    // Include resource information
    final availableResources = await _collectAvailableResources(
      enableMcpResources: true,
    );

    if (includeSystemPrompt && availableResources.isNotEmpty) {
        enhancedPrompt.write('\nResource usage guidelines:\n');
        enhancedPrompt.write('1. When the user requests a resource list, show them the above resource list with details.\n');
        enhancedPrompt.write('2. When using resources, reference the resource name accurately.\n');

      enhancedPrompt.write('\n\nAvailable resources:\n');
      for (int i = 0; i < availableResources.length; i++) {
        final resource = availableResources[i];
        enhancedPrompt.write('${i+1}. ${resource['name']} - ${resource['description']}\n');

        // Add resource details
        if (resource['mimeType'] != null) {
          enhancedPrompt.write('   Type: ${resource['mimeType']}\n');
        }
        enhancedPrompt.write('\n');
      }
    }

    return enhancedPrompt.toString();
  }

  /// Collect available prompts from MCP clients and plugins
  Future<List<Map<String, dynamic>>> _collectAvailablePrompts({
    bool enableMcpPrompts = true,
    bool enablePlugins = true,
    String? mcpClientId, // Option to fetch prompts from a specific client
  }) async {
    final prompts = <Map<String, dynamic>>[];

    // Get prompts from MCP clients
    if (enableMcpPrompts && _mcpClientManager != null) {
      try {
        final mcpPrompts = await _mcpClientManager.getPrompts(mcpClientId);
        for (var prompt in mcpPrompts) {
          try {
            _logger.debug('Prompt information: ${jsonEncode(prompt)}');
          } catch (e) {
            _logger.warning('Failed to serialize prompt information: $e');
          }
        }
        prompts.addAll(mcpPrompts);
      } catch (e) {
        _logger.warning('Failed to get prompts from MCP clients: $e');
      }
    }

    // Get prompts from plugins (if implemented)
    if (enablePlugins) {
      try {
        final plugins = pluginManager.getAllPromptPlugins();
        for (final plugin in plugins) {
          final promptDef = plugin.getPromptDefinition();
          prompts.add({
            'name': promptDef.name,
            'description': promptDef.description,
            'arguments': promptDef.arguments,
          });
        }
      } catch (e) {
        _logger.warning('Failed to get prompts from plugins: $e');
      }
    }

    // Log prompt name list
    final promptNames = prompts.map((prompt) => prompt['name']).toList();
    _logger.info('Available prompt name list: $promptNames');

    return prompts;
  }

  /// Collect available resources from MCP clients
  Future<List<Map<String, dynamic>>> _collectAvailableResources({
    bool enableMcpResources = true,
    String? mcpClientId, // Option to fetch resources from a specific client
  }) async {
    final resources = <Map<String, dynamic>>[];

    // Get resources from MCP clients
    if (enableMcpResources && _mcpClientManager != null) {
      try {
        final mcpResources = await _mcpClientManager.getResources(mcpClientId);
        for (var resource in mcpResources) {
          try {
            _logger.debug('Resource information: ${jsonEncode(resource)}');
          } catch (e) {
            _logger.warning('Failed to serialize resource information: $e');
          }
        }
        resources.addAll(mcpResources);
      } catch (e) {
        _logger.warning('Failed to get resources from MCP clients: $e');
      }
    }

    // Log resource name list
    final resourceNames = resources.map((resource) => resource['name']).toList();
    _logger.info('Available resource name list: $resourceNames');

    return resources;
  }

  // Update system prompt with comprehensive information
  Future<void> updateSystemPrompt({
    String? basePrompt,
    bool includeSystemPrompt = true,
  }) async {
    final enhancedPrompt = await createEnhancedSystemPrompt(
      basePrompt: basePrompt,
      includeSystemPrompt: includeSystemPrompt,
    );
    setSystemPrompt(enhancedPrompt);
  }

  /// Send chat message and get response
  Future<LlmResponse> chat(String userInput, {
    bool enableTools = true,
    bool enablePlugins = true,
    Map<String, dynamic> parameters = const {},
    LlmContext? context,
    bool useRetrieval = false,
    bool enhanceSystemPrompt = true,
    bool noHistory = false,
  }) async {
    final requestId = _performanceMonitor.startRequest('chat');

    try {
      if (noHistory) {
        final systemMessages = chatSession.systemMessages;
        chatSession.clearHistory();

        for (final msg in systemMessages) {
          chatSession.addSystemMessage(msg.getTextContent());
        }
      }

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
      }

      // Create parameter copy
      Map<String, dynamic> effectiveParameters = Map<String, dynamic>.from(parameters);

      // If there are tool information and enhanceSystemPrompt is true,
      // temporarily update the system prompt
      if (availableTools.isNotEmpty) {
        // Add tool descriptions to the copied map
        final toolDescriptions = availableTools.map((tool) => {
          'name': tool['name'],
          'description': tool['description'],
          'parameters': tool['inputSchema'],
       }).toList();

        effectiveParameters['tools'] = toolDescriptions;

        // Handle system prompt
        final enhancedPrompt = await createEnhancedSystemPrompt(includeSystemPrompt: enhanceSystemPrompt);
        effectiveParameters['system'] = (effectiveParameters['system'] ?? '') + enhancedPrompt;
      }

      // Create LLM request
      final request = LlmRequest(
        prompt: userInput,
        history: chatSession.getMessagesForContext(),
        parameters: effectiveParameters,
        context: context,
      );

      // Send request to LLM
      LlmResponse response = await llmProvider.complete(request);

      // Add to chat session only if there's initial text
      if (response.text.isNotEmpty) {
        chatSession.addAssistantMessage(response.text);
      }

      // Store initial text
      final initialText = response.text;

      // Handle tool calls if any
      if (response.toolCalls != null && response.toolCalls!.isNotEmpty) {
        final toolResponse = await _handleToolCalls(
            response,
            userInput,
            enableTools,
            enablePlugins,
            parameters,
            context
        );

        // Add only the follow-up response to chat session
        if (toolResponse.text.isNotEmpty) {
          chatSession.addAssistantMessage(toolResponse.text);
        }

        // Include both initial text and follow-up response in the return value
        final combinedResponse = LlmResponse(
          text: initialText.isNotEmpty
              ? "$initialText\n\n${toolResponse.text}"
              : toolResponse.text,
          metadata: toolResponse.metadata,
          toolCalls: toolResponse.toolCalls,
        );

        _performanceMonitor.endRequest(requestId, success: true);
        return combinedResponse;
      }

      // Return original response if no tool calls
      _performanceMonitor.endRequest(requestId, success: true);
      return response;
    } catch (e, stackTrace) {
      // Error handling (same as existing code)
      String errorMessage;
      try {
        errorMessage = e.toString();
        _logger.error('Error in chat: $errorMessage');
        _logger.debug('Stack trace: $stackTrace');
      } catch (loggingError) {
        errorMessage = 'Error processing request (logging failed: $loggingError)';
      }

      final errorResponse = LlmResponse(
        text: 'Error: Unable to process your request. $errorMessage',
        metadata: {'error': errorMessage},
      );

      try {
        chatSession.addAssistantMessage(errorResponse.text);
      } catch (sessionError) {
        _logger.warning('Failed to add error message to session: $sessionError');
      }

      _performanceMonitor.endRequest(requestId, success: false);
      return errorResponse;
    }
  }

  /// Stream chat responses with tool support
  Stream<LlmResponseChunk> streamChat(String userInput, {
    bool enableTools = true,
    bool enablePlugins = true,
    Map<String, dynamic> parameters = const {},
    LlmContext? context,
    bool useRetrieval = false,
    bool enhanceSystemPrompt = true,
    bool noHistory = false,
  }) async* {
    final requestId = _performanceMonitor.startRequest('stream_chat');
    bool success = true;

    try {
      if (noHistory) {
        final systemMessages = chatSession.systemMessages;
        chatSession.clearHistory();

        for (final msg in systemMessages) {
          chatSession.addSystemMessage(msg.getTextContent());
        }
      }

      // Add user message to session
      chatSession.addUserMessage(userInput);

      // Handle retrieval-augmented generation if enabled and available
      if (useRetrieval && retrievalManager != null) {
        final ragResponse = await _handleRetrievalAugmentedResponse(
            userInput,
            parameters,
            context
        );

        // Add assistant message to session
        chatSession.addAssistantMessage(ragResponse.text);
      }

      // Collect available tools
      final availableTools = await _collectAvailableTools(
        enableMcpTools: enableTools,
        enablePlugins: enablePlugins,
      );

      // Create parameter copy
      Map<String, dynamic> effectiveParameters = Map<String, dynamic>.from(parameters);

      // If there are tool information and enhanceSystemPrompt is true,
      // temporarily update the system prompt
      if (availableTools.isNotEmpty) {
        // Add tool descriptions to the copied map
        final toolDescriptions = availableTools.map((tool) => {
          'name': tool['name'],
          'description': tool['description'],
          'parameters': tool['inputSchema'],
        }).toList();

        effectiveParameters['tools'] = toolDescriptions;

        // Handle system prompt
        final enhancedPrompt = await createEnhancedSystemPrompt(includeSystemPrompt: enhanceSystemPrompt);
        effectiveParameters['system'] = (effectiveParameters['system'] ?? '') + enhancedPrompt;
      }

      final request = LlmRequest(
        prompt: userInput,
        history: chatSession.getMessagesForContext(),
        parameters: effectiveParameters,
        context: context,
      );

      final responseBuffer = StringBuffer();
      LlmResponse? fullResponse;
      List<LlmToolCall>? collectedToolCalls;

      try {
        // Stream the initial response
        await for (final chunk in llmProvider.streamComplete(request)) {
          final standardizedMetadata = llmProvider.standardizeMetadata(chunk.metadata);
          final standardizedChunk = chunk.metadata == standardizedMetadata ?
          chunk :
          LlmResponseChunk(
              textChunk: chunk.textChunk,
              isDone: chunk.isDone,
              metadata: standardizedMetadata,
              toolCalls: chunk.toolCalls
          );

          yield standardizedChunk;
          responseBuffer.write(chunk.textChunk);

          // Keep track of any tool calls from the chunk
          if (chunk.toolCalls != null && chunk.toolCalls!.isNotEmpty) {
            collectedToolCalls ??= [];
            collectedToolCalls.addAll(chunk.toolCalls!);
          }

          final hasToolCallMetadata = llmProvider.hasToolCallMetadata(chunk.metadata);
          if (hasToolCallMetadata) {
            final extractedToolCall = llmProvider.extractToolCallFromMetadata(chunk.metadata);
            if (extractedToolCall != null) {
              collectedToolCalls ??= [];

              // Check if this tool call already exists by ID
              final toolCallExists = collectedToolCalls.any(
                      (tc) => tc.id == extractedToolCall.id);
              if (!toolCallExists) {
                collectedToolCalls.add(extractedToolCall);
              }
            }
          }

          // If the chunk indicates completion, we can create a full response
          if (chunk.isDone) {
            _logger.debug('Streaming complete, collected ${collectedToolCalls?.length ?? 0} tool calls');
            fullResponse = LlmResponse(
              text: responseBuffer.toString(),
              metadata: chunk.metadata,
              toolCalls: collectedToolCalls,
            );
          }
        }

        // If we didn't get a full response from the stream, create one
        fullResponse ??= LlmResponse(
          text: responseBuffer.toString(),
          metadata: {},
          toolCalls: collectedToolCalls,
        );

        // Add the initial response to chat session
        if (fullResponse.text.isNotEmpty) {
          chatSession.addAssistantMessage(fullResponse.text);
        }

        // Handle tool calls if any
        if (fullResponse.toolCalls != null && fullResponse.toolCalls!.isNotEmpty) {
          _logger.debug('Processing ${fullResponse.toolCalls!.length} tool calls from stream response');

          final validToolCalls = fullResponse.toolCalls!.where((tc) => tc.arguments.isNotEmpty).toList();

          if (validToolCalls.isEmpty) {
            _logger.warning('All tool calls had empty arguments - skipping tool execution');

            yield LlmResponseChunk(
              textChunk: "I tried to use tools to help answer your question, but couldn't complete the process. Could you please provide more specific information?",
              isDone: true,
              metadata: {'error': 'empty_tool_calls'},
            );

            chatSession.addAssistantMessage(
                "I tried to use tools to help answer your question, but couldn't complete the process. Could you please provide more specific information?"
            );

            return;
          }

          yield LlmResponseChunk(
            textChunk: "\n\n[Processing tool calls...]\n\n",
            isDone: false,
            metadata: {'processing_tools': true},
          );

          final validatedResponse = LlmResponse(
            text: fullResponse.text,
            metadata: fullResponse.metadata,
            toolCalls: validToolCalls,
          );

          try {
            // Handle tool calls with the validated list
            final toolResponse = await _handleToolCalls(
                validatedResponse,
                userInput,
                enableTools,
                enablePlugins,
                parameters,
                context
            );

            // Add the tool response to the chat session
            if (toolResponse.text.isNotEmpty) {
              chatSession.addAssistantMessage(toolResponse.text);
            }

            // Stream the tool response
            yield LlmResponseChunk(
              textChunk: toolResponse.text,
              isDone: true,
              metadata: toolResponse.metadata,
              toolCalls: toolResponse.toolCalls,
            );
          } catch (e) {
            _logger.error('Error processing tool calls: $e');

            final errorMessage = "Error processing tool calls: $e";

            yield LlmResponseChunk(
              textChunk: errorMessage,
              isDone: true,
              metadata: {'error': e.toString(), 'phase': 'tool_execution'},
            );

            chatSession.addAssistantMessage(errorMessage);
          }
        }
      } catch (e) {
        _logger.error('Error in streaming completion: $e');
        success = false;
        yield LlmResponseChunk(
          textChunk: 'Error during conversation: $e',
          isDone: true,
          metadata: {'error': e.toString()},
        );
      }
    } finally {
      _performanceMonitor.endRequest(requestId, success: success);
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
      LlmContext? context) async {
    // 도구 호출 검증 - 인자 없는 도구 호출 필터링
    final validToolCalls = <LlmToolCall>[];

    final Set<String> processedSignatures = {};

    for (final toolCall in response.toolCalls!) {
      // 인자가 비어있는 도구 호출은 건너뛰기
      if (toolCall.arguments.isEmpty) {
        _logger.warning('Skipping empty tool call for "${toolCall.name}" - no arguments provided');
        continue;
      }

      // 도구 호출 시그니처 생성 (도구 이름 + 인자 값들의 해시)
      final signature = '${toolCall.name}:${jsonEncode(toolCall.arguments)}';

      // 이미 처리한 동일 시그니처의 도�� 호출은 건너뛰기
      if (processedSignatures.contains(signature)) {
        _logger.warning('Skipping duplicate tool call for "${toolCall.name}" with identical arguments');
        continue;
      }

      // 시그니처 추가 및 유효한 도구 호출로 등록
      processedSignatures.add(signature);
      validToolCalls.add(toolCall);
      _logger.debug('Add tool call for ${toolCall.name}:${jsonEncode(toolCall.arguments)}');
    }

    // 유효한 도구 호출이 없으면 처리 중단
    if (validToolCalls.isEmpty) {
      // 모든 도구 호출이 비어있는 경우 오류 메시지 반환
      _logger.warning('All tool calls had empty arguments - skipping tool execution');
      return LlmResponse(
        text: "I tried to use tools to help answer your question, but couldn't complete the process. Could you please provide more specific information?",
        metadata: {'error': 'empty_tool_calls'},
      );
    }

    // Tool call result map (ID -> result)
    final Map<String, dynamic> toolResults = {};
    final Map<String, String> toolErrors = {};

    // Execute all valid tools
    for (final toolCall in validToolCalls) {
      final toolId = toolCall.id ?? 'call_${DateTime.now().millisecondsSinceEpoch}';

      try {
        // Execute tool
        final toolResult = await executeTool(
          toolCall.name,
          toolCall.arguments,
          enableMcpTools: enableTools,
          enablePlugins: enablePlugins,
        );

        // Save to result map
        toolResults[toolId] = toolResult;

        // Add tool result to session
        chatSession.addToolResult(
          toolCall.name,
          toolCall.arguments,
          [toolResult],
          toolCallId: toolId,  // Pass ID
        );
        _logger.debug('toolResult ${toolResult}');
      } catch (e) {
        _logger.error('Error executing tool ${toolCall.name}: $e');

        // Save to error map
        toolErrors[toolId] = e.toString();

        // Add tool error to session
        chatSession.addToolError(
          toolCall.name,
          e.toString(),
          toolCallId: toolId,  // Pass ID
        );
      }
    }

    // Return error response if there are errors
    if (toolResults.isEmpty && toolErrors.isNotEmpty) {
      // Use the first error message
      final firstErrorEntry = toolErrors.entries.first;
      return LlmResponse(
        text: "I tried to use a tool, but encountered an error: ${firstErrorEntry.value}",
        metadata: {'error': firstErrorEntry.value, 'tool_call_id': firstErrorEntry.key},
      );
    }

    // If there are tool results, create a follow-up request
    if (toolResults.isNotEmpty) {
      // Create message with tool result information
      final toolResultsInfo = toolResults.entries.map((entry) =>
      "Tool result for call ${entry.key}: ${entry.value}").join("\n");

      // Create follow-up request
      final followUpRequest = LlmRequest(
        prompt: "Based on the tool results, answer the original question: \"$userInput\"\n\nTool results:\n$toolResultsInfo",
        history: chatSession.getMessagesForContext(),
        parameters: parameters,
        context: context,
      );

      // Get follow-up response
      try {
        response = await llmProvider.complete(followUpRequest);
      } catch (e) {
        _logger.error('Error getting follow-up response: $e');
        return LlmResponse(
          text: "I tried to use tools to answer your question, but encountered an error processing the results: $e",
          metadata: {'error': e.toString()},
        );
      }
    }

    return response;
  }

  /// Collect available tools from MCP clients and plugins
  Future<List<Map<String, dynamic>>> _collectAvailableTools({
    bool enableMcpTools = true,
    bool enablePlugins = true,
    String? mcpClientId, // Option to fetch tools from a specific client
  }) async {
    final tools = <Map<String, dynamic>>[];

    // Get tools from MCP clients
    if(enableMcpTools) _logger.error('enableMcpTools');
    if(_mcpClientManager != null) _logger.error('_mcpClientManager');
    if (enableMcpTools && _mcpClientManager != null) {
      try {
        final mcpTools = await _mcpClientManager.getTools(mcpClientId);
        for (var tool in mcpTools) {
          try {
            // Improved logging for clearer tool information display
            _logger.debug('Tool information: ${jsonEncode(tool)}');
          } catch (e) {
            _logger.warning('Failed to serialize tool information: $e');
          }
        }
        tools.addAll(mcpTools);
      } catch (e) {
        _logger.warning('Failed to get tools from MCP clients: $e');
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

    // Log tool name list
    final toolNames = tools.map((tool) => tool['name']).toList();
    _logger.info('Available tool name list: $toolNames');

    return tools;
  }

  /// Method to select the most suitable client
  Future<String?> _selectBestClientForTool(
      String toolName,
      Map<String, dynamic> args
      ) async {
    final clientIds = _mcpClientManager!.clientIds;

    // Step 1: Find clients with matching tool name
    final clientsWithMatchingTool = <String, Map<String, dynamic>>{};

    for (final clientId in clientIds) {
      try {
        final tools = await _mcpClientManager.getTools(clientId);

        for (final tool in tools) {
          if (tool['name'] == toolName) {
            clientsWithMatchingTool[clientId] = tool;
            break; // Found matching tool, move to next client
          }
        }
      } catch (e) {
        _logger.warning('Error checking tools for client $clientId: $e');
      }
    }

    // If no clients support the tool
    if (clientsWithMatchingTool.isEmpty) {
      return null;
    }

    // If exactly one client supports the tool, return it
    if (clientsWithMatchingTool.length == 1) {
      return clientsWithMatchingTool.keys.first;
    }

    // Step 2: Compare schema match scores for multiple clients
    final scores = <String, int>{};

    for (final entry in clientsWithMatchingTool.entries) {
      final clientId = entry.key;
      final tool = entry.value;

      // Base score
      int score = 1;

      // Schema check
      final inputSchema = tool['inputSchema'] as Map<String, dynamic>?;
      if (inputSchema != null) {
        final properties = inputSchema['properties'] as Map<String, dynamic>?;
        final required = inputSchema['required'] as List<dynamic>?;

        if (properties != null) {
          // Check if provided arguments match schema
          for (final argName in args.keys) {
            if (properties.containsKey(argName)) {
              score += 2; // Argument name matches

              // Type check
              final propDetails = properties[argName] as Map<String, dynamic>?;
              if (propDetails != null && propDetails.containsKey('type')) {
                final argType = propDetails['type'];
                final argValue = args[argName];

                bool typeMatches = _checkTypeMatch(argValue, argType);
                if (typeMatches) {
                  score += 1; // Type matches
                }
              }
            }
          }
        }

        // Check if all required arguments are provided
        if (required != null) {
          final allRequiredProvided = required.every((req) => args.containsKey(req));
          if (allRequiredProvided) {
            score += 5; // All required arguments provided
          }
        }
      }

      scores[clientId] = score;
    }

    // Return the client with the highest score
    if (scores.isNotEmpty) {
      return scores.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;
    }

    // Default to the first matching client
    return clientsWithMatchingTool.keys.first;
  }

  // Helper method to check type matching
  bool _checkTypeMatch(dynamic value, dynamic expectedType) {
    if (expectedType is String) {
      switch (expectedType) {
        case 'string': return value is String;
        case 'number': return value is num;
        case 'integer': return value is int;
        case 'boolean': return value is bool;
        case 'object': return value is Map;
        case 'array': return value is List;
      }
    }
    return false;
  }

  /// Execute tool using MCP clients or plugins
  Future<dynamic> executeTool(String toolName, Map<String, dynamic> args, {
    bool enableMcpTools = true,
    bool enablePlugins = true,
    String? mcpClientId,
    bool tryAllMcpClients = true,
  }) async {
    // Try MCP clients
    if (enableMcpTools && _mcpClientManager != null) {
      try {
        // If client ID is not specified, select the most suitable client
        String? effectiveClientId = mcpClientId;
        if (effectiveClientId == null && !tryAllMcpClients) {
          effectiveClientId = await _selectBestClientForTool(
              toolName,
              args
          );
        }

        final result = await _mcpClientManager.executeTool(
          toolName,
          args,
          clientId: effectiveClientId,
          tryAllClients: tryAllMcpClients,
        );

        if (result != null && !(result is Map && result.containsKey('error'))) {
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

  /// Execute specific tool on a specific MCP client
  Future<dynamic> executeToolWithSpecificClient(
      String toolName,
      Map<String, dynamic> args,
      String clientId) async {
    if (_mcpClientManager == null) {
      throw StateError('MCP client manager is not initialized');
    }

    return await _mcpClientManager.executeTool(
        toolName,
        args,
        clientId: clientId,
        tryAllClients: false
    );
  }

  /// Execute specific tool on all MCP clients and collect results
  Future<Map<String, dynamic>> executeToolOnAllMcpClients(
      String toolName,
      Map<String, dynamic> args) async {
    if (_mcpClientManager == null) {
      throw StateError('MCP client manager is not initialized');
    }

    return await _mcpClientManager.executeToolOnAllClients(toolName, args);
  }

  /// Find all MCP clients that have a specific tool
  Future<List<String>> findMcpClientsWithTool(String toolName) async {
    if (_mcpClientManager == null) {
      return [];
    }

    return await _mcpClientManager.findClientsWithTool(toolName);
  }

  /// Set default MCP client ID to use when calling tools
  void setDefaultToolClient(String clientId) {
    if (_mcpClientManager == null) {
      throw StateError('MCP client manager is not initialized');
    }
    _mcpClientManager.setDefaultClient(clientId);
  }

  /// Get tools organized by client
  Future<Map<String, List<Map<String, dynamic>>>> getToolsByClient() async {
    if (_mcpClientManager == null) {
      return {};
    }

    return await _mcpClientManager.getToolsByClient();
  }


  /// Execute a prompt using MCP clients
  Future<Map<String, dynamic>> executePrompt(
      String promptName,
      Map<String, dynamic> args, {
        String? clientId,
        bool tryAllClients = false,
      }) async {
    if (_mcpClientManager == null) {
      throw StateError('MCP client manager is not initialized');
    }

    return await _mcpClientManager.executePrompt(
        promptName,
        args,
        clientId: clientId,
        tryAllClients: tryAllClients
    );
  }

  /// Read a resource using MCP clients
  Future<Map<String, dynamic>> readResource(
      String resourceUri, {
        String? clientId,
        bool tryAllClients = false,
      }) async {
    if (_mcpClientManager == null) {
      throw StateError('MCP client manager is not initialized');
    }

    return await _mcpClientManager.readResource(
        resourceUri,
        clientId: clientId,
        tryAllClients: tryAllClients
    );
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

