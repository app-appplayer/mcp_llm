
import '../../mcp_llm.dart';
import 'llm_client_server_adapter.dart';
import 'managed_service.dart';

/// Manager for multiple LLM clients that implements the ServiceManager interface
class MultiLlmClientManager implements ServiceManager<LlmClientServiceAdapter> {
  final Map<String, LlmClientServiceAdapter> _clients = {};
  final ServiceRouter _router;
  final ServiceBalancer _loadBalancer;
  final Logger _logger = Logger('mcp_llm.multi_llm_client_manager');

  /// Create a new multi LLM client manager
  MultiLlmClientManager({
    ServiceRouter? router,
    ServiceBalancer? loadBalancer,
  }) :
        _router = router ?? DefaultServiceRouter(),
        _loadBalancer = loadBalancer ?? DefaultServiceBalancer();

  /// Add client with adapter
  void addClient(
      String clientId,
      LlmClient client, {
        Map<String, dynamic>? routingProperties,
        double weight = 1.0,
      }) {
    // Create adapter for the client
    final adapter = LlmClientServiceAdapter(client, clientId);
    addService(clientId, adapter, routingProperties: routingProperties, weight: weight);
  }

  @override
  void addService(
      String serviceId,
      LlmClientServiceAdapter service, {
        Map<String, dynamic>? routingProperties,
        double weight = 1.0,
      }) {
    _clients[serviceId] = service;

    if (routingProperties != null) {
      _router.registerService(serviceId, routingProperties);
    }

    _loadBalancer.registerService(serviceId, weight: weight);
    _logger.info('Added LLM client: $serviceId');
  }

  @override
  Future<void> removeService(String serviceId) async {
    final clientAdapter = _clients.remove(serviceId);
    if (clientAdapter != null) {
      await clientAdapter.disconnect();
      _router.unregisterService(serviceId);
      _loadBalancer.unregisterService(serviceId);
      _logger.info('Removed LLM client: $serviceId');
    }
  }

  @override
  LlmClientServiceAdapter? getService(String serviceId) {
    return _clients[serviceId];
  }

  /// Get the underlying LlmClient
  LlmClient? getClient(String clientId) {
    final adapter = _clients[clientId];
    return adapter?.client;
  }

  @override
  LlmClientServiceAdapter? selectService(String request, {Map<String, dynamic>? properties}) {
    // Route based on request characteristics
    String? clientId = _router.routeRequest(request, properties);

    // Use load balancer if no routing result
    if (clientId == null || !_clients.containsKey(clientId)) {
      clientId = _loadBalancer.getNextService();
    }

    return clientId != null ? _clients[clientId] : null;
  }

  /// Select the most appropriate client for a query
  LlmClient? selectClient(String query, {Map<String, dynamic>? properties}) {
    final adapter = selectService(query, properties: properties);
    return adapter?.client;
  }

  @override
  List<String> get serviceIds => _clients.keys.toList();

  @override
  int get serviceCount => _clients.length;

  /// Execute same operation on all clients (fan-out)
  Future<Map<String, LlmResponse>> fanOutQuery(
      String query, {
        bool enableTools = true,
        Map<String, dynamic> parameters = const {},
      }) async {
    final results = <String, LlmResponse>{};
    final futures = <Future<void>>[];

    for (final entry in _clients.entries) {
      futures.add(_executeClientQuery(
          entry.key, entry.value.client, query, enableTools, parameters)
          .then((response) {
        results[entry.key] = response;
      }));
    }

    await Future.wait(futures);
    return results;
  }

  // Helper method to execute individual client query
  Future<LlmResponse> _executeClientQuery(String clientId, LlmClient client,
      String query, bool enableTools, Map<String, dynamic> parameters) async {
    try {
      return await client.chat(
        query,
        enableTools: enableTools,
        parameters: parameters,
      );
    } catch (e) {
      _logger.error('Error in client $clientId: $e');
      return LlmResponse(
        text: 'Error from client $clientId: $e',
        metadata: {'error': e.toString(), 'clientId': clientId},
      );
    }
  }

  @override
  Future<void> closeAll() async {
    final futures = <Future<void>>[];
    for (final clientAdapter in _clients.values) {
      futures.add(clientAdapter.disconnect());
    }
    await Future.wait(futures);
    _clients.clear();
    _router.clear();
    _loadBalancer.clear();
  }
}