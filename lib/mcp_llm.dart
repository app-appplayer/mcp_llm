/// Main library for integrating Large Language Models with MCP
library;

// Core components
export 'src/core/llm_interface.dart';
export 'src/core/llm_client.dart';
export 'src/core/llm_server.dart';
export 'src/core/llm_context.dart';
export 'src/core/llm_registry.dart';
export 'src/core/models.dart';

// Provider implementations
export 'src/providers/provider.dart';
export 'src/providers/claude_provider.dart';
export 'src/providers/openai_provider.dart';
export 'src/providers/together_provider.dart';
export 'src/providers/custom_provider.dart';

// Multi-client support
export 'src/multi_client/client_manager.dart';
export 'src/multi_client/client_router.dart';
export 'src/multi_client/client_pool.dart';
export 'src/multi_client/load_balancer.dart';

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
import 'src/multi_client/client_manager.dart';
import 'src/parallel/executor.dart';
import 'src/parallel/result_aggregator.dart';
import 'src/plugins/plugin_manager.dart';
import 'src/plugins/plugin_interface.dart';
import 'src/providers/provider.dart';
import 'src/rag/retrieval_manager.dart';
import 'src/storage/storage_manager.dart';
import 'src/utils/performance_monitor.dart';

typedef MCPLlm = McpLlm;
/// Main class for MCPLlm functionality
class McpLlm {
  /// LLM provider registry
  final LlmRegistry _llmRegistry = LlmRegistry();

  /// Client manager
  final MultiClientManager _clientManager = MultiClientManager();

  /// Plugin manager
  final PluginManager _pluginManager = PluginManager();

  /// Performance monitor
  final PerformanceMonitor _performanceMonitor = PerformanceMonitor();

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
  /// [storageManager] - Optional storage manager for persistence
  /// [clientId] - Optional ID for the client
  /// [routingProperties] - Optional properties for client routing
  /// [loadWeight] - Optional weight for load balancing
  Future<LlmClient> createClient({
    required String providerName,
    LlmConfiguration? config,
    dynamic mcpClient, // Type-agnostic to avoid direct dependency
    StorageManager? storageManager,
    String? clientId,
    Map<String, dynamic>? routingProperties,
    double loadWeight = 1.0,
  }) async {
    // Get provider factory
    final factory = _llmRegistry.getProviderFactory(providerName);
    if (factory == null) {
      throw StateError('Provider not found: $providerName');
    }

    // Create LLM provider
    final llmProvider = factory.createProvider(config ?? LlmConfiguration());

    // Create LLM client
    final client = LlmClient(
      llmProvider: llmProvider,
      mcpClient: mcpClient,
      storageManager: storageManager,
      pluginManager: _pluginManager,
    );

    // Generate client ID if not provided
    final id = clientId ?? 'llm_client_${DateTime.now().millisecondsSinceEpoch}';

    // Add to client manager
    _clientManager.addClient(
      id,
      client,
      routingProperties: routingProperties,
      loadWeight: loadWeight,
    );

    return client;
  }

  /// Create an LLM server
  ///
  /// [providerName] - Name of the registered provider to use
  /// [config] - Configuration for the LLM provider
  /// [mcpServer] - Optional MCP server (from mcp_server package)
  /// [storageManager] - Optional storage manager for persistence
  /// [retrievalManager] - Optional retrieval manager for RAG
  Future<LlmServer> createServer({
    required String providerName,
    LlmConfiguration? config,
    dynamic mcpServer, // Type-agnostic to avoid direct dependency
    StorageManager? storageManager,
    RetrievalManager? retrievalManager,
  }) async {
    // Get provider factory
    final factory = _llmRegistry.getProviderFactory(providerName);
    if (factory == null) {
      throw StateError('Provider not found: $providerName');
    }

    // Create LLM provider
    final llmProvider = factory.createProvider(config ?? LlmConfiguration());

    // Create LLM server
    return LlmServer(
      llmProvider: llmProvider,
      mcpServer: mcpServer,
      storageManager: storageManager,
      retrievalManager: retrievalManager,
      pluginManager: _pluginManager,
    );
  }

  /// Get a client by ID
  LlmClient? getClient(String clientId) {
    return _clientManager.getClient(clientId);
  }

  /// Select the most appropriate client for a query
  LlmClient? selectClient(String query, {Map<String, dynamic>? properties}) {
    return _clientManager.selectClient(query, properties: properties);
  }

  /// Execute a query across all clients
  Future<Map<String, LlmResponse>> fanOutQuery(String query, {
    bool enableTools = true,
    Map<String, dynamic> parameters = const {},
  }) async {
    return await _clientManager.fanOutQuery(
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
      }) async {
    // Determine which providers to use
    final providersToUse = providerNames ??
        _llmRegistry.getAvailableProviders();

    // Create provider instances
    final providers = <LlmInterface>[];
    for (final providerName in providersToUse) {
      final factory = _llmRegistry.getProviderFactory(providerName);
      if (factory != null) {
        final provider = factory.createProvider(LlmConfiguration());
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
  void enablePerformanceMonitoring({Duration interval = const Duration(seconds: 10)}) {
    _performanceMonitor.startMonitoring(interval);
  }

  /// Disable performance monitoring
  void disablePerformanceMonitoring() {
    _performanceMonitor.stopMonitoring();
  }

  /// Get performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    return _performanceMonitor.getMetricsReport();
  }

  /// Shutdown and clean up resources
  Future<void> shutdown() async {
    // Close all clients
    await _clientManager.closeAll();

    // Shutdown plugins
    await _pluginManager.shutdown();

    // Stop performance monitoring
    _performanceMonitor.stopMonitoring();
  }
}