
import '../../mcp_llm.dart';
import 'managed_service.dart';

/// Default implementation of ServiceRouter
class DefaultServiceRouter implements ServiceRouter {
  final Map<String, Map<String, dynamic>> _serviceProperties = {};
  RoutingStrategy _routingStrategy = RoutingStrategy.weighted;
  final Logger _logger = Logger('mcp_llm.default_service_router');

  @override
  void registerService(String serviceId, Map<String, dynamic> properties) {
    _serviceProperties[serviceId] = properties;
    _logger.debug('Registered service: $serviceId with properties: $properties');
  }

  @override
  void unregisterService(String serviceId) {
    _serviceProperties.remove(serviceId);
    _logger.debug('Unregistered service: $serviceId');
  }

  @override
  String? routeRequest(String request, [Map<String, dynamic>? requestProperties]) {
    try {
      switch(_routingStrategy) {
        case RoutingStrategy.simple:
          return _simpleRouting(request);
        case RoutingStrategy.weighted:
          return _weightedRouting(request, requestProperties);
        case RoutingStrategy.propertyBased:
          return requestProperties != null
              ? _propertyBasedRouting(requestProperties)
              : _weightedRouting(request, null);
        case RoutingStrategy.adaptive:
          if (requestProperties != null && requestProperties.isNotEmpty) {
            return _propertyBasedRouting(requestProperties);
          } else {
            return _weightedRouting(request, null);
          }
      }
    } catch (e) {
      _logger.error('Error routing request: $e');
      return null;
    }
  }

  @override
  void setRoutingStrategy(RoutingStrategy strategy) {
    _routingStrategy = strategy;
    _logger.info('Service router strategy set to: ${strategy.name}');
  }

  @override
  Map<String, dynamic>? getServiceProperties(String serviceId) {
    return _serviceProperties[serviceId];
  }

  @override
  List<String> getServicesWithProperty(String property, [dynamic value]) {
    List<String> result = [];

    for (final entry in _serviceProperties.entries) {
      final serviceId = entry.key;
      final props = entry.value;

      if (props.containsKey(property)) {
        if (value == null || props[property] == value) {
          result.add(serviceId);
        }
      }
    }

    return result;
  }

  @override
  void clear() {
    _serviceProperties.clear();
    _logger.debug('Cleared all service properties');
  }

  // Simple keyword-based routing
  String? _simpleRouting(String request) {
    final requestLower = request.toLowerCase();

    for (final entry in _serviceProperties.entries) {
      final keywords = entry.value['keywords'] as List<dynamic>?;
      if (keywords != null &&
          keywords.any((keyword) =>
              requestLower.contains(keyword.toString().toLowerCase()))) {
        return entry.key;
      }
    }
    return null;
  }

  // Weighted routing based on multiple factors
  String? _weightedRouting(String request, Map<String, dynamic>? requestProperties) {
    final String normalizedRequest = request.toLowerCase();
    Map<String, double> serviceScores = {};

    for (final entry in _serviceProperties.entries) {
      final serviceId = entry.key;
      final properties = entry.value;
      double score = 0.0;

      // Keyword matching
      if (properties.containsKey('keywords')) {
        final keywords = properties['keywords'] as List<dynamic>;
        for (final keywordObj in keywords) {
          final keyword = keywordObj.toString().toLowerCase();
          if (normalizedRequest.contains(keyword)) {
            score += keyword.length / 2;
          }
        }
      }

      // Domain matching
      if (properties.containsKey('domains')) {
        final domains = properties['domains'] as List<dynamic>;
        for (final domainObj in domains) {
          final domain = domainObj.toString().toLowerCase();
          if (normalizedRequest.contains(domain)) {
            score += 5.0;
          }
        }
      }

      // Additional scoring from request properties if available
      if (requestProperties != null) {
        for (final propEntry in requestProperties.entries) {
          final propName = propEntry.key;
          final propValue = propEntry.value;

          if (properties.containsKey(propName)) {
            final serviceValue = properties[propName];
            if (serviceValue == propValue) {
              score += 8.0;
            }
          }
        }
      }

      // Save score
      if (score > 0) {
        serviceScores[serviceId] = score;
      }
    }

    // Return highest scoring service
    if (serviceScores.isNotEmpty) {
      final bestService = serviceScores.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      return bestService;
    }

    return null;
  }

  // Property-based routing
  String? _propertyBasedRouting(Map<String, dynamic> requestProperties) {
    Map<String, int> matchCounts = {};
    Map<String, double> matchScores = {};

    for (final serviceEntry in _serviceProperties.entries) {
      final serviceId = serviceEntry.key;
      final serviceProps = serviceEntry.value;

      int matches = 0;
      double score = 0.0;

      for (final requestProp in requestProperties.entries) {
        final propName = requestProp.key;
        final propValue = requestProp.value;

        if (serviceProps.containsKey(propName)) {
          final serviceValue = serviceProps[propName];

          // Exact value matching
          if (serviceValue == propValue) {
            matches += 2;
            score += 10.0;
          }
        }
      }

      if (matches > 0) {
        matchCounts[serviceId] = matches;
        matchScores[serviceId] = score;
      }
    }

    // Return highest scoring service
    if (matchScores.isNotEmpty) {
      final bestService = matchScores.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      return bestService;
    }

    return null;
  }
}