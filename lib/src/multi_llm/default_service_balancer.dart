
import '../../mcp_llm.dart';
import 'managed_service.dart';

/// Default implementation of ServiceBalancer
class DefaultServiceBalancer implements ServiceBalancer {
  final Map<String, double> _serviceWeights = {};
  int _currentIndex = 0;
  final List<String> _roundRobinList = [];
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
    if (_roundRobinList.isEmpty) return null;

    final serviceId = _roundRobinList[_currentIndex];
    _currentIndex = (_currentIndex + 1) % _roundRobinList.length;
    return serviceId;
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
    _roundRobinList.clear();
    _currentIndex = 0;
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
    _roundRobinList.clear();

    for (final entry in _serviceWeights.entries) {
      final String serviceId = entry.key;
      final int weightCount = (entry.value * 10).round(); // Scale weight by 10x

      for (int i = 0; i < weightCount; i++) {
        _roundRobinList.add(serviceId);
      }
    }

    // Shuffle the list
    _roundRobinList.shuffle();
    _currentIndex = 0;
  }
}