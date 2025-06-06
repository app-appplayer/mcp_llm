import '../utils/logger.dart';
import 'llm_client_adapter.dart';
import 'mcp_auth_adapter.dart';
import '../health/health_monitor.dart';
import '../capabilities/capability_manager.dart';
import '../batch/batch_request_manager.dart';
import '../core/models.dart';

/// Manages multiple MCP clients for a single LLM client with OAuth 2.1 support (2025-03-26)
class McpClientManager {
  /// Map of MCP client IDs to their instances
  final Map<String, dynamic> _mcpClients = {};

  /// Map of MCP client IDs to their adapters
  final Map<String, LlmClientAdapter> _adapters = {};

  /// Map of MCP client IDs to their auth adapters
  final Map<String, McpAuthAdapter> _authAdapters = {};

  /// Default client ID to use when none specified
  String? _defaultClientId;

  /// Logger instance
  final Logger _logger = Logger('mcp_llm.mcp_client_manager');

  /// Health monitor for 2025-03-26 MCP health checking
  late final McpHealthMonitor _healthMonitor;

  /// Capability manager for 2025-03-26 MCP capability management
  late final McpCapabilityManager _capabilityManager;

  /// Batch request manager for 2025-03-26 JSON-RPC 2.0 optimization
  BatchRequestManager? _batchManager;

  /// Create a new MCP client manager
  McpClientManager({
    dynamic defaultClient, 
    String? defaultClientId,
    HealthCheckConfig? healthConfig,
    BatchConfig? batchConfig,
    bool enableBatchProcessing = false,
  }) {
    // Initialize health monitor
    _healthMonitor = McpHealthMonitor(config: healthConfig ?? const HealthCheckConfig());
    
    // Initialize capability manager
    _capabilityManager = McpCapabilityManager();
    
    // Initialize batch manager if enabled
    if (enableBatchProcessing) {
      _batchManager = BatchRequestManager(config: batchConfig ?? const BatchConfig());
    }
    
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
    
    // Register with batch manager if enabled
    _batchManager?.registerClient(clientId, mcpClient);

    // Set as default if this is the first client
    _defaultClientId ??= clientId;

    _logger.info('Added MCP client: $clientId with 2025-03-26 features');
  }

  /// Add a new MCP client with OAuth 2.1 authentication (2025-03-26)
  Future<void> addClientWithAuth(String clientId, dynamic mcpClient, {
    AuthConfig? authConfig,
    TokenValidator? tokenValidator,
  }) async {
    if (_mcpClients.containsKey(clientId)) {
      _logger.warning('Replacing existing MCP client with ID: $clientId');
    }

    // Create OAuth auth adapter
    final authAdapter = McpAuthAdapter(
      tokenValidator: tokenValidator,
      defaultConfig: authConfig ?? const AuthConfig(),
    );
    
    _mcpClients[clientId] = mcpClient;
    _authAdapters[clientId] = authAdapter;
    _adapters[clientId] = LlmClientAdapter(
      mcpClient,
      authAdapter: authAdapter,
      clientId: clientId,
    );

    // Register with health monitor
    _healthMonitor.registerClient(clientId, mcpClient);
    
    // Register with capability manager with auth adapter
    _capabilityManager.registerClient(clientId, mcpClient, authAdapter: authAdapter);
    
    // Register with batch manager if enabled
    _batchManager?.registerClient(clientId, mcpClient, authAdapter: authAdapter);

    // Set as default if this is the first client
    _defaultClientId ??= clientId;

    _logger.info('Added MCP client with OAuth 2.1 authentication: $clientId with 2025-03-26 features');

    // Attempt automatic authentication
    try {
      final authResult = await authAdapter.authenticate(clientId, mcpClient, config: authConfig);
      if (authResult.isAuthenticated) {
        _logger.info('OAuth 2.1 authentication successful for client: $clientId');
      } else {
        _logger.warning('OAuth 2.1 authentication failed for client $clientId: ${authResult.error}');
      }
    } catch (e) {
      _logger.error('OAuth 2.1 authentication error for client $clientId: $e');
    }
  }

  /// Remove a client
  void removeClient(String clientId) {
    _mcpClients.remove(clientId);
    _adapters.remove(clientId);
    
    // Remove OAuth authentication if exists
    final authAdapter = _authAdapters.remove(clientId);
    if (authAdapter != null) {
      authAdapter.removeAuth(clientId);
      _logger.info('Removed OAuth 2.1 authentication for client: $clientId');
    }

    // Unregister from health monitor
    _healthMonitor.unregisterClient(clientId);
    
    // Unregister from capability manager
    _capabilityManager.unregisterClient(clientId);
    
    // Unregister from batch manager if enabled
    _batchManager?.unregisterClient(clientId);

    // Clear default if it was this client
    if (_defaultClientId == clientId) {
      _defaultClientId = _mcpClients.isNotEmpty ? _mcpClients.keys.first : null;
    }

    _logger.info('Removed MCP client: $clientId from all 2025-03-26 managers');
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

      try {
        final tools = await adapter.getTools();
        return tools.map((tool) => {...tool, 'clientId': clientId}).toList();
      } catch (e) {
        _logger.error('Error getting tools from client $clientId: $e');
        return [];
      }
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

      try {
        final prompts = await adapter.getPrompts();
        return prompts.map((prompt) => {...prompt, 'clientId': clientId}).toList();
      } catch (e) {
        _logger.error('Error getting prompts from client $clientId: $e');
        return [];
      }
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

      try {
        final resources = await adapter.getResources();
        return resources.map((resource) => {...resource, 'clientId': clientId}).toList();
      } catch (e) {
        _logger.error('Error getting resources from client $clientId: $e');
        return [];
      }
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

  /// Execute a tool on a specific client or try all clients
  Future<dynamic> executeTool(
      String toolName,
      Map<String, dynamic> args, {
        String? clientId,
        bool tryAllClients = false,
      }) async {
    // Try a specific client if provided
    if (clientId != null) {
      final adapter = _adapters[clientId];
      if (adapter == null) {
        if (!tryAllClients) {
          throw Exception('Client not found: $clientId');
        }
      } else {
        try {
          final result = await adapter.executeTool(toolName, args);
          if (!result.containsKey('error')) {
            return result;
          }
          if (!tryAllClients) {
            return result; // Return result even with error if not trying all clients
          }
        } catch (e) {
          _logger.warning('Error executing tool $toolName on client $clientId: $e');
          if (!tryAllClients) {
            throw Exception('Tool execution failed on specified client: $e');
          }
        }
      }
    }

    // Try default client if no specific client or default client wasn't already tried
    if (clientId == null && _defaultClientId != null && _defaultClientId != clientId) {
      final adapter = _adapters[_defaultClientId!];
      if (adapter != null) {
        try {
          final result = await adapter.executeTool(toolName, args);
          if (!result.containsKey('error')) {
            return result;
          }
          if (!tryAllClients) {
            return result;
          }
        } catch (e) {
          _logger.warning('Error executing tool $toolName on default client: $e');
          if (!tryAllClients) {
            throw Exception('Tool execution failed on default client: $e');
          }
        }
      }
    }

    // If tryAllClients is true, try all other clients
    if (tryAllClients) {
      Exception? lastError;

      for (final entry in _adapters.entries) {
        // Skip already tried clients
        if (entry.key == clientId || entry.key == _defaultClientId) {
          continue;
        }

        try {
          final result = await entry.value.executeTool(toolName, args);
          if (!result.containsKey('error')) {
            _logger.debug('Successfully executed tool $toolName on client ${entry.key}');
            return result;
          }
        } catch (e) {
          _logger.warning('Error executing tool $toolName on client ${entry.key}: $e');
          lastError = Exception('Failed on client ${entry.key}: $e');
        }
      }

      // If we got here, all clients failed
      if (lastError != null) {
        throw lastError;
      }
    }

    throw Exception('Tool $toolName not found or execution failed');
  }

  /// Execute a tool on all clients and collect results
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

  // Helper method to safely execute tool
  Future<dynamic> _executeToolSafe(
      String clientId,
      LlmClientAdapter adapter,
      String toolName,
      Map<String, dynamic> args
      ) async {
    try {
      return await adapter.executeTool(toolName, args);
    } catch (e) {
      _logger.error('Error executing tool $toolName on client $clientId: $e');
      return {'error': e.toString()};
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

  /// Execute a prompt using MCP clients
  Future<Map<String, dynamic>> executePrompt(
      String promptName,
      Map<String, dynamic> args, {
        String? clientId,
        bool tryAllClients = false,
      }) async {
    // Try a specific client if provided
    if (clientId != null) {
      final adapter = _adapters[clientId];
      if (adapter == null) {
        if (!tryAllClients) {
          throw Exception('Client not found: $clientId');
        }
      } else {
        try {
          final result = await adapter.executePrompt(promptName, args);
          if (!result.containsKey('error')) {
            return result;
          }
          if (!tryAllClients) {
            return result; // Return result even with error if not trying all clients
          }
        } catch (e) {
          _logger.warning('Error executing prompt $promptName on client $clientId: $e');
          if (!tryAllClients) {
            throw Exception('Prompt execution failed on specified client: $e');
          }
        }
      }
    }

    // Try default client if no specific client or default client wasn't already tried
    if (clientId == null && _defaultClientId != null && _defaultClientId != clientId) {
      final adapter = _adapters[_defaultClientId!];
      if (adapter != null) {
        try {
          final result = await adapter.executePrompt(promptName, args);
          if (!result.containsKey('error')) {
            return result;
          }
          if (!tryAllClients) {
            return result;
          }
        } catch (e) {
          _logger.warning('Error executing prompt $promptName on default client: $e');
          if (!tryAllClients) {
            throw Exception('Prompt execution failed on default client: $e');
          }
        }
      }
    }

    // If tryAllClients is true, try all other clients
    if (tryAllClients) {
      Exception? lastError;

      for (final entry in _adapters.entries) {
        // Skip already tried clients
        if (entry.key == clientId || entry.key == _defaultClientId) {
          continue;
        }

        try {
          final result = await entry.value.executePrompt(promptName, args);
          if (!result.containsKey('error')) {
            _logger.debug('Successfully executed prompt $promptName on client ${entry.key}');
            return result;
          }
        } catch (e) {
          _logger.warning('Error executing prompt $promptName on client ${entry.key}: $e');
          lastError = Exception('Failed on client ${entry.key}: $e');
        }
      }

      // If we got here, all clients failed
      if (lastError != null) {
        throw lastError;
      }
    }

    throw Exception('Prompt $promptName not found or execution failed');
  }

  /// Read a resource using MCP clients
  Future<Map<String, dynamic>> readResource(
      String resourceUri, {
        String? clientId,
        bool tryAllClients = false,
      }) async {
    // Try a specific client if provided
    if (clientId != null) {
      final adapter = _adapters[clientId];
      if (adapter == null) {
        if (!tryAllClients) {
          throw Exception('Client not found: $clientId');
        }
      } else {
        try {
          final result = await adapter.readResource(resourceUri);
          if (!result.containsKey('error')) {
            return result;
          }
          if (!tryAllClients) {
            return result; // Return result even with error if not trying all clients
          }
        } catch (e) {
          _logger.warning('Error reading resource $resourceUri on client $clientId: $e');
          if (!tryAllClients) {
            throw Exception('Resource reading failed on specified client: $e');
          }
        }
      }
    }

    // Try default client if no specific client or default client wasn't already tried
    if (clientId == null && _defaultClientId != null && _defaultClientId != clientId) {
      final adapter = _adapters[_defaultClientId!];
      if (adapter != null) {
        try {
          final result = await adapter.readResource(resourceUri);
          if (!result.containsKey('error')) {
            return result;
          }
          if (!tryAllClients) {
            return result;
          }
        } catch (e) {
          _logger.warning('Error reading resource $resourceUri on default client: $e');
          if (!tryAllClients) {
            throw Exception('Resource reading failed on default client: $e');
          }
        }
      }
    }

    // If tryAllClients is true, try all other clients
    if (tryAllClients) {
      Exception? lastError;

      for (final entry in _adapters.entries) {
        // Skip already tried clients
        if (entry.key == clientId || entry.key == _defaultClientId) {
          continue;
        }

        try {
          final result = await entry.value.readResource(resourceUri);
          if (!result.containsKey('error')) {
            _logger.debug('Successfully read resource ${entry.key}');
            return result;
          }
        } catch (e) {
          _logger.warning('Error read resource ${entry.key}: $e');
          lastError = Exception('Failed on client ${entry.key}: $e');
        }
      }

      // If we got here, all clients failed
      if (lastError != null) {
        throw lastError;
      }
    }

    throw Exception('Resource $resourceUri not found or reading failed');
  }

  /// Ensure OAuth 2.1 authentication for a specific client
  Future<bool> ensureAuthenticated(String clientId) async {
    final authAdapter = _authAdapters[clientId];
    if (authAdapter == null) {
      // No authentication required
      return true;
    }

    if (!authAdapter.hasValidAuth(clientId)) {
      _logger.info('Re-authenticating client with OAuth 2.1: $clientId');
      final mcpClient = _mcpClients[clientId];
      if (mcpClient != null) {
        final result = await authAdapter.authenticate(clientId, mcpClient);
        return result.isAuthenticated;
      }
      return false;
    }

    return true;
  }

  /// Refresh OAuth 2.1 tokens for all clients
  Future<void> refreshAllTokens() async {
    final refreshTasks = <Future<void>>[];
    
    for (final entry in _authAdapters.entries) {
      final clientId = entry.key;
      final authAdapter = entry.value;
      
      if (authAdapter.hasValidAuth(clientId)) {
        final context = authAdapter.getAuthContext(clientId);
        if (context?.needsRefresh == true) {
          refreshTasks.add(authAdapter.refreshToken(clientId));
        }
      }
    }
    
    if (refreshTasks.isNotEmpty) {
      _logger.info('Refreshing OAuth 2.1 tokens for ${refreshTasks.length} clients');
      await Future.wait(refreshTasks);
    }
  }

  /// Get OAuth 2.1 authentication status for all clients
  Map<String, Map<String, dynamic>> getAuthStatus() {
    final result = <String, Map<String, dynamic>>{};
    
    for (final clientId in _mcpClients.keys) {
      final adapter = _adapters[clientId];
      if (adapter != null) {
        result[clientId] = adapter.getAuthStatus();
      }
    }
    
    return result;
  }

  /// Check OAuth 2.1 compliance for all clients
  Future<Map<String, bool>> checkOAuth21Compliance() async {
    final result = <String, bool>{};
    final futures = <Future<void>>[];
    
    for (final entry in _adapters.entries) {
      final clientId = entry.key;
      final adapter = entry.value;
      
      futures.add(
        adapter.checkOAuth21Compliance().then((isCompliant) {
          result[clientId] = isCompliant;
        }).catchError((e) {
          _logger.error('OAuth 2.1 compliance check failed for client $clientId: $e');
          result[clientId] = false;
        })
      );
    }
    
    await Future.wait(futures);
    return result;
  }

  /// Get clients that require OAuth 2.1 authentication
  List<String> get authenticatedClients {
    return _authAdapters.keys.toList();
  }

  /// Get clients that do not require authentication
  List<String> get unauthenticatedClients {
    return _mcpClients.keys
        .where((clientId) => !_authAdapters.containsKey(clientId))
        .toList();
  }

  /// Enable OAuth 2.1 authentication for an existing client
  Future<bool> enableAuthenticationForClient(String clientId, {
    AuthConfig? authConfig,
    TokenValidator? tokenValidator,
  }) async {
    final mcpClient = _mcpClients[clientId];
    if (mcpClient == null) {
      _logger.error('Client not found for enabling authentication: $clientId');
      return false;
    }

    if (_authAdapters.containsKey(clientId)) {
      _logger.warning('Authentication already enabled for client: $clientId');
      return true;
    }

    try {
      // Create OAuth auth adapter
      final authAdapter = McpAuthAdapter(
        tokenValidator: tokenValidator,
        defaultConfig: authConfig ?? const AuthConfig(),
      );
      
      _authAdapters[clientId] = authAdapter;
      
      // Update adapter with authentication
      _adapters[clientId] = LlmClientAdapter(
        mcpClient,
        authAdapter: authAdapter,
        clientId: clientId,
      );

      // Attempt authentication
      final authResult = await authAdapter.authenticate(clientId, mcpClient, config: authConfig);
      if (authResult.isAuthenticated) {
        _logger.info('OAuth 2.1 authentication enabled and successful for client: $clientId');
        return true;
      } else {
        _logger.warning('OAuth 2.1 authentication enabled but failed for client $clientId: ${authResult.error}');
        return false;
      }
    } catch (e) {
      _logger.error('Failed to enable OAuth 2.1 authentication for client $clientId: $e');
      return false;
    }
  }

  /// Disable OAuth 2.1 authentication for a client
  void disableAuthenticationForClient(String clientId) {
    final authAdapter = _authAdapters.remove(clientId);
    if (authAdapter != null) {
      authAdapter.removeAuth(clientId);
      
      // Update adapter without authentication
      final mcpClient = _mcpClients[clientId];
      if (mcpClient != null) {
        _adapters[clientId] = LlmClientAdapter(mcpClient);
      }
      
      _logger.info('OAuth 2.1 authentication disabled for client: $clientId');
    } else {
      _logger.warning('Authentication was not enabled for client: $clientId');
    }
  }

  /// Get summary of OAuth 2.1 authentication status
  Map<String, dynamic> getAuthSummary() {
    final authenticated = authenticatedClients;
    final unauthenticated = unauthenticatedClients;
    final total = _mcpClients.length;
    
    return {
      'total_clients': total,
      'authenticated_clients': authenticated.length,
      'unauthenticated_clients': unauthenticated.length,
      'authentication_coverage': total > 0 ? (authenticated.length / total * 100).round() : 0,
      'protocol_version': '2025-03-26',
      'oauth_version': '2.1',
    };
  }

  // ===== 2025-03-26 MCP Feature Methods =====

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

  /// Enable batch processing
  void enableBatchProcessing({BatchConfig? config}) {
    if (_batchManager == null) {
      _batchManager = BatchRequestManager(config: config ?? const BatchConfig());
      
      // Register existing clients with batch manager
      for (final entry in _mcpClients.entries) {
        final authAdapter = _authAdapters[entry.key];
        _batchManager!.registerClient(entry.key, entry.value, authAdapter: authAdapter);
      }
      
      _logger.info('Enabled JSON-RPC 2.0 batch processing with ${_mcpClients.length} clients');
    }
  }

  /// Disable batch processing
  void disableBatchProcessing() {
    _batchManager?.dispose();
    _batchManager = null;
    _logger.info('Disabled JSON-RPC 2.0 batch processing');
  }

  /// Check if batch processing is enabled
  bool get isBatchProcessingEnabled => _batchManager != null;

  /// Add request to batch queue
  Future<Map<String, dynamic>> addBatchRequest(
    String method,
    Map<String, dynamic> params, {
    String? clientId,
    bool forceImmediate = false,
  }) {
    if (_batchManager == null) {
      throw StateError('Batch processing is not enabled. Call enableBatchProcessing() first.');
    }
    
    return _batchManager!.addRequest(
      method,
      params,
      clientId: clientId,
      forceImmediate: forceImmediate,
    );
  }

  /// Get batch processing statistics
  Map<String, dynamic> getBatchStatistics() {
    return _batchManager?.getStatistics() ?? {
      'enabled': false,
      'message': 'Batch processing is not enabled',
    };
  }

  /// Cleanup all OAuth 2.1 resources and 2025-03-26 managers
  void dispose() {
    // Dispose auth adapters
    for (final authAdapter in _authAdapters.values) {
      authAdapter.dispose();
    }
    _authAdapters.clear();
    
    // Dispose health monitor
    _healthMonitor.dispose();
    
    // Dispose capability manager
    _capabilityManager.dispose();
    
    // Dispose batch manager if enabled
    _batchManager?.dispose();
    
    _logger.info('Disposed all OAuth 2.1 authentication adapters and 2025-03-26 managers');
  }
}
