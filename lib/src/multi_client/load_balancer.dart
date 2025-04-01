/// Class that handles load balancing between clients
class LoadBalancer {
  final Map<String, double> _clientWeights = {};
  int _currentIndex = 0;
  final List<String> _roundRobinList = [];

  /// Register new client
  void registerClient(String clientId, {double weight = 1.0}) {
    _clientWeights[clientId] = weight;
    _updateRoundRobinList();
  }

  /// Unregister client
  void unregisterClient(String clientId) {
    _clientWeights.remove(clientId);
    _updateRoundRobinList();
  }

  /// Update weighted round-robin list
  void _updateRoundRobinList() {
    _roundRobinList.clear();

    for (final entry in _clientWeights.entries) {
      final String clientId = entry.key;
      final int weightCount = (entry.value * 10).round(); // Scale weight by 10x

      for (int i = 0; i < weightCount; i++) {
        _roundRobinList.add(clientId);
      }
    }

    // Shuffle the list
    _roundRobinList.shuffle();
    _currentIndex = 0;
  }

  /// Get next client
  String? getNextClient() {
    if (_roundRobinList.isEmpty) return null;

    final clientId = _roundRobinList[_currentIndex];
    _currentIndex = (_currentIndex + 1) % _roundRobinList.length;
    return clientId;
  }

  /// Initialize load balancer
  void clear() {
    _clientWeights.clear();
    _roundRobinList.clear();
    _currentIndex = 0;
  }
}
