import 'dart:async';

import '../core/llm_client.dart';
import '../utils/logger.dart';

/// Manages a pool of LLM clients with connection pooling
class ClientPool {
  /// Pool of available clients
  final Map<String, List<LlmClient>> _availableClients = {};

  /// Clients currently in use
  final Map<String, Set<LlmClient>> _inUseClients = {};

  /// Maximum pool size per provider
  final Map<String, int> _maxPoolSize = {};

  /// Default maximum pool size
  final int _defaultMaxPoolSize;

  /// Client factories for creating new clients as needed
  final Map<String, LlmClientFactory> _clientFactories = {};

  /// Logger instance
  final Logger _logger = Logger.instance;

  /// Create a new client pool
  ClientPool({int defaultMaxPoolSize = 5})
      : _defaultMaxPoolSize = defaultMaxPoolSize;

  /// Register a client factory
  void registerClientFactory(String providerName, LlmClientFactory factory, {int? maxPoolSize}) {
    _clientFactories[providerName] = factory;

    if (maxPoolSize != null) {
      _maxPoolSize[providerName] = maxPoolSize;
    }

    _logger.debug('Registered client factory for provider: $providerName');
  }

  /// Set maximum pool size for a provider
  void setMaxPoolSize(String providerName, int size) {
    _maxPoolSize[providerName] = size;
  }

  /// Get maximum pool size for a provider
  int getMaxPoolSize(String providerName) {
    return _maxPoolSize[providerName] ?? _defaultMaxPoolSize;
  }

  /// Get a client from the pool
  Future<LlmClient> getClient(String providerName) async {
    // Ensure we have a list for this provider
    _availableClients.putIfAbsent(providerName, () => []);
    _inUseClients.putIfAbsent(providerName, () => {});

    // Check if there's an available client
    if (_availableClients[providerName]!.isNotEmpty) {
      final client = _availableClients[providerName]!.removeLast();
      _inUseClients[providerName]!.add(client);
      _logger.debug('Retrieved existing client from pool for provider: $providerName');
      return client;
    }

    // Check if we've reached the pool size limit
    final maxSize = getMaxPoolSize(providerName);
    final currentSize = _inUseClients[providerName]!.length;

    if (currentSize >= maxSize) {
      _logger.warning('Client pool for $providerName is at capacity ($maxSize). Waiting for a client to become available.');

      // Wait for a client to be returned to the pool
      final completer = Completer<LlmClient>();

      // Wait for a client to become available with timeout
      Timer? timeoutTimer;

      // Function to check for an available client
      void checkForAvailableClient() {
        if (_availableClients[providerName]!.isNotEmpty) {
          timeoutTimer?.cancel();

          final client = _availableClients[providerName]!.removeLast();
          _inUseClients[providerName]!.add(client);

          completer.complete(client);
        }
      }

      // Set up a periodic check
      final checkTimer = Timer.periodic(Duration(milliseconds: 100), (_) {
        checkForAvailableClient();
      });

      // Set a timeout
      timeoutTimer = Timer(Duration(seconds: 10), () {
        checkTimer.cancel();

        if (!completer.isCompleted) {
          _logger.error('Timeout waiting for available client for provider: $providerName');
          completer.completeError(TimeoutException('Timeout waiting for available client'));
        }
      });

      return completer.future;
    }

    // Create a new client
    final factory = _clientFactories[providerName];
    if (factory == null) {
      throw StateError('No factory registered for provider: $providerName');
    }

    final client = await factory.createClient();
    _inUseClients[providerName]!.add(client);

    _logger.debug('Created new client for provider: $providerName');
    return client;
  }

  /// Return a client to the pool
  void releaseClient(String providerName, LlmClient client) {
    if (!_inUseClients.containsKey(providerName) ||
        !_inUseClients[providerName]!.contains(client)) {
      _logger.warning('Attempting to release a client that is not in use: $providerName');
      return;
    }

    _inUseClients[providerName]!.remove(client);
    _availableClients[providerName]!.add(client);

    _logger.debug('Released client back to pool for provider: $providerName');
  }

  /// Close all clients and clear the pool
  Future<void> close() async {
    final futures = <Future<void>>[];

    // Close all available clients
    for (final provider in _availableClients.keys) {
      for (final client in _availableClients[provider]!) {
        futures.add(client.close());
      }
    }

    // Close all in-use clients
    for (final provider in _inUseClients.keys) {
      for (final client in _inUseClients[provider]!) {
        futures.add(client.close());
      }
    }

    // Wait for all clients to close
    await Future.wait(futures);

    // Clear the pools
    _availableClients.clear();
    _inUseClients.clear();

    _logger.debug('Closed all clients and cleared the pool');
  }

  /// Get the current pool statistics
  Map<String, Map<String, int>> getPoolStats() {
    final stats = <String, Map<String, int>>{};

    for (final provider in {..._availableClients.keys, ..._inUseClients.keys}) {
      stats[provider] = {
        'available': _availableClients[provider]?.length ?? 0,
        'in_use': _inUseClients[provider]?.length ?? 0,
        'max_size': getMaxPoolSize(provider),
      };
    }

    return stats;
  }
}

/// Factory interface for creating LLM clients
abstract class LlmClientFactory {
  /// Create a new LLM client
  Future<LlmClient> createClient();
}