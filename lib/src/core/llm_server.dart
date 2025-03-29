import '../core/llm_interface.dart';
import '../core/models.dart';
import '../plugins/plugin_manager.dart';
import '../rag/retriever.dart';
import '../storage/storage_manager.dart';
import '../utils/logger.dart';

/// Server for providing LLM capabilities to MCP clients
class LlmServer {
  /// LLM provider
  final LlmInterface llmProvider;

  /// MCP server (type-agnostic to avoid direct dependency)
  final dynamic mcpServer;

  /// Storage manager
  final StorageManager? storageManager;

  /// Retrieval manager for RAG
  final RetrievalManager? retrievalManager;

  /// Plugin manager
  final PluginManager? pluginManager;

  /// Logger
  final Logger _logger = Logger.getLogger('mcp_llm.server');

  /// Create a new LLM server
  LlmServer({
    required this.llmProvider,
    this.mcpServer,
    this.storageManager,
    this.retrievalManager,
    this.pluginManager,
  });

  /// Register LLM capabilities as tools with the MCP server
  Future<void> registerLlmTools() async {
    if (mcpServer == null) {
      _logger.warning('Cannot register LLM tools: MCP server is null');
      return;
    }

    try {
      // Check if the MCP server has an addTool method
      if (!_hasAddToolMethod(mcpServer)) {
        _logger.error('MCP server does not support adding tools');
        return;
      }

      // Register completion tool
      await _registerCompletionTool();

      // Register streaming completion tool
      await _registerStreamingTool();

      // Register embedding tool
      await _registerEmbeddingTool();

      // Register RAG tool if retrieval manager is available
      if (retrievalManager != null) {
        await _registerRagTool();
      }

      _logger.info('Registered LLM tools with MCP server');
    } catch (e) {
      _logger.error('Error registering LLM tools: $e');
    }
  }

  /// Check if the MCP server has an addTool method
  bool _hasAddToolMethod(dynamic server) {
    try {
      // Use reflection to check if the object has an 'addTool' method
      return server != null &&
          server is Object &&
          server.runtimeType.toString().contains('McpServer') &&
          server.toString().contains('addTool');
    } catch (_) {
      return false;
    }
  }

  /// Register LLM completion tool
  Future<void> _registerCompletionTool() async {
    try {
      await mcpServer.addTool(
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

      _logger.debug('Registered LLM completion tool');
    } catch (e) {
      _logger.error('Failed to register LLM completion tool: $e');
    }
  }

  /// Register LLM streaming completion tool
  Future<void> _registerStreamingTool() async {
    try {
      await mcpServer.addTool(
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
        handler: _handleLlmStreamTool,
        isStreaming: true,
      );

      _logger.debug('Registered LLM streaming tool');
    } catch (e) {
      _logger.error('Failed to register LLM streaming tool: $e');
    }
  }

  /// Register LLM embedding tool
  Future<void> _registerEmbeddingTool() async {
    try {
      await mcpServer.addTool(
        name: 'llm-embed',
        description: 'Generate embeddings for text using the LLM',
        inputSchema: {
          'type': 'object',
          'properties': {
            'text': {'type': 'string', 'description': 'The text to embed'},
          },
          'required': ['text']
        },
        handler: _handleLlmEmbedTool,
      );

      _logger.debug('Registered LLM embedding tool');
    } catch (e) {
      _logger.error('Failed to register LLM embedding tool: $e');
    }
  }

  /// Register RAG tool
  Future<void> _registerRagTool() async {
    try {
      await mcpServer.addTool(
        name: 'llm-rag',
        description: 'Retrieve and generate using the LLM',
        inputSchema: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'The query for retrieval'},
            'topK': {'type': 'integer', 'description': 'Number of documents to retrieve', 'default': 5},
            'parameters': {'type': 'object', 'description': 'Optional parameters'}
          },
          'required': ['query']
        },
        handler: _handleLlmRagTool,
      );

      _logger.debug('Registered LLM RAG tool');
    } catch (e) {
      _logger.error('Failed to register LLM RAG tool: $e');
    }
  }

  /// Handle LLM completion tool
  Future<dynamic> _handleLlmCompleteTool(Map<String, dynamic> arguments) async {
    try {
      final prompt = arguments['prompt'] as String;
      final parameters = arguments['parameters'] as Map<String, dynamic>? ?? {};

      _logger.debug('Handling LLM completion tool: $prompt');

      // Create the LLM request
      final request = LlmRequest(
        prompt: prompt,
        parameters: parameters,
      );

      // Get the completion
      final response = await llmProvider.complete(request);

      _logger.debug('LLM completion tool completed');

      // Return the text as content
      return CallToolResult([
        TextContent(text: response.text),
      ]);
    } catch (e) {
      _logger.error('Error handling LLM completion tool: $e');

      return CallToolResult(
        [TextContent(text: 'Error: $e')],
        isError: true,
      );
    }
  }

  /// Handle LLM streaming tool
  Future<dynamic> _handleLlmStreamTool(Map<String, dynamic> arguments) async {
    try {
      final prompt = arguments['prompt'] as String;
      final parameters = arguments['parameters'] as Map<String, dynamic>? ?? {};

      _logger.debug('Handling LLM streaming tool: $prompt');

      // Create the LLM request
      final request = LlmRequest(
        prompt: prompt,
        parameters: parameters,
      );

      // Get the streaming completion
      final responseStream = llmProvider.streamComplete(request);

      _logger.debug('LLM streaming tool started');

      // Return the stream
      return responseStream.map((chunk) {
        return CallToolResult(
          [TextContent(text: chunk.textChunk)],
          isStreaming: !chunk.isDone,
        );
      });
    } catch (e) {
      _logger.error('Error handling LLM streaming tool: $e');

      return Stream.value(CallToolResult(
        [TextContent(text: 'Error: $e')],
        isError: true,
      ));
    }
  }

  /// Handle LLM embedding tool
  Future<dynamic> _handleLlmEmbedTool(Map<String, dynamic> arguments) async {
    try {
      final text = arguments['text'] as String;

      _logger.debug('Handling LLM embedding tool: ${text.substring(0, min(20, text.length))}...');

      // Get the embeddings
      final embeddings = await llmProvider.getEmbeddings(text);

      _logger.debug('LLM embedding tool completed');

      // Return the embeddings as content
      return CallToolResult([
        TextContent(text: 'Embedding vector of length ${embeddings.length}'),
      ]);
    } catch (e) {
      _logger.error('Error handling LLM embedding tool: $e');

      return CallToolResult(
        [TextContent(text: 'Error: $e')],
        isError: true,
      );
    }
  }

  /// Handle LLM RAG tool
  Future<dynamic> _handleLlmRagTool(Map<String, dynamic> arguments) async {
    try {
      final query = arguments['query'] as String;
      final topK = arguments['topK'] as int? ?? 5;
      final parameters = arguments['parameters'] as Map<String, dynamic>? ?? {};

      _logger.debug('Handling LLM RAG tool: $query');

      if (retrievalManager == null) {
        throw StateError('RetrievalManager is not available');
      }

      // Get the RAG response
      final response = await retrievalManager.retrieveAndGenerate(
        query,
        topK: topK,
        generationParams: parameters,
      );

      _logger.debug('LLM RAG tool completed');

      // Return the response as content
      return CallToolResult([
        TextContent(text: response),
      ]);
    } catch (e) {
      _logger.error('Error handling LLM RAG tool: $e');

      return CallToolResult(
        [TextContent(text: 'Error: $e')],
        isError: true,
      );
    }
  }

  /// Close the server and release resources
  Future<void> close() async {
    _logger.info('Shutting down LLM server');

    try {
      await llmProvider.close();
    } catch (e) {
      _logger.error('Error closing LLM provider: $e');
    }
  }
}

// Helper function for min (avoiding dart:math dependency)
int min(int a, int b) => a < b ? a : b;