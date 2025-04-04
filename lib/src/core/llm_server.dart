import '../../mcp_llm.dart';
import '../adapter/llm_server_adapter.dart';

/// Server for providing LLM capabilities
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
        _performanceMonitor = performanceMonitor ?? PerformanceMonitor();

  /// Check if MCP server is available
  bool get hasMcpServer => _mcpServer != null && _serverAdapter != null;

  /// Check if retrieval capabilities are available
  bool get hasRetrievalCapabilities => retrievalManager != null;

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
            'parameters': {'type': 'object', 'description': 'Optional parameters'}
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
            'parameters': {'type': 'object', 'description': 'Optional parameters'}
          },
          'required': ['prompt']
        },
        handler: _handleLlmStreamingTool,
        isStreaming: true,
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
  Future<Map<String, dynamic>> _handleLlmCompleteTool(Map<String, dynamic> args) async {
    try {
      final prompt = args['prompt'] as String;
      final parameters = args['parameters'] as Map<String, dynamic>? ?? {};

      final requestId = _performanceMonitor.startRequest('completion_tool');

      _logger.debug('Handling LLM completion: $prompt');

      // Create request
      final request = LlmRequest(
        prompt: prompt,
        parameters: parameters,
      );

      // Get completion
      final response = await llmProvider.complete(request);

      _performanceMonitor.endRequest(requestId, success: true);

      return {
        'content': response.text,
        'metadata': response.metadata,
      };
    } catch (e) {
      _logger.error('Error in LLM completion: $e');
      _performanceMonitor.recordToolCall('llm-complete', success: false);
      return {'error': e.toString()};
    }
  }

  /// Handle LLM streaming tool calls
  Future<Stream<Map<String, dynamic>>> _handleLlmStreamingTool(Map<String, dynamic> args) async {
    try {
      final prompt = args['prompt'] as String;
      final parameters = args['parameters'] as Map<String, dynamic>? ?? {};

      _logger.debug('Handling LLM streaming: $prompt');
      final requestId = _performanceMonitor.startRequest('streaming_tool');

      // Create request
      final request = LlmRequest(
        prompt: prompt,
        parameters: parameters,
      );

      // Get streaming response
      final responseStream = llmProvider.streamComplete(request);

      // Convert to map stream with success tracking at the end
      return responseStream.map((chunk) {
        if (chunk.isDone) {
          _performanceMonitor.endRequest(requestId, success: true);
        }

        return {
          'content': chunk.textChunk,
          'isDone': chunk.isDone,
          'metadata': chunk.metadata,
        };
      });
    } catch (e) {
      _logger.error('Error in LLM streaming: $e');
      _performanceMonitor.recordToolCall('llm-stream', success: false);
      return Stream.value({'error': e.toString()});
    }
  }

  /// Handle LLM embedding tool calls
  Future<Map<String, dynamic>> _handleLlmEmbeddingTool(Map<String, dynamic> args) async {
    try {
      final text = args['text'] as String;
      final requestId = _performanceMonitor.startRequest('embedding_tool');

      _logger.debug('Handling LLM embedding generation');

      // Get embeddings
      final embeddings = await llmProvider.getEmbeddings(text);
      _performanceMonitor.endRequest(requestId, success: true);

      return {
        'embeddings': embeddings,
        'dimension': embeddings.length,
      };
    } catch (e) {
      _logger.error('Error in LLM embedding: $e');
      _performanceMonitor.recordToolCall('llm-embed', success: false);
      return {'error': e.toString()};
    }
  }

  /// Handle document retrieval tool calls
  Future<Map<String, dynamic>> _handleDocumentRetrievalTool(Map<String, dynamic> args) async {
    if (retrievalManager == null) {
      return {'error': 'Retrieval manager not configured'};
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
        'id': doc.id,
        'title': doc.title,
        'content': doc.content,
        'metadata': doc.metadata,
      }).toList();

      return {
        'documents': results,
        'count': docs.length,
      };
    } catch (e) {
      _logger.error('Error in document retrieval: $e');
      _performanceMonitor.recordToolCall('llm-retrieve', success: false);
      return {'error': e.toString()};
    }
  }

  /// Handle RAG tool calls
  Future<Map<String, dynamic>> _handleRagTool(Map<String, dynamic> args) async {
    if (retrievalManager == null) {
      return {'error': 'Retrieval manager not configured'};
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

      return {
        'response': response,
        'metadata': {
          'topK': topK,
          'namespace': namespace,
        },
      };
    } catch (e) {
      _logger.error('Error in RAG generation: $e');
      _performanceMonitor.recordToolCall('llm-rag', success: false);
      return {'error': e.toString()};
    }
  }

  /// Close and release resources
  Future<void> close() async {
    await llmProvider.close();

    // Close the retrieval manager if present
    if (retrievalManager != null) {
      await retrievalManager!.close();
    }
  }
}