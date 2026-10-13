import '../utils/logger.dart';
import 'llm_client_adapter.dart';
import 'mcp_client_bridge.dart';
import '../health/health_monitor.dart';
import '../capabilities/capability_manager.dart';
import '../core/models.dart';

/// Several MCP clients behind one LLM client. Each is reached through an
/// [LlmClientAdapter] (typed through its [McpClientBridge]); a client that
/// needs authorization carries it itself (mcp_client's `McpOAuth`).
class McpClientManager {
  /// Map of MCP client IDs to their instances
  final Map<String, dynamic> _mcpClients = {};

  /// Map of MCP client IDs to their adapters
  final Map<String, LlmClientAdapter> _adapters = {};

  /// Default client ID to use when none specified
  String? _defaultClientId;

  /// Logger instance
  final Logger _logger = Logger('mcp_llm.mcp_client_manager');

  /// Health monitor for MCP health checking
  late final McpHealthMonitor _healthMonitor;

  /// Capability manager for MCP capability management
  late final McpCapabilityManager _capabilityManager;

  /// Create a new MCP client manager
  McpClientManager({
    dynamic defaultClient,
    String? defaultClientId,
    HealthCheckConfig? healthConfig,
  }) {
    // Initialize health monitor
    _healthMonitor =
        McpHealthMonitor(config: healthConfig ?? const HealthCheckConfig());

    // Initialize capability manager
    _capabilityManager = McpCapabilityManager();

    if (defaultClient != null) {
      final id = defaultClientId ?? 'default';
      addClient(id, defaultClient);
      _defaultClientId = id;
    }
  }

  /// Add a new MCP client
  void addClient(String clientId, dynamic mcpClient) {
    if (_mcpClients.containsKey(clientId)) {
      _logger.warning('Replacing existing MCP client with ID: $clientId');
    }

    _mcpClients[clientId] = mcpClient;
    _adapters[clientId] = LlmClientAdapter(mcpClient);

    // Register with health monitor
    _healthMonitor.registerClient(clientId, mcpClient);
    
    // Register with capability manager
    _capabilityManager.registerClient(clientId, mcpClient);

    // Set as default if this is the first client
    _defaultClientId ??= clientId;

    _logger.info('Added MCP client: $clientId');
  }

  /// Remove a client
  void removeClient(String clientId) {
    _mcpClients.remove(clientId);
    _adapters.remove(clientId);

    // Unregister from health monitor
    _healthMonitor.unregisterClient(clientId);
    
    // Unregister from capability manager
    _capabilityManager.unregisterClient(clientId);

    // Clear default if it was this client
    if (_defaultClientId == clientId) {
      _defaultClientId = _mcpClients.isNotEmpty ? _mcpClients.keys.first : null;
    }

    _logger.info('Removed MCP client: $clientId');
  }

  /// Set the default client
  void setDefaultClient(String clientId) {
    if (!_mcpClients.containsKey(clientId)) {
      throw StateError('Cannot set default: Client ID not found: $clientId');
    }

    _defaultClientId = clientId;
    _logger.info('Set default MCP client to: $clientId');
  }

  /// Get a client by ID
  dynamic getClient(String clientId) {
    return _mcpClients[clientId];
  }

  /// Get default client
  dynamic get defaultClient {
    if (_defaultClientId == null) {
      return null;
    }
    return _mcpClients[_defaultClientId];
  }

  /// Get an adapter by client ID
  LlmClientAdapter? getAdapter(String clientId) {
    return _adapters[clientId];
  }

  /// The typed operations of one client.
  McpClientBridge? getBridge(String clientId) => _adapters[clientId]?.bridge;

  /// Get default adapter
  LlmClientAdapter? get defaultAdapter {
    if (_defaultClientId == null) {
      return null;
    }
    return _adapters[_defaultClientId];
  }

  /// Get all client IDs
  List<String> get clientIds {
    return _mcpClients.keys.toList();
  }

  /// Get count of clients
  int get clientCount {
    return _mcpClients.length;
  }

  /// Get available tools from all clients or a specific client
  Future<List<Map<String, dynamic>>> getTools([String? clientId]) async {
    final allTools = <Map<String, dynamic>>[];

    // Get tools from specific client only
    if (clientId != null) {
      final adapter = _adapters[clientId];
      if (adapter == null) {
        _logger.warning('Client not found for getTools: $clientId');
        return [];
      }

      // One client asked for: its failure is the answer, not an empty list.
      final tools = await adapter.getTools();
      return tools.map((tool) => {...tool, 'clientId': clientId}).toList();
    }

    // Get tools from all clients
    for (final entry in _adapters.entries) {
      try {
        final clientTools = await entry.value.getTools();

        // Create a new map with clientId added
        final toolsWithClientId = clientTools.map((tool) =>
        {...tool, 'clientId': entry.key}
        ).toList();

        allTools.addAll(toolsWithClientId);
      } catch (e) {
        _logger.error('Error getting tools from client ${entry.key}: $e');
      }
    }

    return allTools;
  }

  /// Get available prompts from all clients or a specific client
  Future<List<Map<String, dynamic>>> getPrompts([String? clientId]) async {
    final allPrompts = <Map<String, dynamic>>[];

    // Get prompts from specific client only
    if (clientId != null) {
      final adapter = _adapters[clientId];
      if (adapter == null) {
        _logger.warning('Client not found for getPrompts: $clientId');
        return [];
      }

      // One client asked for: its failure is the answer, not an empty list.
      final prompts = await adapter.getPrompts();
      return prompts.map((prompt) => {...prompt, 'clientId': clientId}).toList();
    }

    // Get prompts from all clients
    for (final entry in _adapters.entries) {
      try {
        final clientPrompts = await entry.value.getPrompts();

        // Create a new map with clientId added
        final promptsWithClientId = clientPrompts.map((prompt) =>
        {...prompt, 'clientId': entry.key}
        ).toList();

        allPrompts.addAll(promptsWithClientId);
      } catch (e) {
        _logger.error('Error getting prompts from client ${entry.key}: $e');
      }
    }

    return allPrompts;
  }

  /// Get available resources from all clients or a specific client
  Future<List<Map<String, dynamic>>> getResources([String? clientId]) async {
    final allResources = <Map<String, dynamic>>[];

    // Get resources from specific client only
    if (clientId != null) {
      final adapter = _adapters[clientId];
      if (adapter == null) {
        _logger.warning('Client not found for getResources: $clientId');
        return [];
      }

      // One client asked for: its failure is the answer, not an empty list.
      final resources = await adapter.getResources();
      return resources.map((resource) => {...resource, 'clientId': clientId}).toList();
    }

    // Get resources from all clients
    for (final entry in _adapters.entries) {
      try {
        final clientResources = await entry.value.getResources();

        // Create a new map with clientId added
        final resourcesWithClientId = clientResources.map((resource) =>
        {...resource, 'clientId': entry.key}
        ).toList();

        allResources.addAll(resourcesWithClientId);
      } catch (e) {
        _logger.error('Error getting resources from client ${entry.key}: $e');
      }
    }

    return allResources;
  }

  /// Get prompts organized by client
  Future<Map<String, List<Map<String, dynamic>>>> getPromptsByClient() async {
    final result = <String, List<Map<String, dynamic>>>{};

    for (final entry in _adapters.entries) {
      try {
        final clientPrompts = await entry.value.getPrompts();
        result[entry.key] = clientPrompts;
      } catch (e) {
        _logger.error('Error getting prompts from client ${entry.key}: $e');
        result[entry.key] = [];
      }
    }

    return result;
  }

  /// Get resources organized by client
  Future<Map<String, List<Map<String, dynamic>>>> getResourcesByClient() async {
    final result = <String, List<Map<String, dynamic>>>{};

    for (final entry in _adapters.entries) {
      try {
        final clientResources = await entry.value.getResources();
        result[entry.key] = clientResources;
      } catch (e) {
        _logger.error('Error getting resources from client ${entry.key}: $e');
        result[entry.key] = [];
      }
    }

    return result;
  }

  /// Get tools organized by client
  Future<Map<String, List<Map<String, dynamic>>>> getToolsByClient() async {
    final result = <String, List<Map<String, dynamic>>>{};

    for (final entry in _adapters.entries) {
      try {
        final clientTools = await entry.value.getTools();
        result[entry.key] = clientTools;
      } catch (e) {
        _logger.error('Error getting tools from client ${entry.key}: $e');
        result[entry.key] = [];
      }
    }

    return result;
  }

  /// The clients to try for an operation, in order: [clientId] (or the
  /// default), then — with [tryAllClients] — every other one.
  List<MapEntry<String, LlmClientAdapter>> _route(String? clientId, bool tryAllClients) {
    final first = clientId ?? _defaultClientId;
    final order = <MapEntry<String, LlmClientAdapter>>[
      if (first != null && _adapters[first] != null) MapEntry(first, _adapters[first]!),
      if (tryAllClients)
        for (final e in _adapters.entries)
          if (e.key != first) e,
    ];
    if (clientId != null && _adapters[clientId] == null && !tryAllClients) {
      throw McpLayerException('', 'Client not found: $clientId');
    }
    return order;
  }

  /// Run [op] on the routed clients until one answers. A tool that reports
  /// `isError` has answered; only a failed exchange moves on.
  Future<T> _first<T>(String method, String? clientId, bool tryAllClients,
      Future<T> Function(LlmClientAdapter adapter) op) async {
    final order = _route(clientId, tryAllClients);
    if (order.isEmpty) throw McpLayerException(method, 'No MCP client to send it to');
    McpLayerException? last;
    for (final entry in order) {
      try {
        return await op(entry.value);
      } on McpLayerException catch (e) {
        _logger.warning('$method on client ${entry.key} failed: $e');
        last = e;
      }
    }
    throw last!;
  }

  /// `tools/call` on [clientId] (or the default client; with
  /// [tryAllClients], the others in turn), as protocol JSON.
  Future<dynamic> executeTool(
      String toolName,
      Map<String, dynamic> args, {
        String? clientId,
        bool tryAllClients = false,
      }) =>
      _first('tools/call', clientId, tryAllClients, (a) => a.executeTool(toolName, args));

  /// Execute a tool on all clients: client id → its result JSON, or the
  /// [McpLayerException] it failed with.
  Future<Map<String, dynamic>> executeToolOnAllClients(
      String toolName,
      Map<String, dynamic> args
      ) async {
    final results = <String, dynamic>{};
    final futures = <Future<void>>[];

    for (final entry in _adapters.entries) {
      futures.add(_executeToolSafe(entry.key, entry.value, toolName, args)
          .then((result) {
        results[entry.key] = result;
      }));
    }

    await Future.wait(futures);
    return results;
  }

  // One client's answer: its result JSON, or the McpLayerException it failed with.
  Future<dynamic> _executeToolSafe(
      String clientId,
      LlmClientAdapter adapter,
      String toolName,
      Map<String, dynamic> args
      ) async {
    try {
      return await adapter.executeTool(toolName, args);
    } on McpLayerException catch (e) {
      _logger.error('Error executing tool $toolName on client $clientId: $e');
      return e;
    }
  }

  /// Find all clients that have a specific tool
  Future<List<String>> findClientsWithTool(String toolName) async {
    final result = <String>[];
    final futures = <Future<void>>[];

    for (final entry in _adapters.entries) {
      futures.add(
          _hasToolSafe(entry.key, entry.value, toolName).then((hasTool) {
            if (hasTool) {
              result.add(entry.key);
            }
          })
      );
    }

    await Future.wait(futures);
    return result;
  }

  // Helper method to check if client has a tool
  Future<bool> _hasToolSafe(
      String clientId,
      LlmClientAdapter adapter,
      String toolName
      ) async {
    try {
      final tools = await adapter.getTools();
      return tools.any((tool) => tool['name'] == toolName);
    } catch (e) {
      _logger.warning('Error checking tool $toolName for client $clientId: $e');
      return false;
    }
  }

  /// `prompts/get`, routed like [executeTool], as protocol JSON.
  Future<Map<String, dynamic>> executePrompt(
      String promptName,
      Map<String, dynamic> args, {
        String? clientId,
        bool tryAllClients = false,
      }) =>
      _first('prompts/get', clientId, tryAllClients, (a) => a.executePrompt(promptName, args));

  /// `resources/read`, routed like [executeTool], as protocol JSON.
  Future<Map<String, dynamic>> readResource(
      String resourceUri, {
        String? clientId,
        bool tryAllClients = false,
      }) =>
      _first('resources/read', clientId, tryAllClients, (a) => a.readResource(resourceUri));

  // ===== Health and capabilities =====

  /// Perform health check on all or specific clients
  Future<HealthReport> performHealthCheck({
    List<String>? clientIds,
    bool includeSystemMetrics = true,
  }) {
    return _healthMonitor.performHealthCheck(
      clientIds: clientIds,
      includeSystemMetrics: includeSystemMetrics,
    );
  }

  /// Get health status for a specific client
  HealthCheckResult? getClientHealth(String clientId) {
    return _healthMonitor.getClientHealth(clientId);
  }

  /// Check if all clients are healthy
  bool get allClientsHealthy => _healthMonitor.allClientsHealthy;

  /// Get list of unhealthy clients
  List<String> get unhealthyClients => _healthMonitor.unhealthyClients;

  /// Get health statistics
  Map<String, dynamic> getHealthStatistics() {
    return _healthMonitor.getHealthStatistics();
  }

  /// Get capabilities for a specific client
  Map<String, McpCapability> getClientCapabilities(String clientId) {
    return _capabilityManager.getClientCapabilities(clientId);
  }

  /// Get all capabilities across all clients
  Map<String, Map<String, McpCapability>> getAllCapabilities() {
    return _capabilityManager.getAllCapabilities();
  }

  /// Update capabilities for a client
  Future<CapabilityUpdateResponse> updateCapabilities(CapabilityUpdateRequest request) {
    return _capabilityManager.updateCapabilities(request);
  }

  /// Get capability statistics
  Map<String, dynamic> getCapabilityStatistics() {
    return _capabilityManager.getCapabilityStatistics();
  }

  // JSON-RPC batch processing was removed in MCP 2025-06-18 (PR #416).
  // The previous `enableBatchProcessing` / `addBatchRequest` /
  // `getBatchStatistics` helpers are gone in 2.0; LLM-level fan-out (multi
  // request → multi response without batching on the wire) lives in
  // ParallelExecutor / MultiLlm.

  /// Release the health monitor and capability manager.
  void dispose() {
    // Dispose health monitor
    _healthMonitor.dispose();

    // Dispose capability manager
    _capabilityManager.dispose();

    _logger.info('Disposed MCP client managers');
  }
}
