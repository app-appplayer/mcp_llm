/// Main library for integrating Large Language Models with MCP
library;

// Multi-MCP Integration
export 'src/adapter/mcp_client_manager.dart';
export 'src/adapter/mcp_server_manager.dart';
export 'src/adapter/llm_client_adapter.dart';
export 'src/adapter/mcp_auth_adapter.dart';

// 2025-03-26 MCP Enhancements
export 'src/batch/batch_request_manager.dart';
export 'src/health/health_monitor.dart';
export 'src/capabilities/capability_manager.dart';
export 'src/lifecycle/lifecycle_manager.dart';
export 'src/error/enhanced_error_handler.dart';

// Core components
export 'src/core/llm_interface.dart';
export 'src/core/llm_client.dart';
export 'src/core/llm_server.dart';
export 'src/core/llm_context.dart';
export 'src/core/llm_registry.dart';
export 'src/core/models.dart';
export 'src/core/llm_server_extensions.dart';

// Provider implementations
export 'src/providers/provider.dart';
export 'src/providers/claude_provider.dart';
export 'src/providers/openai_provider.dart';
export 'src/providers/together_provider.dart';
export 'src/providers/custom_provider.dart';

// Multi llm support
export 'src/multi_llm/llm_client_manager.dart';
export 'src/multi_llm/llm_server_manager.dart';
export 'src/multi_llm/default_service_router.dart';
export 'src/multi_llm/generic_service_pool.dart';
export 'src/multi_llm/default_service_balancer.dart';

// Chat modules
export 'src/chat/chat_session.dart';
export 'src/chat/message.dart';
export 'src/chat/history.dart';
export 'src/chat/conversation.dart';

// Plugin system
export 'src/plugins/plugin_manager.dart';
export 'src/plugins/plugin_interface.dart';
export 'src/plugins/tool_plugin.dart';
export 'src/plugins/prompt_plugin.dart';
export 'src/plugins/core_llm_plugins.dart';

// Parallel processing
export 'src/parallel/executor.dart';
export 'src/parallel/task_scheduler.dart';
export 'src/parallel/result_aggregator.dart';
export 'src/parallel/advanced_task_scheduler.dart';

// Storage
export 'src/storage/storage_manager.dart';
export 'src/storage/memory_storage.dart';
export 'src/storage/persistent_storage.dart';

// RAG
export 'src/rag/retrieval_manager.dart';
export 'src/rag/embeddings.dart';
export 'src/rag/document_store.dart';
export 'src/rag/vector_store.dart';
export 'src/rag/vector_stores/pinecone_vector_store.dart';
export 'src/rag/vector_stores/weaviate_vector_store.dart';
export 'src/rag/vector_stores/real_vector_stores.dart';

// Utilities
export 'src/utils/logger.dart';
export 'src/utils/token_counter.dart';
export 'src/utils/error_handler.dart';
export 'src/utils/performance_monitor.dart';

import 'src/core/llm_registry.dart';
import 'src/core/llm_client.dart';
import 'src/core/llm_server.dart';
import 'src/core/llm_interface.dart';
import 'src/core/models.dart';
import 'src/multi_llm/llm_client_manager.dart';
import 'src/multi_llm/llm_server_manager.dart';
import 'src/parallel/executor.dart';
import 'src/parallel/result_aggregator.dart';
import 'src/plugins/plugin_manager.dart';
import 'src/plugins/plugin_interface.dart';
import 'src/providers/provider.dart';
import 'src/rag/retrieval_manager.dart';
import 'src/rag/document_store.dart';
import 'src/rag/vector_store.dart';
import 'src/storage/storage_manager.dart';
import 'src/utils/performance_monitor.dart';
import 'src/utils/logger.dart';

typedef MCPLlm = McpLlm;
/// Main class for MCPLlm functionality
class McpLlm {
  /// LLM provider registry
  final LlmRegistry _llmRegistry = LlmRegistry();

  /// Multi llm client manager
  final MultiLlmClientManager _llmClientManager = MultiLlmClientManager();

  /// Multi llm server manager
  final MultiLlmServerManager _llmServerManager = MultiLlmServerManager();

  /// Plugin manager
  final PluginManager _pluginManager = PluginManager();

  /// Performance monitor
  final PerformanceMonitor _performanceMonitor = PerformanceMonitor();

  /// Logger instance
  final Logger _logger = Logger('mcp_llm.mcpllm');

  /// Create a new MCPLlm instance
  McpLlm() {
    // Initialize any necessary components
  }

  /// Register a new LLM provider
  void registerProvider(String name, LlmProviderFactory factory) {
    _llmRegistry.registerProvider(name, factory);
  }

  /// Create a new LLM client
  ///
  /// [providerName] - Name of the registered provider to use
  /// [config] - Configuration for the LLM provider
  /// [mcpClient] - Optional MCP client (from mcp_client package)
  /// [mcpClients] - Optional map of MCP clients (for multi-mcp_client support)
  /// [storageManager] - Optional storage manager for persistence
  /// [pluginManager] - Optional plugin manager or uses internal one if not provided
  /// [performanceMonitor] - Optional performance monitor
  /// [retrievalManager] - Optional retrieval manager for RAG capabilities
  /// [clientId] - Optional ID for the client
  /// [routingProperties] - Optional properties for client routing
  /// [loadWeight] - Optional weight for load balancing
  /// [systemPrompt] - Optional system prompt for the LLM
  Future<LlmClient> createClient({
    required String providerName,
    LlmConfiguration? config,
    dynamic mcpClient, // Single client (backward compatibility)
    Map<String, dynamic>? mcpClients, // Multiple clients (new feature)
    StorageManager? storageManager,
    PluginManager? pluginManager,
    PerformanceMonitor? performanceMonitor,
    RetrievalManager? retrievalManager,
    String? clientId,
    Map<String, dynamic>? routingProperties,
    double loadWeight = 1.0,
    String? systemPrompt,
  }) async {
    // Get provider factory
    final factory = _llmRegistry.getProviderFactory(providerName);
    if (factory == null) {
      throw StateError('Provider not found: $providerName');
    }

    // Use provided configuration or create default
    final effectiveConfig = config ?? LlmConfiguration();

    // Create LLM provider
    final llmProvider = factory.createProvider(effectiveConfig);

    // Initialize provider if needed
    await llmProvider.initialize(effectiveConfig);

    // Use provided components or internal ones
    final effectivePluginManager = pluginManager ?? _pluginManager;
    final effectivePerformanceMonitor = performanceMonitor ?? _performanceMonitor;

    // Create LLM client with all optional components
    final client = LlmClient(
      llmProvider: llmProvider,
      mcpClient: mcpClient,
      mcpClients: mcpClients,
      storageManager: storageManager,
      pluginManager: effectivePluginManager,
      performanceMonitor: effectivePerformanceMonitor,
      retrievalManager: retrievalManager,
    );

    // Add system prompt to the chat session if provided
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      client.chatSession.addSystemMessage(systemPrompt);
    }

    // Generate client ID if not provided
    final id = clientId ?? 'llm_client_${DateTime.now().millisecondsSinceEpoch}';

    // Add to client manager
    _llmClientManager.addClient(
      id,
      client,
      routingProperties: routingProperties,
      weight: loadWeight,
    );

    return client;
  }

  /// Get a client by ID
  LlmClient? getClient(String clientId) {
    return _llmClientManager.getClient(clientId);
  }

  /// Select the most appropriate client for a query
  LlmClient? selectClient(String query, {Map<String, dynamic>? properties}) {
    return _llmClientManager.selectClient(query, properties: properties);
  }

  /// Execute a query across all clients
  Future<Map<String, LlmResponse>> fanOutQuery(String query, {
    bool enableTools = true,
    Map<String, dynamic> parameters = const {},
  }) async {
    return await _llmClientManager.fanOutQuery(
      query,
      enableTools: enableTools,
      parameters: parameters,
    );
  }

  /// Add an MCP client to an existing LLM client
  ///
  /// [llmClientId] - ID of the LLM client
  /// [mcpClientId] - ID for the new MCP client
  /// [mcpClient] - MCP client instance to add
  Future<bool> addMcpClientToLlmClient(
      String llmClientId,
      String mcpClientId,
      dynamic mcpClient
      ) async {
    final llmClient = _llmClientManager.getClient(llmClientId);
    if (llmClient == null) {
      _logger.warning('LLM client not found: $llmClientId');
      return false;
    }

    try {
      llmClient.addMcpClient(mcpClientId, mcpClient);
      _logger.info('Added MCP client "$mcpClientId" to LLM client "$llmClientId"');
      return true;
    } catch (e) {
      _logger.error('Failed to add MCP client to LLM client: $e');
      return false;
    }
  }

  /// Remove an MCP client from an existing LLM client
  ///
  /// [llmClientId] - ID of the LLM client
  /// [mcpClientId] - ID of the MCP client to remove
  Future<bool> removeMcpClientFromLlmClient(
      String llmClientId,
      String mcpClientId
      ) async {
    final llmClient = _llmClientManager.getClient(llmClientId);
    if (llmClient == null) {
      _logger.warning('LLM client not found: $llmClientId');
      return false;
    }

    try {
      llmClient.removeMcpClient(mcpClientId);
      _logger.info('Removed MCP client "$mcpClientId" from LLM client "$llmClientId"');
      return true;
    } catch (e) {
      _logger.error('Failed to remove MCP client from LLM client: $e');
      return false;
    }
  }

  /// Set the default MCP client for an LLM client
  ///
  /// [llmClientId] - ID of the LLM client
  /// [mcpClientId] - ID of the MCP client to set as default
  Future<bool> setDefaultMcpClient(
      String llmClientId,
      String mcpClientId
      ) async {
    final llmClient = _llmClientManager.getClient(llmClientId);
    if (llmClient == null) {
      _logger.warning('LLM client not found: $llmClientId');
      return false;
    }

    try {
      llmClient.setDefaultMcpClient(mcpClientId);
      _logger.info('Set default MCP client to "$mcpClientId" for LLM client "$llmClientId"');
      return true;
    } catch (e) {
      _logger.error('Failed to set default MCP client: $e');
      return false;
    }
  }

  /// Get all MCP client IDs for an LLM client
  ///
  /// [llmClientId] - ID of the LLM client
  List<String> getMcpClientIds(String llmClientId) {
    final llmClient = _llmClientManager.getClient(llmClientId);
    if (llmClient == null) {
      _logger.warning('LLM client not found: $llmClientId');
      return [];
    }

    return llmClient.getMcpClientIds();
  }

  /// Create an LLM server
  ///
  /// [providerName] - Name of the registered provider to use
  /// [config] - Configuration for the LLM provider
  /// [mcpServer] - Optional MCP server (from mcp_server package)
  /// [mcpServers] - Optional map of MCP servers (for multi-mcp_server support)
  /// [storageManager] - Optional storage manager for persistence
  /// [pluginManager] - Optional plugin manager or uses internal one if not provided
  /// [performanceMonitor] - Optional performance monitor
  /// [retrievalManager] - Optional retrieval manager for RAG capabilities
  /// [serverId] - Optional ID for the server
  /// [routingProperties] - Optional properties for client routing
  /// [loadWeight] - Optional weight for load balancing
  /// [systemPrompt] - Optional system prompt for the LLM
  Future<LlmServer> createServer({
    required String providerName,
    LlmConfiguration? config,
    dynamic mcpServer, // Single server (backward compatibility)
    Map<String, dynamic>? mcpServers, // Multiple servers (new feature)
    StorageManager? storageManager,
    PluginManager? pluginManager,
    PerformanceMonitor? performanceMonitor,
    RetrievalManager? retrievalManager,
    String? serverId,
    Map<String, dynamic>? routingProperties,
    double loadWeight = 1.0,
    String? systemPrompt,
  }) async {
    // Get provider factory
    final factory = _llmRegistry.getProviderFactory(providerName);
    if (factory == null) {
      throw StateError('Provider not found: $providerName');
    }

    // Use provided configuration or create default
    final effectiveConfig = config ?? LlmConfiguration();

    // Create LLM provider
    final llmProvider = factory.createProvider(effectiveConfig);

    // Initialize provider if needed
    await llmProvider.initialize(effectiveConfig);

    // Use provided components or internal ones
    final effectivePluginManager = pluginManager ?? _pluginManager;
    final effectivePerformanceMonitor = performanceMonitor ?? _performanceMonitor;

    // Create LLM client with all optional components
    final server = LlmServer(
      llmProvider: llmProvider,
      mcpServer: mcpServer,
      mcpServers: mcpServers,
      storageManager: storageManager,
      pluginManager: effectivePluginManager,
      performanceMonitor: effectivePerformanceMonitor,
      retrievalManager: retrievalManager,
    );

    // Add system prompt to the chat session if provided
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      server.chatSession.addSystemMessage(systemPrompt);
    }

    // Generate client ID if not provided
    final id = serverId ?? 'llm_server_${DateTime.now().millisecondsSinceEpoch}';

    // Add to client manager
    _llmServerManager.addServer(
      id,
      server,
      routingProperties: routingProperties,
      weight: loadWeight,
    );

    return server;
  }

  /// Get a server by ID
  LlmServer? getServer(String serverId) {
    return _llmServerManager.getServer(serverId);
  }

  /// Select the most appropriate client for a query
  LlmServer? selectServer(String query, {Map<String, dynamic>? properties}) {
    return _llmServerManager.selectServer(query, properties: properties);
  }

  /// Add an MCP server to an existing LLM server
  ///
  /// [llmServerId] - ID of the LLM server
  /// [mcpServerId] - ID for the new MCP server
  /// [mcpServer] - MCP server instance to add
  Future<bool> addMcpServerToLlmServer(
      String llmServerId,
      String mcpServerId,
      dynamic mcpServer
      ) async {
    final llmServer = _llmServerManager.getServer(llmServerId);
    if (llmServer== null) {
      _logger.warning('LLM server not found: $llmServerId');
      return false;
    }

    try {
      llmServer.addMcpServer(mcpServerId, mcpServer);
      _logger.info('Added MCP server "$mcpServerId" to LLM server "$llmServerId"');
      return true;
    } catch (e) {
      _logger.error('Failed to add MCP server to LLM server: $e');
      return false;
    }
  }

  /// Remove an MCP server from an existing LLM server
  ///
  /// [llmServerId] - ID of the LLM server
  /// [mcpServerId] - ID of the MCP server to remove
  Future<bool> removeMcpServerFromLlmServer(
      String llmServerId,
      String mcpServerId
      ) async {
    final llmServer = _llmServerManager.getServer(llmServerId);
    if (llmServer == null) {
      _logger.warning('LLM server not found: $llmServerId');
      return false;
    }

    try {
      llmServer.removeMcpServer(mcpServerId);
      _logger.info('Removed MCP server "$mcpServerId" from LLM server "$llmServerId"');
      return true;
    } catch (e) {
      _logger.error('Failed to remove MCP server from LLM server: $e');
      return false;
    }
  }

  /// Set the default MCP server for an LLM server
  ///
  /// [llmServerId] - ID of the LLM server
  /// [mcpServerId] - ID of the MCP server to set as default
  Future<bool> setDefaultMcpServer(
      String llmServerId,
      String mcpServerId
      ) async {
    final llmServer = _llmServerManager.getServer(llmServerId);
    if (llmServer == null) {
      _logger.warning('LLM server not found: $llmServerId');
      return false;
    }

    try {
      llmServer.setDefaultMcpServer(mcpServerId);
      _logger.info('Set default MCP server to "$mcpServerId" for LLM server "$llmServerId"');
      return true;
    } catch (e) {
      _logger.error('Failed to set default MCP server: $e');
      return false;
    }
  }

  /// Get all MCP server IDs for an LLM server
  ///
  /// [llmServerId] - ID of the LLM server
  List<String> getMcpServerIds(String llmServerId) {
    final llmServer = _llmServerManager.getServer(llmServerId);
    if (llmServer == null) {
      _logger.warning('LLM client not found: $llmServerId');
      return [];
    }

    return llmServer.getMcpServerIds();
  }

  /// Execute a query in parallel across multiple providers
  Future<LlmResponse> executeParallel(
      String query, {
        List<String>? providerNames,
        ResultAggregator? aggregator,
        Map<String, dynamic> parameters = const {},
        LlmConfiguration? config,
      }) async {
    // Determine which providers to use
    final providersToUse = providerNames ??
        _llmRegistry.getAvailableProviders();

    // Use provided configuration or create default
    final effectiveConfig = config ?? LlmConfiguration();

    // Create provider instances
    final providers = <LlmInterface>[];
    for (final providerName in providersToUse) {
      final factory = _llmRegistry.getProviderFactory(providerName);
      if (factory != null) {
        final provider = factory.createProvider(effectiveConfig);
        await provider.initialize(effectiveConfig);
        providers.add(provider);
      }
    }

    if (providers.isEmpty) {
      throw StateError('No valid providers available');
    }

    // Create parallel executor
    final executor = ParallelExecutor(
      providers: providers,
      aggregator: aggregator,
    );

    // Create request
    final request = LlmRequest(
      prompt: query,
      parameters: parameters,
    );

    // Execute in parallel
    return await executor.executeParallel(request);
  }

  /// Register a plugin
  Future<void> registerPlugin(LlmPlugin plugin, [Map<String, dynamic>? config]) async {
    await _pluginManager.registerPlugin(plugin, config);
  }

  /// Get provider capabilities
  Map<String, Set<LlmCapability>> getProviderCapabilities() {
    final result = <String, Set<LlmCapability>>{};

    for (final providerName in _llmRegistry.getAvailableProviders()) {
      final factory = _llmRegistry.getProviderFactory(providerName);
      if (factory != null) {
        result[providerName] = factory.capabilities;
      }
    }

    return result;
  }

  /// Get providers with a specific capability
  List<String> getProvidersWithCapability(LlmCapability capability) {
    return _llmRegistry.getProvidersWithCapability(capability);
  }

  /// Enable performance monitoring
  void enablePerformanceMonitoring({
    Duration interval = const Duration(seconds: 10),
    bool resetMetricsOnStart = false
  }) {
    // Option to reset metrics before starting
    if (resetMetricsOnStart) {
      _performanceMonitor.resetMetrics();
    }

    _performanceMonitor.startMonitoring(interval);
    _logger.info('Performance monitoring enabled with interval: ${interval.inSeconds}s');
  }

  /// Disable performance monitoring
  void disablePerformanceMonitoring() {
    _performanceMonitor.stopMonitoring();
    _logger.info('Performance monitoring disabled');
  }

  /// Reset performance metrics
  void resetPerformanceMetrics() {
    _performanceMonitor.resetMetrics();
    _logger.info('Performance metrics have been reset');
  }

  /// Get performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    return _performanceMonitor.getMetricsReport();
  }

  /// Get PerformanceMonitor instance (used in plugins, etc.)
  PerformanceMonitor getPerformanceMonitor() {
    return _performanceMonitor;
  }

  /// Create retrieval manager with document store
  RetrievalManager createRetrievalManager({
    required String providerName,
    required DocumentStore documentStore,
    LlmConfiguration? config,
  }) {
    // Get provider factory
    final factory = _llmRegistry.getProviderFactory(providerName);
    if (factory == null) {
      throw StateError('Provider not found: $providerName');
    }

    // Use provided configuration or create default
    final effectiveConfig = config ?? LlmConfiguration();

    // Create LLM provider
    final llmProvider = factory.createProvider(effectiveConfig);

    // Create retrieval manager
    return RetrievalManager.withDocumentStore(
      llmProvider: llmProvider,
      documentStore: documentStore,
    );
  }

  /// Create retrieval manager with vector store
  RetrievalManager createVectorRetrievalManager({
    required String providerName,
    required VectorStore vectorStore,
    String? defaultNamespace,
    LlmConfiguration? config,
  }) {
    // Get provider factory
    final factory = _llmRegistry.getProviderFactory(providerName);
    if (factory == null) {
      throw StateError('Provider not found: $providerName');
    }

    // Use provided configuration or create default
    final effectiveConfig = config ?? LlmConfiguration();

    // Create LLM provider
    final llmProvider = factory.createProvider(effectiveConfig);

    // Create retrieval manager
    return RetrievalManager.withVectorStore(
      llmProvider: llmProvider,
      vectorStore: vectorStore,
      defaultNamespace: defaultNamespace,
    );
  }

  /// Shutdown and clean up resources
  Future<void> shutdown() async {
    _logger.info('Shutting down MCPLlm system...');

    // Stop performance monitoring
    disablePerformanceMonitoring();

    // Close all clients
    await _llmClientManager.closeAll();

    // Shutdown plugin system
    await _pluginManager.shutdown();

    _logger.info('MCPLlm system shutdown completed');
  }
}

