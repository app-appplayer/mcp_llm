import 'dart:async';
import 'dart:math';

import '../../mcp_llm.dart';
import 'managed_service.dart';

/// Advanced implementation of ServiceBalancer with multiple strategies
/// and service health monitoring
class AdvancedServiceBalancer implements ServiceBalancer {
  // Service weight map
  final Map<String, double> _serviceWeights = {};

  // Service state tracking
  final Map<String, _ServiceState> _serviceStates = {};

  // Round robin list
  final List<String> _roundRobinList = [];

  // Current round robin index
  int _currentIndex = 0;

  // Load balancing strategy
  BalancingStrategy _strategy = BalancingStrategy.weightedRoundRobin;

  // Status evaluation interval
  late Timer _healthCheckTimer;

  // Logging
  final Logger _logger = Logger('mcp_llm.advanced_service_balancer');

  // Constructor
  AdvancedServiceBalancer({
    BalancingStrategy strategy = BalancingStrategy.weightedRoundRobin,
    Duration healthCheckInterval = const Duration(seconds: 30),
  }) {
    _strategy = strategy;
    _startHealthChecks(healthCheckInterval);
  }

  // Start health checks
  void _startHealthChecks(Duration interval) {
    _healthCheckTimer = Timer.periodic(interval, (_) {
      _updateServiceHealth();
    });
  }

  @override
  void registerService(String serviceId, {double weight = 1.0}) {
    _serviceWeights[serviceId] = weight;
    _serviceStates[serviceId] = _ServiceState(
      serviceId: serviceId,
      maxConcurrentRequests: 5,
    );

    _updateRoundRobinList();
    _logger.debug('Registered service: $serviceId with weight $weight');
  }

  @override
  void unregisterService(String serviceId) {
    _serviceWeights.remove(serviceId);
    _serviceStates.remove(serviceId);

    _updateRoundRobinList();
    _logger.debug('Unregistered service: $serviceId');
  }

  // Update round robin list
  void _updateRoundRobinList() {
    _roundRobinList.clear();

    // Distribute services based on weight and health status
    for (final entry in _serviceWeights.entries) {
      final serviceId = entry.key;
      final state = _serviceStates[serviceId];

      if (state == null) continue;

      // Calculate final weight by combining health status and weight
      double effectiveWeight = entry.value * state.healthFactor;

      // Determine number of items based on weight (minimum 1)
      int count = max(1, (effectiveWeight * 10).round());

      for (int i = 0; i < count; i++) {
        _roundRobinList.add(serviceId);
      }
    }

    // Shuffle the list
    _roundRobinList.shuffle();
    _currentIndex = 0;
  }

  @override
  String? getNextService() {
    if (_roundRobinList.isEmpty) return null;

    switch (_strategy) {
      case BalancingStrategy.weightedRoundRobin:
        return _getNextRoundRobinService();

      case BalancingStrategy.leastConnections:
        return _getLeastConnectionsService();

      case BalancingStrategy.fastestResponse:
        return _getFastestResponseService();

      case BalancingStrategy.adaptiveLoad:
        return _getAdaptiveLoadService();
    }
  }

  // Weight-based round robin selection
  String? _getNextRoundRobinService() {
    if (_roundRobinList.isEmpty) return null;

    final serviceId = _roundRobinList[_currentIndex];
    _currentIndex = (_currentIndex + 1) % _roundRobinList.length;

    return serviceId;
  }

  // Least connections selection
  String? _getLeastConnectionsService() {
    if (_serviceStates.isEmpty) return null;

    String? bestService;
    int lowestConnections = -1;

    for (final state in _serviceStates.values) {
      // Initialize or update if fewer connections found
      if (lowestConnections == -1 ||
          state.currentRequests < lowestConnections) {
        lowestConnections = state.currentRequests;
        bestService = state.serviceId;
      }
    }

    return bestService;
  }

  // Fastest response time selection
  String? _getFastestResponseService() {
    if (_serviceStates.isEmpty) return null;

    String? bestService;
    double fastestAvgResponseTime = double.infinity;

    for (final state in _serviceStates.values) {
      if (state.avgResponseTime < fastestAvgResponseTime) {
        fastestAvgResponseTime = state.avgResponseTime;
        bestService = state.serviceId;
      }
    }

    return bestService;
  }

  // Adaptive load selection
  String? _getAdaptiveLoadService() {
    if (_serviceStates.isEmpty) return null;

    // Calculate state weights
    Map<String, double> scores = {};

    for (final entry in _serviceStates.entries) {
      final state = entry.value;
      final serviceWeight = _serviceWeights[state.serviceId] ?? 1.0;

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
      double finalScore = serviceWeight *
          (responseTimeScore * 0.4 +
              utilizationScore * 0.4 +
              errorRateScore * 0.2);

      scores[state.serviceId] = finalScore;
    }

    // Select service with highest score
    String? bestService;
    double highestScore = -1;

    for (final entry in scores.entries) {
      if (entry.value > highestScore) {
        highestScore = entry.value;
        bestService = entry.key;
      }
    }

    return bestService;
  }

  /// Record request start for a service
  void recordRequestStart(String serviceId) {
    final state = _serviceStates[serviceId];
    if (state != null) {
      state.currentRequests++;
      state.requestCount++;
      state.lastRequestStartTime = DateTime.now();
    }
  }

  /// Record request completion for a service
  void recordRequestEnd(String serviceId,
      {bool success = true, int responseTimeMs = 0}) {
    final state = _serviceStates[serviceId];
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

  // Periodically update service health status
  void _updateServiceHealth() {
    for (final state in _serviceStates.values) {
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

  @override
  void clear() {
    _serviceWeights.clear();
    _serviceStates.clear();
    _roundRobinList.clear();
    _currentIndex = 0;
    _healthCheckTimer.cancel();
  }

  @override
  Map<String, Map<String, dynamic>> getServiceStats() {
    Map<String, Map<String, dynamic>> stats = {};

    for (final entry in _serviceStates.entries) {
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

  @override
  void updateServiceWeight(String serviceId, double weight) {
    if (_serviceWeights.containsKey(serviceId)) {
      _serviceWeights[serviceId] = weight;
      _updateRoundRobinList();
      _logger.debug('Updated weight for service $serviceId to $weight');
    }
  }

  /// Set balancing strategy
  void setBalancingStrategy(BalancingStrategy strategy) {
    _strategy = strategy;
    _logger.info('Balancing strategy changed to: ${strategy.toString().split('.').last}');
  }
}

/// Load balancing strategy enum
enum BalancingStrategy {
  weightedRoundRobin, // Weight-based round robin
  leastConnections, // Prioritize least number of connections
  fastestResponse, // Prioritize fastest response time
  adaptiveLoad, // Adaptive load distribution
}

/// Service state tracking class
class _ServiceState {
  final String serviceId;
  final int maxConcurrentRequests;

  int currentRequests = 0; // Current active request count
  int requestCount = 0; // Total request count
  int errorCount = 0; // Error count
  DateTime? lastRequestStartTime; // Last request start time

  double avgResponseTime = 0.0; // Average response time (ms)
  double healthFactor = 1.0; // Health factor (0.0-1.0)

  final List<int> _responseTimeSamples = []; // Recent response time samples
  final int _maxSamples = 20; // Maximum sample count

  _ServiceState({
    required this.serviceId,
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