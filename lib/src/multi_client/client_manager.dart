import '../../mcp_llm.dart';

/// Class for managing multiple MCP clients
class MultiClientManager {
  final Map<String, LlmClient> _clients = {};
  final ClientRouter _router = ClientRouter();
  final LoadBalancer _loadBalancer = LoadBalancer();
  final Logger _logger = Logger.getLogger('mcp_llm.client_manager');

  /// Add new client
  void addClient(
    String clientId,
    LlmClient client, {
    Map<String, dynamic>? routingProperties,
    double loadWeight = 1.0,
  }) {
    _clients[clientId] = client;

    if (routingProperties != null) {
      _router.registerClient(clientId, routingProperties);
    }

    _loadBalancer.registerClient(clientId, weight: loadWeight);
    _logger.info('Added client: $clientId');
  }

  /// Remove client
  Future<void> removeClient(String clientId) async {
    final client = _clients.remove(clientId);
    if (client != null) {
      await client.close();
      _router.unregisterClient(clientId);
      _loadBalancer.unregisterClient(clientId);
      _logger.info('Removed client: $clientId');
    }
  }

  LlmClient? getClient(String clientId) {
    return _clients[clientId];
  }

  /// Select the most appropriate client for the query
  LlmClient? selectClient(String query, {Map<String, dynamic>? properties}) {
    // Route based on query characteristics
    String? clientId = _router.routeQuery(query, properties);

    // Use load balancer if no routing result
    if (clientId == null || !_clients.containsKey(clientId)) {
      clientId = _loadBalancer.getNextClient();
    }

    return clientId != null ? _clients[clientId] : null;
  }

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
              entry.key, entry.value, query, enableTools, parameters)
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

  /// Close all clients
  Future<void> closeAll() async {
    final futures = <Future<void>>[];
    for (final client in _clients.values) {
      futures.add(client.close());
    }
    await Future.wait(futures);
    _clients.clear();
    _router.clear();
    _loadBalancer.clear();
  }
}
