// lib/src/core/llm_server.dart
import '../../mcp_llm.dart';
import 'llm_interface.dart';
import '../adapter/llm_server_adapter.dart';
import '../utils/logger.dart';

/// Server for providing LLM capabilities
class LlmServer {
  /// LLM provider
  final LlmInterface llmProvider;

  /// MCP server adapter
  final LlmServerAdapter? _serverAdapter;

  /// Raw MCP server instance
  final dynamic _mcpServer;

  /// Logger instance
  final Logger _logger = Logger.getLogger('mcp_llm.server');

  /// Create a new LLM server
  LlmServer({
    required this.llmProvider,
    dynamic mcpServer, StorageManager? storageManager, RetrievalManager? retrievalManager, required PluginManager pluginManager,
  }) : _mcpServer = mcpServer,
        _serverAdapter = mcpServer != null ? LlmServerAdapter(mcpServer) : null;

  /// Check if MCP server is available
  bool get hasMcpServer => _mcpServer != null && _serverAdapter != null;

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
      return await _serverAdapter!.registerTool(
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
    } catch (e) {
      _logger.error('Failed to register completion tool: $e');
      return false;
    }
  }

  /// Register LLM streaming tool
  Future<bool> _registerStreamingTool() async {
    try {
      return await _serverAdapter!.registerTool(
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
    } catch (e) {
      _logger.error('Failed to register streaming tool: $e');
      return false;
    }
  }

  /// Register LLM embedding tool
  Future<bool> _registerEmbeddingTool() async {
    try {
      return await _serverAdapter!.registerTool(
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
    } catch (e) {
      _logger.error('Failed to register embedding tool: $e');
      return false;
    }
  }

  /// Handle LLM completion tool calls
  Future<Map<String, dynamic>> _handleLlmCompleteTool(Map<String, dynamic> args) async {
    try {
      final prompt = args['prompt'] as String;
      final parameters = args['parameters'] as Map<String, dynamic>? ?? {};

      _logger.debug('Handling LLM completion: $prompt');

      // Create request
      final request = LlmRequest(
        prompt: prompt,
        parameters: parameters,
      );

      // Get completion
      final response = await llmProvider.complete(request);

      return {
        'content': response.text,
        'metadata': response.metadata,
      };
    } catch (e) {
      _logger.error('Error in LLM completion: $e');
      return {'error': e.toString()};
    }
  }

  /// Handle LLM streaming tool calls
  Future<Stream<Map<String, dynamic>>> _handleLlmStreamingTool(Map<String, dynamic> args) async {
    try {
      final prompt = args['prompt'] as String;
      final parameters = args['parameters'] as Map<String, dynamic>? ?? {};

      _logger.debug('Handling LLM streaming: $prompt');

      // Create request
      final request = LlmRequest(
        prompt: prompt,
        parameters: parameters,
      );

      // Get streaming response
      final responseStream = llmProvider.streamComplete(request);

      // Convert to map stream
      return responseStream.map((chunk) => {
        'content': chunk.textChunk,
        'isDone': chunk.isDone,
        'metadata': chunk.metadata,
      });
    } catch (e) {
      _logger.error('Error in LLM streaming: $e');
      return Stream.value({'error': e.toString()});
    }
  }

  /// Handle LLM embedding tool calls
  Future<Map<String, dynamic>> _handleLlmEmbeddingTool(Map<String, dynamic> args) async {
    try {
      final text = args['text'] as String;

      _logger.debug('Handling LLM embedding generation');

      // Get embeddings
      final embeddings = await llmProvider.getEmbeddings(text);

      return {
        'embeddings': embeddings,
        'dimension': embeddings.length,
      };
    } catch (e) {
      _logger.error('Error in LLM embedding: $e');
      return {'error': e.toString()};
    }
  }

  /// Close and release resources
  Future<void> close() async {
    await llmProvider.close();
  }
}