/// Class that routes to appropriate clients based on queries
class ClientRouter {
  final Map<String, Map<String, dynamic>> _clientProperties = {};

  /// Register client with routing properties
  void registerClient(String clientId, Map<String, dynamic> properties) {
    _clientProperties[clientId] = properties;
  }

  /// Unregister client
  void unregisterClient(String clientId) {
    _clientProperties.remove(clientId);
  }

  /// Find appropriate client for query
  String? routeQuery(String query, [Map<String, dynamic>? queryProperties]) {
    if (queryProperties == null || queryProperties.isEmpty) {
      // Simple keyword-based routing
      for (final entry in _clientProperties.entries) {
        final keywords = entry.value['keywords'] as List<String>?;
        if (keywords != null &&
            keywords.any((keyword) =>
                query.toLowerCase().contains(keyword.toLowerCase()))) {
          return entry.key;
        }
      }
      return null;
    }

    // Property-based routing
    String? bestMatch;
    int highestMatches = 0;

    for (final entry in _clientProperties.entries) {
      int matches = 0;
      for (final prop in queryProperties.entries) {
        if (entry.value.containsKey(prop.key) &&
            entry.value[prop.key] == prop.value) {
          matches++;
        }
      }

      if (matches > highestMatches) {
        highestMatches = matches;
        bestMatch = entry.key;
      }
    }

    return bestMatch;
  }

  /// Initialize router
  void clear() {
    _clientProperties.clear();
  }
}
