import '../../mcp_llm.dart';
import '../adapter/llm_server_adapter.dart';
import 'dart:convert';
import 'dart:io';

/// Server for providing LLM capabilities
/// Enhanced with local tool registration, direct LLM interaction,
/// and dynamic capability generation
class LlmServer {
  /// LLM provider
  final LlmInterface llmProvider;

  /// MCP server adapter
  final LlmServerAdapter? _serverAdapter;

  /// Raw MCP server instance
  final dynamic _mcpServer;

  /// Storage manager
  final StorageManager? storageManager;

  /// Retrieval manager
  final RetrievalManager? retrievalManager;

  /// Plugin manager
  final PluginManager pluginManager;

  /// Performance monitor
  final PerformanceMonitor _performanceMonitor;

  /// Logger instance
  final Logger _logger = Logger.getLogger('mcp_llm.llm_server');

  /// Registered local tools (name -> handler function)
  final Map<String, Function> _localTools = {};

  /// Chat sessions for different contexts
  final Map<String, ChatSession> _chatSessions = {};

  /// Create a new LLM server
  LlmServer({
    required this.llmProvider,
    dynamic mcpServer,
    this.storageManager,
    this.retrievalManager,
    required this.pluginManager,
    PerformanceMonitor? performanceMonitor,
  }) : _mcpServer = mcpServer,
        _serverAdapter = mcpServer != null ? LlmServerAdapter(mcpServer) : null,
        _performanceMonitor = performanceMonitor ?? PerformanceMonitor() {
    // Initialize default chat session
    _chatSessions['default'] = ChatSession(
      llmProvider: llmProvider,
      storageManager: storageManager,
      id: 'default',
    );
  }

  LlmServerAdapter? get serverAdapter => _serverAdapter;

  /// Check if MCP server is available
  bool get hasMcpServer => _mcpServer != null && _serverAdapter != null;

  /// Check if retrieval capabilities are available
  bool get hasRetrievalCapabilities => retrievalManager != null;

  /// Get or create a chat session for a specific context
  ChatSession _getChatSession(String sessionId) {
    if (!_chatSessions.containsKey(sessionId)) {
      _chatSessions[sessionId] = ChatSession(
        llmProvider: llmProvider,
        storageManager: storageManager,
        id: sessionId,
      );
    }
    return _chatSessions[sessionId]!;
  }

  /// Register LLM capabilities as tools
  Future<bool> registerLlmTools() async {
    if (!hasMcpServer) {
      _logger.warning('Cannot register LLM tools: MCP server is not available');
      return false;
    }

    try {
      bool success = true;

      // Register completion tool
      success = success && await _registerCompletionTool();

      // Register streaming tool
      success = success && await _registerStreamingTool();

      // Register embedding tool
      success = success && await _registerEmbeddingTool();

      // Register retrieval tools if retrieval manager is available
      if (hasRetrievalCapabilities) {
        success = success && await _registerRetrievalTools();
      }

      if (success) {
        _logger.info('Successfully registered LLM tools with MCP server');
      } else {
        _logger.warning('Some tools failed to register');
      }

      return success;
    } catch (e) {
      _logger.error('Error registering LLM tools: $e');
      return false;
    }
  }

  /// Register LLM completion tool
  Future<bool> _registerCompletionTool() async {
    try {
      final requestId = _performanceMonitor.startRequest('completion_tool_registration');

      final result = await _serverAdapter!.registerTool(
        name: 'llm-complete',
        description: 'Generate text completion using the LLM',
        inputSchema: {
          'type': 'object',
          'properties': {
            'prompt': {'type': 'string', 'description': 'The prompt to complete'},
            'parameters': {'type': 'object', 'description': 'Optional parameters'},
            'systemPrompt': {'type': 'string', 'description': 'Optional system prompt'},
          },
          'required': ['prompt']
        },
        handler: _handleLlmCompleteTool,
      );

      _performanceMonitor.endRequest(requestId, success: result);
      return result;
    } catch (e) {
      _logger.error('Failed to register completion tool: $e');
      return false;
    }
  }

  /// Register LLM streaming tool
  Future<bool> _registerStreamingTool() async {
    try {
      final requestId = _performanceMonitor.startRequest('streaming_tool_registration');

      final result = await _serverAdapter!.registerTool(
        name: 'llm-stream',
        description: 'Generate streaming text completion using the LLM',
        inputSchema: {
          'type': 'object',
          'properties': {
            'prompt': {'type': 'string', 'description': 'The prompt to complete'},
            'parameters': {'type': 'object', 'description': 'Optional parameters'},
            'systemPrompt': {'type': 'string', 'description': 'Optional system prompt'},
          },
          'required': ['prompt']
        },
        handler: _handleLlmStreamingTool,
      );

      _performanceMonitor.endRequest(requestId, success: result);
      return result;
    } catch (e) {
      _logger.error('Failed to register streaming tool: $e');
      return false;
    }
  }

  /// Register LLM embedding tool
  Future<bool> _registerEmbeddingTool() async {
    try {
      final requestId = _performanceMonitor.startRequest('embedding_tool_registration');

      final result = await _serverAdapter!.registerTool(
        name: 'llm-embed',
        description: 'Generate embeddings for text using the LLM',
        inputSchema: {
          'type': 'object',
          'properties': {
            'text': {'type': 'string', 'description': 'The text to embed'},
          },
          'required': ['text']
        },
        handler: _handleLlmEmbeddingTool,
      );

      _performanceMonitor.endRequest(requestId, success: result);
      return result;
    } catch (e) {
      _logger.error('Failed to register embedding tool: $e');
      return false;
    }
  }

  /// Register retrieval-related tools
  Future<bool> _registerRetrievalTools() async {
    try {
      bool success = true;

      // Register document retrieval tool
      success = success && await _serverAdapter!.registerTool(
        name: 'llm-retrieve',
        description: 'Retrieve relevant documents for a query',
        inputSchema: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'The query to search for'},
            'topK': {'type': 'integer', 'description': 'Number of documents to return'},
            'namespace': {'type': 'string', 'description': 'Optional namespace/collection'},
            'filters': {'type': 'object', 'description': 'Optional filters'},
          },
          'required': ['query']
        },
        handler: _handleDocumentRetrievalTool,
      );

      // Register RAG tool
      success = success && await _serverAdapter.registerTool(
        name: 'llm-rag',
        description: 'Retrieve documents and generate a response',
        inputSchema: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'The query to answer'},
            'topK': {'type': 'integer', 'description': 'Number of documents to use'},
            'namespace': {'type': 'string', 'description': 'Optional namespace/collection'},
            'parameters': {'type': 'object', 'description': 'Generation parameters'},
          },
          'required': ['query']
        },
        handler: _handleRagTool,
      );

      return success;
    } catch (e) {
      _logger.error('Failed to register retrieval tools: $e');
      return false;
    }
  }

  /// Handle LLM completion tool calls
  Future<LlmCallToolResult> _handleLlmCompleteTool(Map<String, dynamic> args) async {
    try {
      final prompt = args['prompt'] as String;
      final parameters = args['parameters'] as Map<String, dynamic>? ?? {};
      final systemPrompt = args['systemPrompt'] as String?;

      final requestId = _performanceMonitor.startRequest('completion_tool');
      _logger.debug('Handling LLM completion: $prompt');

      // Create request
      final request = LlmRequest(
        prompt: prompt,
        parameters: parameters,
      );

      // Add system prompt if provided
      if (systemPrompt != null) {
        request.parameters['system'] = systemPrompt;
      }

      // Get completion
      final response = await llmProvider.complete(request);
      _performanceMonitor.endRequest(requestId, success: true);
      _performanceMonitor.recordToolCall('llm-complete', success: true);

      // 응답 내용을 LlmTextContent로 변환하여 반환
      return LlmCallToolResult([LlmTextContent(text: response.text)]);
    } catch (e) {
      _logger.error('Error in LLM completion: $e');
      _performanceMonitor.recordToolCall('llm-complete', success: false);
      return LlmCallToolResult([LlmTextContent(text: 'Error: ${e.toString()}')], isError: true);
    }
  }

  /// Handle LLM streaming tool calls
  Future<LlmCallToolResult> _handleLlmStreamingTool(Map<String, dynamic> args) async {
    try {
      final prompt = args['prompt'] as String;
      final parameters = args['parameters'] as Map<String, dynamic>? ?? {};
      final systemPrompt = args['systemPrompt'] as String?;

      _logger.debug('Handling LLM streaming: $prompt');
      final requestId = _performanceMonitor.startRequest('streaming_tool');

      // Create request
      final request = LlmRequest(
        prompt: prompt,
        parameters: parameters,
      );

      // Add system prompt if provided
      if (systemPrompt != null) {
        request.parameters['system'] = systemPrompt;
      }

      // Get streaming response
      final responseStream = llmProvider.streamComplete(request);

      // 스트리밍 컨텐츠 생성
      final contents = [LlmTextContent(text: 'Streaming started...')];

      // 스트리밍 결과를 담은 LlmCallToolResult 반환
      return LlmCallToolResult(contents, isStreaming: true);
    } catch (e) {
      _logger.error('Error in LLM streaming: $e');
      _performanceMonitor.recordToolCall('llm-stream', success: false);
      return LlmCallToolResult([LlmTextContent(text: 'Error: ${e.toString()}')], isError: true);
    }
  }

  /// Handle LLM embedding tool calls
  Future<LlmCallToolResult> _handleLlmEmbeddingTool(Map<String, dynamic> args) async {
    try {
      final text = args['text'] as String;
      final requestId = _performanceMonitor.startRequest('embedding_tool');

      _logger.debug('Handling LLM embedding generation');

      // Get embeddings
      final embeddings = await llmProvider.getEmbeddings(text);
      _performanceMonitor.endRequest(requestId, success: true);
      _performanceMonitor.recordToolCall('llm-embed', success: true);

      // 임베딩 결과를 문자열로 변환하여 반환
      return LlmCallToolResult([LlmTextContent(text: embeddings.toString())]);
    } catch (e) {
      _logger.error('Error in LLM embedding: $e');
      _performanceMonitor.recordToolCall('llm-embed', success: false);
      return LlmCallToolResult([LlmTextContent(text: 'Error: ${e.toString()}')], isError: true);
    }
  }

  /// Handle document retrieval tool calls
  Future<LlmCallToolResult> _handleDocumentRetrievalTool(Map<String, dynamic> args) async {
    if (retrievalManager == null) {
      return LlmCallToolResult([LlmTextContent(text: 'Retrieval manager not configured')], isError: true);
    }

    try {
      final query = args['query'] as String;
      final topK = args['topK'] as int? ?? 5;
      final namespace = args['namespace'] as String?;
      final filters = args['filters'] as Map<String, dynamic>? ?? {};

      final requestId = _performanceMonitor.startRequest('retrieval_tool');

      // Retrieve documents
      final docs = await retrievalManager!.retrieveRelevant(
        query,
        topK: topK,
        namespace: namespace,
        filters: filters,
      );

      _performanceMonitor.endRequest(requestId, success: true);

      // Format results
      final results = docs.map((doc) => {
        'uri': doc.id,
        'content': doc.content,
        'metadata': doc.metadata,
      }).toList();

      // 검색 결과를 문자열로 변환하여 반환
      return LlmCallToolResult([LlmTextContent(text: results.toString())]);
    } catch (e) {
      _logger.error('Error in document retrieval: $e');
      _performanceMonitor.recordToolCall('llm-retrieve', success: false);
      return LlmCallToolResult([LlmTextContent(text: 'Error: ${e.toString()}')], isError: true);
    }
  }

  /// Handle RAG tool calls
  Future<LlmCallToolResult> _handleRagTool(Map<String, dynamic> args) async {
    if (retrievalManager == null) {
      return LlmCallToolResult([LlmTextContent(text: 'Retrieval manager not configured')], isError: true);
    }

    try {
      final query = args['query'] as String;
      final topK = args['topK'] as int? ?? 5;
      final namespace = args['namespace'] as String?;
      final parameters = args['parameters'] as Map<String, dynamic>? ?? {};

      final requestId = _performanceMonitor.startRequest('rag_tool');

      // Generate RAG response
      final response = await retrievalManager!.retrieveAndGenerate(
        query,
        topK: topK,
        namespace: namespace,
        generationParams: parameters,
      );

      _performanceMonitor.endRequest(requestId, success: true);

      // RAG 결과를 반환
      return LlmCallToolResult([LlmTextContent(text: response)]);
    } catch (e) {
      _logger.error('Error in RAG generation: $e');
      _performanceMonitor.recordToolCall('llm-rag', success: false);
      return LlmCallToolResult([LlmTextContent(text: 'Error: ${e.toString()}')], isError: true);
    }
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
      final chatSession = _getChatSession(sessionId);

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
  Future<bool> registerLocalTool({
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema,
    required ToolHandler handler,
    bool registerWithServer = true,
  }) async {
    try {
      // Store locally
      _localTools[name] = handler;
      _logger.info('Registered local tool: $name');

      // Register with server if requested and available
      if (registerWithServer && hasMcpServer) {
        final result = await _serverAdapter!.registerTool(
          name: name,
          description: description,
          inputSchema: inputSchema,
          handler: handler,
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
    if (!_localTools.containsKey(name)) {
      throw Exception('Local tool not found: $name');
    }

    try {
      _logger.debug('Executing local tool: $name');
      return await _localTools[name]!(args);
    } catch (e) {
      _logger.error('Error executing local tool: $e');
      throw Exception('Failed to execute local tool "$name": $e');
    }
  }

  /// Generate and register a tool based on LLM's design
  ///
  /// [description] - Natural language description of the tool to create
  /// [registerWithServer] - Whether to register the tool with MCP server
  /// [sessionId] - Optional session ID for maintaining conversation context
  Future<bool> generateAndRegisterTool(String description, {
    bool registerWithServer = true,
    String sessionId = 'default',
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
        // Extract JSON from response if needed (in case LLM adds explanatory text)
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

      // Create handler function that delegates to LLM
      handler(Map<String, dynamic> args) async {
        // Create a prompt for processing the tool request
        final handlerPrompt = '''
        You are executing the "$toolName" tool with these parameters:
        ${jsonEncode(args)}
        
        Processing logic:
        $processingLogic
        
        Respond with only the result in valid JSON format. Do not include any explanations or extra text.
        ''';

        // Execute through LLM
        final handlerResponse = await askLlm(handlerPrompt, sessionId: '${sessionId}_$toolName');

        try {
          // Parse response - allow for both JSON object and plain text response
          String result = handlerResponse.text.trim();
          return LlmCallToolResult([LlmTextContent(text: result)]);
        } catch (e) {
          _logger.error('Error parsing tool response: $e');
          return LlmCallToolResult(
              [LlmTextContent(text: 'Error: ${e.toString()}')],
              isError: true
          );
        }
      }

      // Register the tool
      return await registerLocalTool(
        name: toolName,
        description: toolDescription,
        inputSchema: inputSchema,
        handler: handler,
        registerWithServer: registerWithServer,
      );
    } catch (e) {
      _logger.error('Error generating and registering tool: $e');
      return false;
    }
  }

  /// Generate and register a prompt template based on LLM's design
  ///
  /// [description] - Natural language description of the prompt to create
  /// [registerWithServer] - Whether to register the prompt with MCP server
  /// [sessionId] - Optional session ID for maintaining conversation context
  Future<bool> generateAndRegisterPrompt(String description, {
    bool registerWithServer = true,
    String sessionId = 'default',
  }) async {
    if (!hasMcpServer) {
      _logger.warning('Cannot register prompt: MCP server is not available');
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
        // Extract JSON from response if needed
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

      // Create handler function that matches PromptHandler type
      handler(Map<String, dynamic> args) async {
        try {
          // Replace placeholders in template
          String filledPrompt = userPromptTemplate;

          // Replace each {parameter} with its value
          args.forEach((key, value) {
            filledPrompt = filledPrompt.replaceAll('{$key}', value.toString());
          });

          // Create messages array for the prompt
          final messages = [
            LlmMessage(role: 'system', content: systemPrompt),
            LlmMessage(role: 'user', content: filledPrompt),
          ];

          return LlmGetPromptResult(
            description: promptDescription,
            messages: messages,
          );
        } catch (e) {
          _logger.error('Error processing prompt template: $e');
          return LlmGetPromptResult(
            description: 'Error',
            messages: [LlmMessage(role: 'system', content: 'Failed to process prompt template: $e')],
          );
        }
      }

      // Convert arguments to expected format
      final formattedArgs = arguments.map((arg) {
        return {
          'name': arg['name'],
          'description': arg['description'],
          'required': arg['required'] ?? false,
        };
      }).toList();

      // Register with server
      if (registerWithServer && hasMcpServer) {
        final result = await _serverAdapter!.registerPrompt(
          name: promptName,
          description: promptDescription,
          arguments: formattedArgs,
          handler: handler,
        );

        if (result) {
          _logger.info('Successfully registered prompt: $promptName');
        } else {
          _logger.warning('Failed to register prompt with server: $promptName');
        }

        return result;
      }

      return false;
    } catch (e) {
      _logger.error('Error generating and registering prompt: $e');
      return false;
    }
  }

  /// Generate and register a resource based on LLM's design
  ///
  /// [description] - Natural language description of the resource to create
  /// [registerWithServer] - Whether to register the resource with MCP server
  /// [sessionId] - Optional session ID for maintaining conversation context
  Future<bool> generateAndRegisterResource(String description, {
    bool registerWithServer = true,
    String sessionId = 'default',
  }) async {
    if (!hasMcpServer) {
      _logger.warning('Cannot register resource: MCP server is not available');
      return false;
    }

    try {
      // Prompt for the LLM to design a resource
      final designPrompt = '''
      You are a resource designer for an AI system. Please create a resource definition based on this description:
      "$description"
      
      Respond in JSON format only with the following structure:
      {
        "name": "Resource Name",
        "description": "A clear description of the resource",
        "uri": "resource://unique_identifier",
        "mimeType": "text/plain or application/json etc.",
        "contentTemplate": "Template or example of the resource content"
      }
      ''';

      // Get resource definition from LLM
      final response = await askLlm(designPrompt, sessionId: sessionId);

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
      final mimeType = resourceDefinition['mimeType'] as String;
      final contentTemplate = resourceDefinition['contentTemplate'] as String;

      // Create handler function
      handler(String uri, Map<String, dynamic>? params) async {
        try {
          // Generate dynamic content if parameters provided
          String content = contentTemplate;

          if (params != null && params.isNotEmpty) {
            // Prompt LLM to generate resource content based on parameters
            final contentPrompt = '''
            Generate content for the resource "$resourceName" with these parameters:
            ${jsonEncode(params)}
            
            Base template:
            $contentTemplate
            
            Return only the generated content, formatted appropriately for MIME type: $mimeType
            ''';

            final contentResponse = await askLlm(contentPrompt, sessionId: '${sessionId}_resource');
            content = contentResponse.text;
          }

          // Format response based on mime type
          final contents = [
            LlmTextContent(text: content)
          ];

          return LlmReadResourceResult(
            content: content,
            mimeType: mimeType,
            contents: contents,
          );
        } catch (e) {
          _logger.error('Error generating resource content: $e');
          return LlmReadResourceResult(
            content: 'Error: ${e.toString()}',
            mimeType: 'text/plain',
            contents: [LlmTextContent(text: 'Error: ${e.toString()}')],
          );
        }
      }

      // Register with server
      if (registerWithServer && hasMcpServer) {
        final result = await _serverAdapter!.registerResource(
          uri: resourceUri,
          name: resourceName,
          description: resourceDescription,
          mimeType: mimeType,
          handler: handler,
        );

        if (result) {
          _logger.info('Successfully registered resource: $resourceName ($resourceUri)');
        } else {
          _logger.warning('Failed to register resource with server: $resourceUri');
        }

        return result;
      }

      return false;
    } catch (e) {
      _logger.error('Error generating and registering resource: $e');
      return false;
    }
  }

  /// Register capabilities (tools, prompts, resources) from a description file
  ///
  /// [filePath] - Path to the description file
  Future<bool> registerCapabilitiesFromFile(String filePath) async {
    if (!hasMcpServer) {
      _logger.warning('Cannot register capabilities: MCP server is not available');
      return false;
    }

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
        for (final tool in tools) {
          if (tool is Map<String, dynamic>) {
            final name = tool['name'] as String?;
            final description = tool['description'] as String?;
            final inputSchema = tool['inputSchema'] as Map<String, dynamic>?;
            final handlerCode = tool['handler'] as String?;

            if (name != null && description != null && inputSchema != null && handlerCode != null) {
              totalCount++;
              // 핸들러 함수를 적절한 ToolHandler 타입으로 변환
              handler(Map<String, dynamic> args) async {
                // 핸들러 로직
                return LlmCallToolResult([LlmTextContent(text: 'Handled by $name')]);
              }

              final success = await _serverAdapter!.registerTool(
                name: name,
                description: description,
                inputSchema: inputSchema,
                handler: handler,
              );

              if (success) successCount++;
            }
          }
        }
      }

      // Process prompts
      if (data.containsKey('prompts') && data['prompts'] is List) {
        final prompts = data['prompts'] as List;
        for (final promptDesc in prompts) {
          totalCount++;
          final success = await generateAndRegisterPrompt(promptDesc.toString());
          if (success) successCount++;
        }
      }

      // Process resources
      if (data.containsKey('resources') && data['resources'] is List) {
        final resources = data['resources'] as List;
        for (final resourceDesc in resources) {
          totalCount++;
          final success = await generateAndRegisterResource(resourceDesc.toString());
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
  /// [parameters] - Optional parameters for the LLM request
  /// [sessionId] - Optional session ID for maintaining conversation context
  /// [systemPrompt] - Optional system prompt to use
  /// [sendToolResultsToLlm] - Whether to send tool results back to LLM or return directly
  Future<Map<String, dynamic>> processQuery({
    required String query,
    bool useLocalTools = true,
    Map<String, dynamic> parameters = const {},
    String sessionId = 'default',
    String? systemPrompt,
    bool sendToolResultsToLlm = true,
  }) async {
    final chatSession = _getChatSession(sessionId);
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

      // Get available local tools if needed
      Map<String, dynamic> effectiveParameters = Map<String, dynamic>.from(parameters);
      if (useLocalTools && _localTools.isNotEmpty) {
        final toolDescriptions = <Map<String, dynamic>>[];

        // Get registered tools from server if available
        if (hasMcpServer) {
          try {
            final serverTools = await _serverAdapter!.listTools();
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
        for (final name in _localTools.keys) {
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
      if (useLocalTools && response.toolCalls != null && response.toolCalls!.isNotEmpty) {
        final toolCalls = response.toolCalls!;
        final toolResults = <String, dynamic>{};
        final toolErrors = <String, String>{};

        // Execute all tools
        for (final toolCall in toolCalls) {
          final toolId = toolCall.id ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
          final toolName = toolCall.name;

          try {
            // Try server tool first
            if (hasMcpServer) {
              try {
                final result = await _serverAdapter!.executeTool(toolName, toolCall.arguments);
                toolResults[toolId] = result;
                continue;
              } catch (e) {
                _logger.debug('Server tool execution failed, trying local: $e');
                // Continue to local tool execution
              }
            }

            // Try local tool
            if (_localTools.containsKey(toolName)) {
              final result = await executeLocalTool(toolName, toolCall.arguments);
              toolResults[toolId] = result;
            } else {
              throw Exception('Tool not found: $toolName');
            }
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
  /// [parameters] - Optional parameters for the LLM request
  /// [sessionId] - Optional session ID for maintaining conversation context
  /// [systemPrompt] - Optional system prompt to use
  Stream<Map<String, dynamic>> streamProcessQuery({
    required String query,
    bool useLocalTools = true,
    Map<String, dynamic> parameters = const {},
    String sessionId = 'default',
    String? systemPrompt,
  }) async* {
    final chatSession = _getChatSession(sessionId);

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

      // Get available local tools if needed
      Map<String, dynamic> effectiveParameters = Map<String, dynamic>.from(parameters);
      if (useLocalTools && _localTools.isNotEmpty) {
        final toolDescriptions = <Map<String, dynamic>>[];

        // Get registered tools from server if available
        if (hasMcpServer) {
          try {
            final serverTools = await _serverAdapter!.listTools();
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
        for (final name in _localTools.keys) {
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

  /// Close and release resources
  Future<void> close() async {
    // No need to manually save chat sessions - they save automatically when messages are added
    _logger.debug('Closing ${_chatSessions.length} chat sessions');

    // Close LLM provider
    await llmProvider.close();

    // Close the retrieval manager if present
    if (retrievalManager != null) {
      await retrievalManager!.close();
    }
  }
}