import 'dart:async';
import 'dart:math';

import '../../mcp_llm.dart';

class AdvancedLoadBalancer {
  // Client weight map
  final Map<String, double> _clientWeights = {};

  // Client state tracking
  final Map<String, _ClientState> _clientStates = {};

  // Round robin list
  final List<String> _roundRobinList = [];

  // Current round robin index
  int _currentIndex = 0;

  // Load balancing strategy
  LoadBalancingStrategy _strategy = LoadBalancingStrategy.weightedRoundRobin;

  // Status evaluation interval
  late Timer _healthCheckTimer;

  // Logging
  final Logger _logger = Logger.getLogger('mcp_llm.advanced_load_balancer');

  // Constructor
  AdvancedLoadBalancer({
    LoadBalancingStrategy strategy = LoadBalancingStrategy.weightedRoundRobin,
    Duration healthCheckInterval = const Duration(seconds: 30),
  }) {
    _strategy = strategy;
    _startHealthChecks(healthCheckInterval);
  }

  // Start health checks
  void _startHealthChecks(Duration interval) {
    _healthCheckTimer = Timer.periodic(interval, (_) {
      _updateClientHealth();
    });
  }

  // Register client
  void registerClient(
    String clientId, {
    double weight = 1.0,
    int maxConcurrentRequests = 5,
  }) {
    _clientWeights[clientId] = weight;
    _clientStates[clientId] = _ClientState(
      clientId: clientId,
      maxConcurrentRequests: maxConcurrentRequests,
    );

    _updateRoundRobinList();
    _logger.debug('Registered client: $clientId with weight $weight');
  }

  // Unregister client
  void unregisterClient(String clientId) {
    _clientWeights.remove(clientId);
    _clientStates.remove(clientId);

    _updateRoundRobinList();
    _logger.debug('Unregistered client: $clientId');
  }

  // Update round robin list
  void _updateRoundRobinList() {
    _roundRobinList.clear();

    // Distribute clients based on weight and health status
    for (final entry in _clientWeights.entries) {
      final clientId = entry.key;
      final state = _clientStates[clientId];

      if (state == null) continue;

      // Calculate final weight by combining health status and weight
      double effectiveWeight = entry.value * state.healthFactor;

      // Determine number of items based on weight (minimum 1)
      int count = max(1, (effectiveWeight * 10).round());

      for (int i = 0; i < count; i++) {
        _roundRobinList.add(clientId);
      }
    }

    // Shuffle the list
    _roundRobinList.shuffle();
    _currentIndex = 0;
  }

  // Select next client
  String? getNextClient() {
    if (_roundRobinList.isEmpty) return null;

    switch (_strategy) {
      case LoadBalancingStrategy.weightedRoundRobin:
        return _getNextRoundRobinClient();

      case LoadBalancingStrategy.leastConnections:
        return _getLeastConnectionsClient();

      case LoadBalancingStrategy.fastestResponse:
        return _getFastestResponseClient();

      case LoadBalancingStrategy.adaptiveLoad:
        return _getAdaptiveLoadClient();
    }
  }

  // Weight-based round robin selection
  String? _getNextRoundRobinClient() {
    if (_roundRobinList.isEmpty) return null;

    final clientId = _roundRobinList[_currentIndex];
    _currentIndex = (_currentIndex + 1) % _roundRobinList.length;

    return clientId;
  }

  // Least connections selection
  String? _getLeastConnectionsClient() {
    if (_clientStates.isEmpty) return null;

    String? bestClient;
    int lowestConnections = -1;

    for (final state in _clientStates.values) {
      // Initialize or update if fewer connections found
      if (lowestConnections == -1 ||
          state.currentRequests < lowestConnections) {
        lowestConnections = state.currentRequests;
        bestClient = state.clientId;
      }
    }

    return bestClient;
  }

  // Fastest response time selection
  String? _getFastestResponseClient() {
    if (_clientStates.isEmpty) return null;

    String? bestClient;
    double fastestAvgResponseTime = double.infinity;

    for (final state in _clientStates.values) {
      if (state.avgResponseTime < fastestAvgResponseTime) {
        fastestAvgResponseTime = state.avgResponseTime;
        bestClient = state.clientId;
      }
    }

    return bestClient;
  }

  // Adaptive load selection
  String? _getAdaptiveLoadClient() {
    if (_clientStates.isEmpty) return null;

    // Calculate state weights
    Map<String, double> scores = {};

    for (final entry in _clientStates.entries) {
      final state = entry.value;
      final clientWeight = _clientWeights[state.clientId] ?? 1.0;

      // Response time score (faster = higher score)
      double responseTimeScore = 1.0;
      if (state.avgResponseTime > 0) {
        responseTimeScore = 1.0 / (state.avgResponseTime / 1000);
      }

      // Utilization score (lower = higher score)
      double utilizationScore = 1.0;
      if (state.maxConcurrentRequests > 0) {
        utilizationScore =
            1.0 - (state.currentRequests / state.maxConcurrentRequests);
      }

      // Error rate score (lower = higher score)
      double errorRateScore = 1.0;
      if (state.requestCount > 0) {
        errorRateScore = 1.0 - (state.errorCount / state.requestCount);
      }

      // Calculate final score
      double finalScore = clientWeight *
          (responseTimeScore * 0.4 +
              utilizationScore * 0.4 +
              errorRateScore * 0.2);

      scores[state.clientId] = finalScore;
    }

    // Select client with highest score
    String? bestClient;
    double highestScore = -1;

    for (final entry in scores.entries) {
      if (entry.value > highestScore) {
        highestScore = entry.value;
        bestClient = entry.key;
      }
    }

    return bestClient;
  }

  // Record request start
  void recordRequestStart(String clientId) {
    final state = _clientStates[clientId];
    if (state != null) {
      state.currentRequests++;
      state.requestCount++;
      state.lastRequestStartTime = DateTime.now();
    }
  }

  // Record request completion
  void recordRequestEnd(String clientId,
      {bool success = true, int responseTimeMs = 0}) {
    final state = _clientStates[clientId];
    if (state != null) {
      state.currentRequests--;

      if (!success) {
        state.errorCount++;
      }

      // Update response time
      if (responseTimeMs > 0) {
        state.addResponseTime(responseTimeMs);
      } else if (state.lastRequestStartTime != null) {
        final duration = DateTime.now().difference(state.lastRequestStartTime!);
        state.addResponseTime(duration.inMilliseconds);
      }
    }
  }

  // Periodically update client health status
  void _updateClientHealth() {
    for (final state in _clientStates.values) {
      // Calculate health score based on error rate
      double newHealthFactor = 1.0;

      if (state.requestCount > 10) {
        // Only adjust after collecting sufficient statistics
        final errorRate = state.requestCount > 0
            ? state.errorCount / state.requestCount
            : 0.0;

        // Generate health score based on error rate
        if (errorRate > 0.5) {
          newHealthFactor = 0.1; // Severe error rate
        } else if (errorRate > 0.2) {
          newHealthFactor = 0.5; // High error rate
        } else if (errorRate > 0.1) {
          newHealthFactor = 0.8; // Minor error rate
        }
      }

      // Adjust based on response time
      if (state.avgResponseTime > 5000) {
        // Very slow if over 5 seconds
        newHealthFactor *= 0.5;
      } else if (state.avgResponseTime > 2000) {
        // Slow if over 2 seconds
        newHealthFactor *= 0.8;
      }

      // Update state
      state.healthFactor = newHealthFactor;
    }

    // Update round robin list
    _updateRoundRobinList();
  }

  // Clear load balancer
  void clear() {
    _clientWeights.clear();
    _clientStates.clear();
    _roundRobinList.clear();
    _currentIndex = 0;
    _healthCheckTimer.cancel();
  }

  // Get client statistics
  Map<String, Map<String, dynamic>> getClientStats() {
    Map<String, Map<String, dynamic>> stats = {};

    for (final entry in _clientStates.entries) {
      stats[entry.key] = {
        'current_requests': entry.value.currentRequests,
        'request_count': entry.value.requestCount,
        'error_count': entry.value.errorCount,
        'avg_response_time_ms': entry.value.avgResponseTime,
        'health_factor': entry.value.healthFactor,
      };
    }

    return stats;
  }

  // Set load balancing strategy
  void setStrategy(LoadBalancingStrategy strategy) {
    _strategy = strategy;
    _logger.info(
        'Load balancing strategy changed to: ${strategy.toString().split('.').last}');
  }
}

// Load balancing strategy enum
enum LoadBalancingStrategy {
  weightedRoundRobin, // Weight-based round robin
  leastConnections, // Prioritize least number of connections
  fastestResponse, // Prioritize fastest response time
  adaptiveLoad, // Adaptive load distribution
}

// Client state tracking class
class _ClientState {
  final String clientId;
  final int maxConcurrentRequests;

  int currentRequests = 0; // Current active request count
  int requestCount = 0; // Total request count
  int errorCount = 0; // Error count
  DateTime? lastRequestStartTime; // Last request start time

  double avgResponseTime = 0.0; // Average response time (ms)
  double healthFactor = 1.0; // Health factor (0.0-1.0)

  final List<int> _responseTimeSamples = []; // Recent response time samples
  final int _maxSamples = 20; // Maximum sample count

  _ClientState({
    required this.clientId,
    this.maxConcurrentRequests = 5,
  });

  // Add response time
  void addResponseTime(int responseTimeMs) {
    _responseTimeSamples.add(responseTimeMs);

    // Maintain maximum sample count
    if (_responseTimeSamples.length > _maxSamples) {
      _responseTimeSamples.removeAt(0);
    }

    // Recalculate average
    if (_responseTimeSamples.isNotEmpty) {
      int total = _responseTimeSamples.reduce((a, b) => a + b);
      avgResponseTime = total / _responseTimeSamples.length;
    }
  }
}
