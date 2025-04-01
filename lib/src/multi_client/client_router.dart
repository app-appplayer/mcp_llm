import 'package:collection/collection.dart';
import '../utils/logger.dart';

/// Routing strategy options
enum RoutingStrategy {
  simple,        // Basic keyword matching
  weighted,      // Score-based routing with weights
  propertyBased, // Specific property matching
  adaptive       // Dynamic strategy based on query
}

/// Class that routes to appropriate clients based on queries
class ClientRouter {
  // Client properties map
  final Map<String, Map<String, dynamic>> _clientProperties = {};

  // Current routing strategy
  RoutingStrategy _routingStrategy = RoutingStrategy.weighted;

  // Logger instance
  final Logger _logger = Logger.getLogger('mcp_llm.client_router');

  /// Create a new client router
  ClientRouter({
    RoutingStrategy strategy = RoutingStrategy.weighted
  }) : _routingStrategy = strategy;

  /// Register client with routing properties
  void registerClient(String clientId, Map<String, dynamic> properties) {
    _clientProperties[clientId] = properties;
    _logger.debug('Registered client: $clientId with properties: $properties');
  }

  /// Unregister client
  void unregisterClient(String clientId) {
    _clientProperties.remove(clientId);
    _logger.debug('Unregistered client: $clientId');
  }

  /// Find appropriate client for query
  String? routeQuery(String query, [Map<String, dynamic>? queryProperties]) {
    try {
      switch(_routingStrategy) {
        case RoutingStrategy.simple:
          return _simpleRouting(query);
        case RoutingStrategy.weighted:
          return _weightedRouting(query, queryProperties);
        case RoutingStrategy.propertyBased:
          return queryProperties != null
              ? _propertyBasedRouting(queryProperties)
              : _weightedRouting(query, null);
        case RoutingStrategy.adaptive:
        // Choose best strategy based on the query and properties
          if (queryProperties != null && queryProperties.isNotEmpty) {
            return _propertyBasedRouting(queryProperties);
          } else {
            return _weightedRouting(query, null);
          }
      }
    } catch (e) {
      _logger.error('Error routing query: $e');
      return null;
    }
  }

  /// Set routing strategy
  void setRoutingStrategy(RoutingStrategy strategy) {
    _routingStrategy = strategy;
    _logger.info('Client router strategy set to: ${strategy.name}');
  }

  /// Simple keyword-based routing (original implementation)
  String? _simpleRouting(String query) {
    final queryLower = query.toLowerCase();

    // Simple keyword-based routing
    for (final entry in _clientProperties.entries) {
      final keywords = entry.value['keywords'] as List<dynamic>?;
      if (keywords != null &&
          keywords.any((keyword) =>
              queryLower.contains(keyword.toString().toLowerCase()))) {
        return entry.key;
      }
    }
    return null;
  }

  /// Advanced weighted routing
  String? _weightedRouting(String query, Map<String, dynamic>? queryProperties) {
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

      // Additional scoring from query properties if available
      if (queryProperties != null) {
        for (final propEntry in queryProperties.entries) {
          final propName = propEntry.key;
          final propValue = propEntry.value;

          if (properties.containsKey(propName)) {
            final clientValue = properties[propName];

            // Exact match
            if (_isEqual(clientValue, propValue)) {
              score += 8.0;
            }
            // Match within list
            else if (clientValue is List &&
                clientValue.any((v) => _isEqual(v, propValue))) {
              score += 4.0;
            }
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

      _logger.debug('Routed to client: $bestClient with score: ${clientScores[bestClient]}');
      return bestClient;
    }

    return null;
  }

  /// Property-based routing
  String? _propertyBasedRouting(Map<String, dynamic> queryProperties) {
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

  /// Get client properties
  Map<String, dynamic>? getClientProperties(String clientId) {
    return _clientProperties[clientId];
  }

  /// Get all clients with specific property
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

  /// Helper function for value comparison
  bool _isEqual(dynamic a, dynamic b) {
    // Use DeepCollectionEquality to compare complex objects
    return const DeepCollectionEquality().equals(a, b);
  }

  /// Clear all registered clients
  void clear() {
    _clientProperties.clear();
    _logger.debug('Cleared all client properties');
  }
}