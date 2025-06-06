import 'dart:async';
import '../../mcp_llm.dart';
import 'managed_service.dart';

/// Implementation of service pool for resource pooling of clients or servers
class GenericServicePool<T> implements ServicePool<T> {
  /// Pool of available services
  final Map<String, List<T>> _availableServices = {};

  /// Services currently in use
  final Map<String, Set<T>> _inUseServices = {};

  /// Maximum pool size per service type
  final Map<String, int> _maxPoolSize = {};

  /// Default maximum pool size
  final int _defaultMaxPoolSize;

  /// Default timeout duration for service acquisition
  final Duration _defaultTimeout;

  /// Service factories for creating new services as needed
  final Map<String, ServiceFactory<T>> _serviceFactories = {};

  /// Logger instance
  final Logger _logger = Logger('mcp_llm.generic_service_pool');

  /// Create a new service pool
  GenericServicePool({
    int defaultMaxPoolSize = 5,
    Duration defaultTimeout = const Duration(seconds: 10),
  }) : _defaultMaxPoolSize = defaultMaxPoolSize,
        _defaultTimeout = defaultTimeout;

  @override
  void registerServiceFactory(String serviceType, ServiceFactory<T> factory, {int? maxPoolSize}) {
    _serviceFactories[serviceType] = factory;

    if (maxPoolSize != null) {
      _maxPoolSize[serviceType] = maxPoolSize;
    }

    _logger.debug('Registered service factory for type: $serviceType');
  }

  @override
  void setMaxPoolSize(String serviceType, int size) {
    _maxPoolSize[serviceType] = size;
  }

  /// Get maximum pool size for a service type
  int getMaxPoolSize(String serviceType) {
    return _maxPoolSize[serviceType] ?? _defaultMaxPoolSize;
  }

  @override
  Future<T> getService(String serviceType, {Duration? timeout}) async {
    // Ensure we have a list for this service type
    _availableServices.putIfAbsent(serviceType, () => []);
    _inUseServices.putIfAbsent(serviceType, () => {});

    // Check if there's an available service
    if (_availableServices[serviceType]!.isNotEmpty) {
      final service = _availableServices[serviceType]!.removeLast();
      _inUseServices[serviceType]!.add(service);
      _logger.debug('Retrieved existing service from pool for type: $serviceType');
      return service;
    }

    // Check if we've reached the pool size limit
    final maxSize = getMaxPoolSize(serviceType);
    final currentSize = _inUseServices[serviceType]!.length;

    if (currentSize >= maxSize) {
      _logger.warning('Service pool for $serviceType is at capacity ($maxSize). Waiting for a service to become available.');

      // Wait for a service to be returned to the pool
      final completer = Completer<T>();
      final actualTimeout = timeout ?? _defaultTimeout;

      // Initialize timers as nullable
      Timer? timeoutTimer;
      Timer? checkTimer;

      // Function to check for an available service
      void checkForAvailableService() {
        if (_availableServices[serviceType]!.isNotEmpty) {
          timeoutTimer?.cancel();
          checkTimer?.cancel();

          final service = _availableServices[serviceType]!.removeLast();
          _inUseServices[serviceType]!.add(service);

          completer.complete(service);
        }
      }

      // Set up a periodic check
      checkTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        checkForAvailableService();
      });

      // Set a timeout
      timeoutTimer = Timer(actualTimeout, () {
        checkTimer?.cancel();

        if (!completer.isCompleted) {
          _logger.error('Timeout waiting for available service for type: $serviceType');
          completer.completeError(TimeoutException(
              'Timeout waiting for available service after ${actualTimeout.inSeconds} seconds'));
        }
      });

      return completer.future;
    }

    // Create a new service
    final factory = _serviceFactories[serviceType];
    if (factory == null) {
      throw StateError('No factory registered for service type: $serviceType');
    }

    final service = await factory.createService();
    _inUseServices[serviceType]!.add(service);

    _logger.debug('Created new service for type: $serviceType');
    return service;
  }

  @override
  void releaseService(String serviceType, T service) {
    if (!_inUseServices.containsKey(serviceType) ||
        !_inUseServices[serviceType]!.contains(service)) {
      _logger.warning('Attempting to release a service that is not in use: $serviceType');
      return;
    }

    _inUseServices[serviceType]!.remove(service);
    _availableServices[serviceType]!.add(service);

    _logger.debug('Released service back to pool for type: $serviceType');
  }

  @override
  Future<void> close() async {
    _logger.debug('Closing service pool');

    // We would need a way to close/cleanup services
    // For now, we're just clearing the collections
    _availableServices.clear();
    _inUseServices.clear();

    _logger.debug('Service pool closed');
  }

  @override
  Map<String, Map<String, int>> getPoolStats() {
    final stats = <String, Map<String, int>>{};

    for (final serviceType in {..._availableServices.keys, ..._inUseServices.keys}) {
      stats[serviceType] = {
        'available': _availableServices[serviceType]?.length ?? 0,
        'in_use': _inUseServices[serviceType]?.length ?? 0,
        'max_size': getMaxPoolSize(serviceType),
      };
    }

    return stats;
  }
}

/// Implementation of service factory for LLM clients
class LlmClientFactory implements ServiceFactory<LlmClient> {
  final String providerName;
  final LlmConfiguration configuration;
  final LlmRegistry registry;
  final StorageManager? storageManager;
  final PluginManager? pluginManager;
  final String? systemPrompt;

  LlmClientFactory({
    required this.providerName,
    required this.configuration,
    required this.registry,
    this.storageManager,
    this.pluginManager,
    this.systemPrompt,
  });

  @override
  Future<LlmClient> createService() async {
    // Get provider factory
    final factory = registry.getProviderFactory(providerName);
    if (factory == null) {
      throw StateError('Provider not found: $providerName');
    }

    // Create LLM provider
    final llmProvider = factory.createProvider(configuration);

    // Initialize provider
    await llmProvider.initialize(configuration);

    // Create LLM client
    final client = LlmClient(
      llmProvider: llmProvider,
      storageManager: storageManager,
      pluginManager: pluginManager,
    );

    // Set system prompt if provided
    if (systemPrompt != null && systemPrompt!.isNotEmpty) {
      client.setSystemPrompt(systemPrompt!);
    }

    return client;
  }
}

/// Implementation of service factory for LLM servers
class LlmServerFactory implements ServiceFactory<LlmServer> {
  final String providerName;
  final LlmConfiguration configuration;
  final LlmRegistry registry;
  final StorageManager? storageManager;
  final PluginManager? pluginManager;
  final RetrievalManager? retrievalManager;

  LlmServerFactory({
    required this.providerName,
    required this.configuration,
    required this.registry,
    this.storageManager,
    this.pluginManager,
    this.retrievalManager,
  });

  @override
  Future<LlmServer> createService() async {
    // Get provider factory
    final factory = registry.getProviderFactory(providerName);
    if (factory == null) {
      throw StateError('Provider not found: $providerName');
    }

    // Create LLM provider
    final llmProvider = factory.createProvider(configuration);

    // Initialize provider
    await llmProvider.initialize(configuration);

    // Create LLM server
    return LlmServer(
      llmProvider: llmProvider,
      storageManager: storageManager,
      pluginManager: pluginManager ?? PluginManager(),
      retrievalManager: retrievalManager,
    );
  }
}