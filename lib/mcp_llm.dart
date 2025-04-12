/// Main library for integrating Large Language Models with MCP
library;

// Multi-MCP Client Integration
export 'src/adapter/mcp_client_manager.dart';

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

  /// Client manager
  final MultiLlmClientManager _llmClientManager = MultiLlmClientManager();

  /// Plugin manager
  final PluginManager _pluginManager = PluginManager();

  /// Performance monitor
  final PerformanceMonitor _performanceMonitor = PerformanceMonitor();

  /// Logger instance
  final Logger _logger = Logger.getLogger('mcp_llm.mcpllm');

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
  /// [mcpClients] - Optional map of MCP clients (for multi-client support)
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

    // 시스템 프롬프트가 제공된 경우 채팅 세션에 추가
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
  /// [storageManager] - Optional storage manager for persistence
  /// [retrievalManager] - Optional retrieval manager for RAG
  /// [pluginManager] - Optional plugin manager or uses internal one if not provided
  /// [performanceMonitor] - Optional performance monitor
  Future<LlmServer> createServer({
    required String providerName,
    LlmConfiguration? config,
    dynamic mcpServer, // Type-agnostic to avoid direct dependency
    StorageManager? storageManager,
    RetrievalManager? retrievalManager,
    PluginManager? pluginManager,
    PerformanceMonitor? performanceMonitor,
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

    // Create LLM server with all components
    return LlmServer(
      llmProvider: llmProvider,
      mcpServer: mcpServer,
      storageManager: storageManager,
      retrievalManager: retrievalManager,
      pluginManager: effectivePluginManager,
      performanceMonitor: effectivePerformanceMonitor,
    );
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

  /// 성능 모니터링 활성화
  void enablePerformanceMonitoring({
    Duration interval = const Duration(seconds: 10),
    bool resetMetricsOnStart = false
  }) {
    // 시작 전 메트릭 초기화 옵션
    if (resetMetricsOnStart) {
      _performanceMonitor.resetMetrics();
    }

    _performanceMonitor.startMonitoring(interval);
    _logger.info('Performance monitoring enabled with interval: ${interval.inSeconds}s');
  }

  /// 성능 모니터링 비활성화
  void disablePerformanceMonitoring() {
    _performanceMonitor.stopMonitoring();
    _logger.info('Performance monitoring disabled');
  }

  /// 성능 메트릭 초기화
  void resetPerformanceMetrics() {
    _performanceMonitor.resetMetrics();
    _logger.info('Performance metrics have been reset');
  }

  /// 성능 메트릭 가져오기
  Map<String, dynamic> getPerformanceMetrics() {
    return _performanceMonitor.getMetricsReport();
  }

  /// PerformanceMonitor 인스턴스 가져오기 (플러그인 등에서 사용)
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

    // 성능 모니터링 중지
    disablePerformanceMonitoring();

    // 모든 클라이언트 종료
    await _llmClientManager.closeAll();

    // 플러그인 시스템 종료
    await _pluginManager.shutdown();

    _logger.info('MCPLlm system shutdown completed');
  }
}
