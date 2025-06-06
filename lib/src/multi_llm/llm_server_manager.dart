
import '../../mcp_llm.dart';
import 'llm_client_server_adapter.dart';
import 'managed_service.dart';
/// Manager for multiple LLM servers that implements the ServiceManager interface
class MultiLlmServerManager implements ServiceManager<LlmServerServiceAdapter> {
  final Map<String, LlmServerServiceAdapter> _servers = {};
  final ServiceRouter _router;
  final ServiceBalancer _loadBalancer;
  final Logger _logger = Logger('mcp_llm.multi_llm_server_manager');

  /// Create a new multi LLM server manager
  MultiLlmServerManager({
    ServiceRouter? router,
    ServiceBalancer? loadBalancer,
  }) :
        _router = router ?? DefaultServiceRouter(),
        _loadBalancer = loadBalancer ?? DefaultServiceBalancer();

  /// Add server with adapter
  void addServer(
      String serverId,
      LlmServer server, {
        Map<String, dynamic>? routingProperties,
        double weight = 1.0,
      }) {
    // Create adapter for the server
    final adapter = LlmServerServiceAdapter(server, serverId);
    addService(serverId, adapter, routingProperties: routingProperties, weight: weight);
  }

  @override
  void addService(
      String serviceId,
      LlmServerServiceAdapter service, {
        Map<String, dynamic>? routingProperties,
        double weight = 1.0,
      }) {
    _servers[serviceId] = service;

    if (routingProperties != null) {
      _router.registerService(serviceId, routingProperties);
    }

    _loadBalancer.registerService(serviceId, weight: weight);
    _logger.info('Added LLM server: $serviceId');
  }

  @override
  Future<void> removeService(String serviceId) async {
    final serverAdapter = _servers.remove(serviceId);
    if (serverAdapter != null) {
      await serverAdapter.disconnect();
      _router.unregisterService(serviceId);
      _loadBalancer.unregisterService(serviceId);
      _logger.info('Removed LLM server: $serviceId');
    }
  }

  @override
  LlmServerServiceAdapter? getService(String serviceId) {
    return _servers[serviceId];
  }

  /// Get the underlying LlmServer
  LlmServer? getServer(String serverId) {
    final adapter = _servers[serverId];
    return adapter?.server;
  }

  @override
  LlmServerServiceAdapter? selectService(String request, {Map<String, dynamic>? properties}) {
    // Route based on request characteristics
    String? serverId = _router.routeRequest(request, properties);

    // Use load balancer if no routing result
    if (serverId == null || !_servers.containsKey(serverId)) {
      serverId = _loadBalancer.getNextService();
    }

    return serverId != null ? _servers[serverId] : null;
  }

  /// Select the most appropriate server for a query
  LlmServer? selectServer(String query, {Map<String, dynamic>? properties}) {
    final adapter = selectService(query, properties: properties);
    return adapter?.server;
  }

  @override
  List<String> get serviceIds => _servers.keys.toList();

  @override
  int get serviceCount => _servers.length;

  /// Process a query across multiple servers and aggregate results
  Future<Map<String, dynamic>> processQueryAcrossServers(
      String query, {
        bool useLocalTools = true,
        bool usePluginTools = true,
        Map<String, dynamic> parameters = const {},
        String sessionId = 'default',
        String? systemPrompt,
        bool sendToolResultsToLlm = true,
        List<String>? specificServerIds,
      }) async {
    final results = <String, dynamic>{};
    final futures = <Future<void>>[];

    // Determine which servers to use
    final targetServers = specificServerIds ?? serviceIds;

    // Process query on each server
    for (final serverId in targetServers) {
      final serverAdapter = _servers[serverId];
      if (serverAdapter == null) continue;
      final server = serverAdapter.server;

      futures.add(
          server.processQuery(
            query: query,
            useLocalTools: useLocalTools,
            usePluginTools: usePluginTools,
            parameters: parameters,
            sessionId: '$sessionId-$serverId', // Use unique session ID for each server
            systemPrompt: systemPrompt,
            sendToolResultsToLlm: sendToolResultsToLlm,
          ).then((response) {
            results[serverId] = response;
          }).catchError((e) {
            _logger.error('Error processing query on server $serverId: $e');
            results[serverId] = {'error': e.toString()};
          })
      );
    }

    await Future.wait(futures);
    return results;
  }

  @override
  Future<void> closeAll() async {
    final futures = <Future<void>>[];
    for (final serverAdapter in _servers.values) {
      futures.add(serverAdapter.disconnect());
    }
    await Future.wait(futures);
    _servers.clear();
    _router.clear();
    _loadBalancer.clear();
  }
}