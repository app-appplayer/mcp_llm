
import '../../mcp_llm.dart';

/// Default implementation of ServiceBalancer
class DefaultServiceBalancer implements ServiceBalancer {
  final Map<String, double> _serviceWeights = {};

  /// Smooth weighted round-robin state: each pick adds every service's
  /// weight to its running score and takes the highest, which then pays the
  /// total back. Picks follow the weights in every window, and equal
  /// weights take strict turns.
  final Map<String, double> _current = {};
  final Logger _logger = Logger('mcp_llm.default_service_balancer');

  @override
  void registerService(String serviceId, {double weight = 1.0}) {
    _serviceWeights[serviceId] = weight;
    _updateRoundRobinList();
    _logger.debug('Registered service: $serviceId with weight $weight');
  }

  @override
  void unregisterService(String serviceId) {
    _serviceWeights.remove(serviceId);
    _updateRoundRobinList();
    _logger.debug('Unregistered service: $serviceId');
  }

  @override
  String? getNextService() {
    final eligible = _serviceWeights.entries.where((e) => e.value > 0).toList();
    if (eligible.isEmpty) return null;
    var total = 0.0;
    MapEntry<String, double>? best;
    for (final e in eligible) {
      total += e.value;
      final score = (_current[e.key] ?? 0) + e.value;
      _current[e.key] = score;
      if (best == null || score > best.value) best = MapEntry(e.key, score);
    }
    _current[best!.key] = best.value - total;
    return best.key;
  }

  @override
  void updateServiceWeight(String serviceId, double weight) {
    if (_serviceWeights.containsKey(serviceId)) {
      _serviceWeights[serviceId] = weight;
      _updateRoundRobinList();
      _logger.debug('Updated weight for service $serviceId to $weight');
    }
  }

  @override
  void clear() {
    _serviceWeights.clear();
    _current.clear();
    _logger.debug('Cleared all services');
  }

  @override
  Map<String, Map<String, dynamic>> getServiceStats() {
    final stats = <String, Map<String, dynamic>>{};

    for (final entry in _serviceWeights.entries) {
      stats[entry.key] = {
        'weight': entry.value,
      };
    }

    return stats;
  }

  /// Update weighted round-robin list
  void _updateRoundRobinList() {
    // Scores start over whenever the set of services or a weight changes.
    _current.clear();
  }
}