import 'dart:convert';

import '../../mcp_llm.dart';

/// Collection of core LLM feature plugins
/// These plugins provide the standard LLM functionality as tools
/// that can be registered with the MCP server
final Logger _logger = Logger('mcp_llm.core_llm_plugin');

/// Plugin for basic LLM text completion
class LlmCompletionPlugin extends BaseToolPlugin {
  final LlmInterface llmProvider;
  final PerformanceMonitor _performanceMonitor;
  /// Logger instance

  LlmCompletionPlugin({
    required this.llmProvider,
    PerformanceMonitor? performanceMonitor,
  }) : _performanceMonitor = performanceMonitor ?? PerformanceMonitor(),
        super(
        name: 'llm-complete',
        version: '1.0.0',
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
      );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> args) async {
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

      // Return as LlmCallToolResult
      return LlmCallToolResult([LlmTextContent(text: response.text)]);
    } catch (e) {
      _logger.error('Error in LLM completion: $e');
      _performanceMonitor.recordToolCall('llm-complete', success: false);
      return LlmCallToolResult(
          [LlmTextContent(text: 'Error: ${e.toString()}')],
          isError: true
      );
    }
  }
}

/// Plugin for streaming LLM text completion
class LlmStreamingPlugin extends BaseToolPlugin {
  final LlmInterface llmProvider;
  final PerformanceMonitor _performanceMonitor;

  LlmStreamingPlugin({
    required this.llmProvider,
    PerformanceMonitor? performanceMonitor,
  }) : _performanceMonitor = performanceMonitor ?? PerformanceMonitor(),
        super(
        name: 'llm-stream',
        version: '1.0.0',
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
      );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> args) async {
    final requestId = _performanceMonitor.startRequest('streaming_tool');

    try {
      final prompt = args['prompt'] as String;
      final parameters = args['parameters'] as Map<String, dynamic>? ?? {};
      final systemPrompt = args['systemPrompt'] as String?;

      _logger.debug('Handling LLM streaming: $prompt');

      // Create request
      final request = LlmRequest(
        prompt: prompt,
        parameters: parameters,
      );

      // Add system prompt if provided
      if (systemPrompt != null) {
        request.parameters['system'] = systemPrompt;
      }

      // Record successful tool call
      _performanceMonitor.endRequest(requestId, success: true);
      _performanceMonitor.recordToolCall('llm-stream', success: true);

      // Return streaming content
      return LlmCallToolResult(
        [LlmTextContent(text: 'Streaming started...')],
        isStreaming: true,
      );
    } catch (e) {
      _logger.error('Error in LLM streaming: $e');
      _performanceMonitor.endRequest(requestId, success: false);
      _performanceMonitor.recordToolCall('llm-stream', success: false);
      return LlmCallToolResult(
        [LlmTextContent(text: 'Error: ${e.toString()}')],
        isError: true,
      );
    }
  }
}

/// Plugin for generating embeddings
class LlmEmbeddingPlugin extends BaseToolPlugin {
  final LlmInterface llmProvider;
  final PerformanceMonitor _performanceMonitor;

  LlmEmbeddingPlugin({
    required this.llmProvider,
    PerformanceMonitor? performanceMonitor,
  }) : _performanceMonitor = performanceMonitor ?? PerformanceMonitor(),
        super(
        name: 'llm-embed',
        version: '1.0.0',
        description: 'Generate embeddings for text using the LLM',
        inputSchema: {
          'type': 'object',
          'properties': {
            'text': {'type': 'string', 'description': 'The text to embed'},
          },
          'required': ['text']
        },
      );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> args) async {
    try {
      final text = args['text'] as String;
      final requestId = _performanceMonitor.startRequest('embedding_tool');

      _logger.debug('Handling LLM embedding generation');

      // Get embeddings
      final embeddings = await llmProvider.getEmbeddings(text);
      _performanceMonitor.endRequest(requestId, success: true);
      _performanceMonitor.recordToolCall('llm-embed', success: true);

      // Return embeddings
      return LlmCallToolResult([
        LlmTextContent(text: jsonEncode({
          'embeddings': embeddings,
          'dimension': embeddings.length,
        }))
      ]);
    } catch (e) {
      _logger.error('Error in LLM embedding: $e');
      _performanceMonitor.recordToolCall('llm-embed', success: false);
      return LlmCallToolResult(
        [LlmTextContent(text: 'Error: ${e.toString()}')],
        isError: true,
      );
    }
  }
}

/// Plugin for document retrieval
class LlmRetrievalPlugin extends BaseToolPlugin {
  final RetrievalManager retrievalManager;
  final PerformanceMonitor _performanceMonitor;

  LlmRetrievalPlugin({
    required this.retrievalManager,
    PerformanceMonitor? performanceMonitor,
  }) : _performanceMonitor = performanceMonitor ?? PerformanceMonitor(),
        super(
        name: 'llm-retrieve',
        version: '1.0.0',
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
      );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> args) async {
    try {
      final query = args['query'] as String;
      final topK = args['topK'] as int? ?? 5;
      final namespace = args['namespace'] as String?;
      final filters = args['filters'] as Map<String, dynamic>? ?? {};

      final requestId = _performanceMonitor.startRequest('retrieval_tool');

      // Retrieve documents
      final docs = await retrievalManager.retrieveRelevant(
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

      // Return results
      return LlmCallToolResult([
        LlmTextContent(text: jsonEncode({
          'documents': results,
          'count': docs.length,
        }))
      ]);
    } catch (e) {
      _logger.error('Error in document retrieval: $e');
      _performanceMonitor.recordToolCall('llm-retrieve', success: false);
      return LlmCallToolResult(
        [LlmTextContent(text: 'Error: ${e.toString()}')],
        isError: true,
      );
    }
  }
}

/// Plugin for Retrieval Augmented Generation (RAG)
class LlmRagPlugin extends BaseToolPlugin {
  final RetrievalManager retrievalManager;
  final PerformanceMonitor _performanceMonitor;

  LlmRagPlugin({
    required this.retrievalManager,
    PerformanceMonitor? performanceMonitor,
  }) : _performanceMonitor = performanceMonitor ?? PerformanceMonitor(),
        super(
        name: 'llm-rag',
        version: '1.0.0',
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
      );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> args) async {
    try {
      final query = args['query'] as String;
      final topK = args['topK'] as int? ?? 5;
      final namespace = args['namespace'] as String?;
      final parameters = args['parameters'] as Map<String, dynamic>? ?? {};

      final requestId = _performanceMonitor.startRequest('rag_tool');

      // Generate RAG response
      final response = await retrievalManager.retrieveAndGenerate(
        query,
        topK: topK,
        namespace: namespace,
        generationParams: parameters,
      );

      _performanceMonitor.endRequest(requestId, success: true);

      // Return response
      return LlmCallToolResult([
        LlmTextContent(text: response)
      ]);
    } catch (e) {
      _logger.error('Error in RAG generation: $e');
      _performanceMonitor.recordToolCall('llm-rag', success: false);
      return LlmCallToolResult(
        [LlmTextContent(text: 'Error: ${e.toString()}')],
        isError: true,
      );
    }
  }
}

/// Factory to create all core LLM feature plugins
class CoreLlmPluginFactory {
  /// Create all core LLM plugins
  static List<LlmPlugin> createCorePlugins({
    required LlmInterface llmProvider,
    RetrievalManager? retrievalManager,
    PerformanceMonitor? performanceMonitor,
    bool includeCompletionPlugin = true,
    bool includeStreamingPlugin = true,
    bool includeEmbeddingPlugin = true,
    bool includeRetrievalPlugins = true,
  }) {
    final effectiveMonitor = performanceMonitor ?? PerformanceMonitor();
    final plugins = <LlmPlugin>[];

    // Basic LLM features
    if (includeCompletionPlugin) {
      plugins.add(LlmCompletionPlugin(
        llmProvider: llmProvider,
        performanceMonitor: effectiveMonitor,
      ));
    }

    if (includeStreamingPlugin) {
      plugins.add(LlmStreamingPlugin(
        llmProvider: llmProvider,
        performanceMonitor: effectiveMonitor,
      ));
    }

    if (includeEmbeddingPlugin) {
      plugins.add(LlmEmbeddingPlugin(
        llmProvider: llmProvider,
        performanceMonitor: effectiveMonitor,
      ));
    }

    // Retrieval features
    if (includeRetrievalPlugins && retrievalManager != null) {
      plugins.add(LlmRetrievalPlugin(
        retrievalManager: retrievalManager,
        performanceMonitor: effectiveMonitor,
      ));

      plugins.add(LlmRagPlugin(
        retrievalManager: retrievalManager,
        performanceMonitor: effectiveMonitor,
      ));
    }

    return plugins;
  }

  /// Register all core LLM plugins with a plugin manager
  static Future<void> registerWithManager({
    required PluginManager pluginManager,
    required LlmInterface llmProvider,
    RetrievalManager? retrievalManager,
    PerformanceMonitor? performanceMonitor,
    bool includeCompletionPlugin = true,
    bool includeStreamingPlugin = true,
    bool includeEmbeddingPlugin = true,
    bool includeRetrievalPlugins = true,
  }) async {
    final plugins = createCorePlugins(
      llmProvider: llmProvider,
      retrievalManager: retrievalManager,
      performanceMonitor: performanceMonitor,
      includeCompletionPlugin: includeCompletionPlugin,
      includeStreamingPlugin: includeStreamingPlugin,
      includeEmbeddingPlugin: includeEmbeddingPlugin,
      includeRetrievalPlugins: includeRetrievalPlugins,
    );

    for (final plugin in plugins) {
      await pluginManager.registerPlugin(plugin);
    }
  }
}