import 'dart:async';
import '../../mcp_llm.dart';
import 'managed_service.dart';

/// Adapter that makes LlmClient conform to ManagedService interface
class LlmClientServiceAdapter implements ManagedService {
  final LlmClient _client;
  final String _id;
  final Logger _logger = Logger('mcp_llm.llm_client_adapter');

  /// Create a new LlmClient adapter
  LlmClientServiceAdapter(this._client, this._id);

  /// Get the wrapped client
  LlmClient get client => _client;

  @override
  String get id => _id;

  @override
  bool isAvailable() {
    // A simple check - could be enhanced with more sophisticated health check
    return true;
  }

  @override
  Future<bool> connect() async {
    // LlmClient doesn't have explicit connect method
    // Could implement reconnection logic if needed
    return true;
  }

  @override
  Future<bool> disconnect() async {
    try {
      await _client.close();
      return true;
    } catch (e) {
      _logger.error('Error disconnecting client: $e');
      return false;
    }
  }

  @override
  Map<String, dynamic> getStatus() {
    // Basic status information
    return {
      'available': isAvailable(),
      'hasMcpClientManager': _client.hasMcpClientManager,
      'hasRetrievalCapabilities': _client.hasRetrievalCapabilities,
    };
  }

  @override
  Future<dynamic> executeCapability(String capabilityName, Map<String, dynamic> parameters) async {
    switch (capabilityName) {
      case 'chat':
        return await _client.chat(
          parameters['prompt'] as String,
          enableTools: parameters['enableTools'] as bool? ?? true,
          parameters: parameters['parameters'] as Map<String, dynamic>? ?? const {},
          context: parameters['context'] as LlmContext?,
          useRetrieval: parameters['useRetrieval'] as bool? ?? false,
          enhanceSystemPrompt: parameters['enhanceSystemPrompt'] as bool? ?? true,
          noHistory: parameters['noHistory'] as bool? ?? false,
        );

      case 'streamChat':
        return _client.streamChat(
          parameters['prompt'] as String,
          enableTools: parameters['enableTools'] as bool? ?? true,
          parameters: parameters['parameters'] as Map<String, dynamic>? ?? const {},
          context: parameters['context'] as LlmContext?,
          useRetrieval: parameters['useRetrieval'] as bool? ?? false,
          enhanceSystemPrompt: parameters['enhanceSystemPrompt'] as bool? ?? true,
          noHistory: parameters['noHistory'] as bool? ?? false,
        );

      case 'executeTool':
        return await _client.executeTool(
          parameters['toolName'] as String,
          parameters['args'] as Map<String, dynamic>,
          enableMcpTools: parameters['enableMcpTools'] as bool? ?? true,
          enablePlugins: parameters['enablePlugins'] as bool? ?? true,
          mcpClientId: parameters['mcpClientId'] as String?,
          tryAllMcpClients: parameters['tryAllMcpClients'] as bool? ?? true,
        );

      default:
        throw UnsupportedError('Capability not supported: $capabilityName');
    }
  }

  @override
  Future<bool> hasCapability(String capabilityName) async {
    final capabilities = await getCapabilities();
    return capabilities.contains(capabilityName);
  }

  @override
  Future<List<String>> getCapabilities() async {
    return ['chat', 'streamChat', 'executeTool'];
  }

  @override
  Map<String, dynamic> getMetadata() {
    return {
      'type': 'LlmClient',
      'hasRetrievalCapabilities': _client.hasRetrievalCapabilities,
      'mcpClientIds': _client.hasMcpClientManager ? _client.getMcpClientIds() : [],
    };
  }
}

/// Adapter that makes LlmServer conform to ManagedService interface
class LlmServerServiceAdapter implements ManagedService {
  final LlmServer _server;
  final String _id;
  final Logger _logger = Logger('mcp_llm.llm_server_adapter');

  /// Create a new LlmServer adapter
  LlmServerServiceAdapter(this._server, this._id);

  /// Get the wrapped server
  LlmServer get server => _server;

  @override
  String get id => _id;

  @override
  bool isAvailable() {
    // A simple check
    return true;
  }

  @override
  Future<bool> connect() async {
    // LlmServer doesn't have explicit connect method
    return true;
  }

  @override
  Future<bool> disconnect() async {
    try {
      await _server.close();
      return true;
    } catch (e) {
      _logger.error('Error disconnecting server: $e');
      return false;
    }
  }

  @override
  Map<String, dynamic> getStatus() {
    return {
      'available': isAvailable(),
      'hasMcpServer': _server.hasMcpServer,
      'hasRetrievalCapabilities': _server.hasRetrievalCapabilities,
      'toolCount': _server.localTools.length,
    };
  }

  @override
  Future<dynamic> executeCapability(String capabilityName, Map<String, dynamic> parameters) async {
    switch (capabilityName) {
      case 'processQuery':
        return await _server.processQuery(
          query: parameters['query'] as String,
          useLocalTools: parameters['useLocalTools'] as bool? ?? true,
          usePluginTools: parameters['usePluginTools'] as bool? ?? true,
          parameters: parameters['parameters'] as Map<String, dynamic>? ?? const {},
          sessionId: parameters['sessionId'] as String? ?? 'default',
          systemPrompt: parameters['systemPrompt'] as String?,
          sendToolResultsToLlm: parameters['sendToolResultsToLlm'] as bool? ?? true,
          serverId: parameters['serverId'] as String?,
        );

      case 'streamProcessQuery':
        return _server.streamProcessQuery(
          query: parameters['query'] as String,
          useLocalTools: parameters['useLocalTools'] as bool? ?? true,
          usePluginTools: parameters['usePluginTools'] as bool? ?? true,
          parameters: parameters['parameters'] as Map<String, dynamic>? ?? const {},
          sessionId: parameters['sessionId'] as String? ?? 'default',
          systemPrompt: parameters['systemPrompt'] as String?,
          serverId: parameters['serverId'] as String?,
        );

      case 'executeTool':
        return await _server.executeLocalTool(
          parameters['toolName'] as String,
          parameters['args'] as Map<String, dynamic>,
        );

      default:
        throw UnsupportedError('Capability not supported: $capabilityName');
    }
  }

  @override
  Future<bool> hasCapability(String capabilityName) async {
    final capabilities = await getCapabilities();
    return capabilities.contains(capabilityName);
  }

  @override
  Future<List<String>> getCapabilities() async {
    return ['processQuery', 'streamProcessQuery', 'executeTool'];
  }

  @override
  Map<String, dynamic> getMetadata() {
    return {
      'type': 'LlmServer',
      'hasRetrievalCapabilities': _server.hasRetrievalCapabilities,
      'hasMcpServer': _server.hasMcpServer,
      'serverIds': _server.hasMcpServer ? _server.getMcpServerIds() : [],
    };
  }
}