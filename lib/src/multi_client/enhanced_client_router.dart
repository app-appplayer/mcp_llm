import 'package:collection/collection.dart';

import '../../mcp_llm.dart';

class EnhancedClientRouter {
  // Client properties map
  final Map<String, Map<String, dynamic>> _clientProperties = {};

  // Logging
  final Logger _logger = Logger.getLogger('mcp_llm.enhanced_client_router');

  // Constructor
  EnhancedClientRouter();

  // Register client
  void registerClient(String clientId, Map<String, dynamic> properties) {
    _clientProperties[clientId] = properties;
    _logger.debug('Registered client: $clientId with properties: $properties');
  }

  // Unregister client
  void unregisterClient(String clientId) {
    _clientProperties.remove(clientId);
    _logger.debug('Unregistered client: $clientId');
  }

  // Find appropriate client for query
  String? routeQuery(String query, [Map<String, dynamic>? queryProperties]) {
    try {
      if (queryProperties == null || queryProperties.isEmpty) {
        return _routeByKeywordMatching(query);
      } else {
        return _routeByPropertyMatching(queryProperties);
      }
    } catch (e) {
      _logger.error('Error routing query: $e');
      return null;
    }
  }

  // Keyword-based routing
  String? _routeByKeywordMatching(String query) {
    final String normalizedQuery = query.toLowerCase();
    Map<String, double> clientScores = {};

    // Calculate score for all clients
    for (final entry in _clientProperties.entries) {
      final clientId = entry.key;
      final properties = entry.value;
      double score = 0.0;

      // Keyword matching
      if (properties.containsKey('keywords')) {
        final keywords = properties['keywords'] as List<dynamic>;
        for (final keywordObj in keywords) {
          final keyword = keywordObj.toString().toLowerCase();

          // Exact keyword match
          if (normalizedQuery.contains(keyword)) {
            // Score proportional to keyword length
            score += keyword.length / 2;

            // Bonus for exact word match
            final wordMatches =
                RegExp('\\b$keyword\\b').allMatches(normalizedQuery).length;
            score += wordMatches * 3;
          }
        }
      }

      // Domain matching
      if (properties.containsKey('domains')) {
        final domains = properties['domains'] as List<dynamic>;
        for (final domainObj in domains) {
          final domain = domainObj.toString().toLowerCase();
          if (normalizedQuery.contains(domain)) {
            score += 5.0; // High score for domain match
          }
        }
      }

      // Model capability matching
      if (properties.containsKey('capabilities')) {
        final capabilities = properties['capabilities'] as List<dynamic>;

        // Detect code generation queries
        if (normalizedQuery.contains('code') ||
            normalizedQuery.contains('function') ||
            normalizedQuery.contains('program')) {
          if (capabilities.contains('code_generation')) {
            score += 10.0;
          }
        }

        // Detect creative queries
        if (normalizedQuery.contains('creative') ||
            normalizedQuery.contains('story') ||
            normalizedQuery.contains('imagine')) {
          if (capabilities.contains('creative_writing')) {
            score += 8.0;
          }
        }

        // Detect math queries
        if (normalizedQuery.contains('calculate') ||
            normalizedQuery.contains('math') ||
            RegExp(r'\d+[\+\-\*\/\=]\d+').hasMatch(normalizedQuery)) {
          if (capabilities.contains('math')) {
            score += 12.0;
          }
        }
      }

      // Save score
      if (score > 0) {
        clientScores[clientId] = score;
      }
    }

    // Return highest scoring client
    if (clientScores.isNotEmpty) {
      final bestClient =
          clientScores.entries.reduce((a, b) => a.value > b.value ? a : b).key;

      _logger.debug(
          'Routed to client: $bestClient by keyword matching with query: $normalizedQuery');
      return bestClient;
    }

    return null;
  }

  // Property-based routing
  String? _routeByPropertyMatching(Map<String, dynamic> queryProperties) {
    // Calculate property matching scores
    Map<String, int> matchCounts = {};
    Map<String, double> matchScores = {};

    for (final clientEntry in _clientProperties.entries) {
      final clientId = clientEntry.key;
      final clientProps = clientEntry.value;

      int matches = 0;
      double score = 0.0;

      // Check matching for each query property
      for (final queryProp in queryProperties.entries) {
        final propName = queryProp.key;
        final propValue = queryProp.value;

        if (clientProps.containsKey(propName)) {
          final clientValue = clientProps[propName];

          // Exact value matching
          if (_isEqual(clientValue, propValue)) {
            matches += 2;
            score += 10.0;
          }
          // Value matching within list
          else if (clientValue is List &&
              clientValue.any((v) => _isEqual(v, propValue))) {
            matches += 1;
            score += 5.0;
          }
          // Substring matching
          else if (clientValue is String &&
              propValue is String &&
              clientValue.toLowerCase().contains(propValue.toLowerCase())) {
            matches += 1;
            score += 3.0;
          }
        }
      }

      // Add additional weight to priority properties
      if (queryProperties.containsKey('priority')) {
        final priority = queryProperties['priority'];
        if (clientProps.containsKey('priority') &&
            _isEqual(clientProps['priority'], priority)) {
          score *= 1.5;
        }
      }

      if (matches > 0) {
        matchCounts[clientId] = matches;
        matchScores[clientId] = score;
      }
    }

    // Return highest scoring client
    if (matchScores.isNotEmpty) {
      final bestClient =
          matchScores.entries.reduce((a, b) => a.value > b.value ? a : b).key;

      _logger.debug('Routed to client: $bestClient by property matching');
      return bestClient;
    }

    return null;
  }

  // Helper function for value comparison
  bool _isEqual(dynamic a, dynamic b) {
    // Use DeepCollectionEquality to compare complex objects
    return const DeepCollectionEquality().equals(a, b);
  }

  // Clear all
  void clear() {
    _clientProperties.clear();
    _logger.debug('Cleared all client properties');
  }

  // Get client properties
  Map<String, dynamic>? getClientProperties(String clientId) {
    return _clientProperties[clientId];
  }

  // Get all clients with specific property
  List<String> getClientsWithProperty(String property, [dynamic value]) {
    List<String> result = [];

    for (final entry in _clientProperties.entries) {
      final clientId = entry.key;
      final props = entry.value;

      if (props.containsKey(property)) {
        if (value == null || _isEqual(props[property], value)) {
          result.add(clientId);
        }
      }
    }

    return result;
  }
}
