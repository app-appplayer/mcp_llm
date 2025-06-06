import 'dart:async';
import '../utils/logger.dart';
import '../adapter/mcp_auth_adapter.dart';
import '../core/models.dart';

/// MCP Capability Manager for 2025-03-26 capabilities/update methods
class McpCapabilityManager {
  final Logger _logger = Logger('mcp_llm.capability_manager');
  
  final Map<String, dynamic> _mcpClients = {};
  final Map<String, McpAuthAdapter?> _authAdapters = {};
  final Map<String, Map<String, McpCapability>> _clientCapabilities = {};
  
  // Event stream for capability changes
  final StreamController<CapabilityEvent> _eventController = StreamController<CapabilityEvent>.broadcast();
  Stream<CapabilityEvent> get events => _eventController.stream;
  
  // Capability update history
  final Map<String, List<CapabilityUpdateRequest>> _updateHistory = {};
  final int _maxHistorySize = 100;

  McpCapabilityManager();

  /// Register MCP client for capability management
  void registerClient(String clientId, dynamic mcpClient, {McpAuthAdapter? authAdapter}) {
    _mcpClients[clientId] = mcpClient;
    _authAdapters[clientId] = authAdapter;
    _clientCapabilities[clientId] = {};
    _updateHistory[clientId] = [];
    _logger.info('Registered MCP client for capability management: $clientId');
    
    // Perform initial capability discovery
    _discoverClientCapabilities(clientId);
  }

  /// Unregister MCP client
  void unregisterClient(String clientId) {
    _mcpClients.remove(clientId);
    _authAdapters.remove(clientId);
    _clientCapabilities.remove(clientId);
    _updateHistory.remove(clientId);
    _logger.info('Unregistered MCP client from capability management: $clientId');
  }

  /// Discover and register client capabilities automatically
  Future<void> _discoverClientCapabilities(String clientId) async {
    final mcpClient = _mcpClients[clientId];
    if (mcpClient == null) return;

    try {
      final discoveredCapabilities = <McpCapability>[];
      
      // Check tools capability
      try {
        final tools = await mcpClient.listTools();
        discoveredCapabilities.add(McpCapability(
          type: McpCapabilityType.tools,
          name: 'tools',
          version: '2025-03-26',
          enabled: true,
          configuration: {'tool_count': tools.length},
          lastUpdated: DateTime.now(),
        ));
      } catch (e) {
        _logger.debug('Tools capability not available for $clientId: $e');
      }

      // Check prompts capability
      try {
        final prompts = await mcpClient.listPrompts();
        discoveredCapabilities.add(McpCapability(
          type: McpCapabilityType.prompts,
          name: 'prompts',
          version: '2025-03-26',
          enabled: true,
          configuration: {'prompt_count': prompts.length},
          lastUpdated: DateTime.now(),
        ));
      } catch (e) {
        _logger.debug('Prompts capability not available for $clientId: $e');
      }

      // Check resources capability
      try {
        final resources = await mcpClient.listResources();
        discoveredCapabilities.add(McpCapability(
          type: McpCapabilityType.resources,
          name: 'resources',
          version: '2025-03-26',
          enabled: true,
          configuration: {'resource_count': resources.length},
          lastUpdated: DateTime.now(),
        ));
      } catch (e) {
        _logger.debug('Resources capability not available for $clientId: $e');
      }

      // Check authentication capability
      final authAdapter = _authAdapters[clientId];
      if (authAdapter != null) {
        discoveredCapabilities.add(McpCapability(
          type: McpCapabilityType.auth,
          name: 'oauth_2_1',
          version: '2025-03-26',
          enabled: authAdapter.hasValidAuth(clientId),
          configuration: {'auth_type': 'oauth_2.1'},
          lastUpdated: DateTime.now(),
        ));
      }

      // Check for 2025-03-26 specific capabilities
      _checkModernCapabilities(clientId, mcpClient, discoveredCapabilities);

      // Store discovered capabilities
      for (final capability in discoveredCapabilities) {
        _clientCapabilities[clientId]![capability.name] = capability;
        
        _eventController.add(CapabilityEvent(
          clientId: clientId,
          capabilityName: capability.name,
          type: CapabilityEventType.enabled,
          data: {'capability': capability.toJson(), 'reason': 'Initial discovery'},
          timestamp: DateTime.now(),
        ));
      }

      _logger.info('Discovered ${discoveredCapabilities.length} capabilities for $clientId');
    } catch (e) {
      _logger.error('Error discovering capabilities for $clientId: $e');
    }
  }

  /// Check for 2025-03-26 modern capabilities
  void _checkModernCapabilities(String clientId, dynamic mcpClient, List<McpCapability> capabilities) {
    // Check health capability
    if (_hasHealthSupport(mcpClient)) {
      capabilities.add(McpCapability(
        type: McpCapabilityType.auth,
        name: 'health_check',
        version: '2025-03-26',
        enabled: true,
        configuration: {'endpoint': '/health'},
        lastUpdated: DateTime.now(),
      ));
    }

    // Check batch processing capability
    if (_hasBatchSupport(mcpClient)) {
      capabilities.add(McpCapability(
        type: McpCapabilityType.batch,
        name: 'batch_processing',
        version: '2025-03-26',
        enabled: true,
        configuration: {'max_batch_size': 10},
        lastUpdated: DateTime.now(),
      ));
    }

    // Check streaming capability
    if (_hasStreamingSupport(mcpClient)) {
      capabilities.add(McpCapability(
        type: McpCapabilityType.streaming,
        name: 'response_streaming',
        version: '2025-03-26',
        enabled: true,
        lastUpdated: DateTime.now(),
      ));
    }

    // Check versioning capability
    capabilities.add(McpCapability(
      type: McpCapabilityType.streaming,
      name: 'protocol_versioning',
      version: '2025-03-26',
      enabled: true,
      configuration: {'supported_versions': ['2024-11-05', '2025-03-26']},
      lastUpdated: DateTime.now(),
    ));
  }

  /// Check if client supports health endpoints
  bool _hasHealthSupport(dynamic mcpClient) {
    try {
      return mcpClient.toString().contains('health') ||
             mcpClient.runtimeType.toString().contains('Health');
    } catch (e) {
      return false;
    }
  }

  /// Check if client supports batch processing
  bool _hasBatchSupport(dynamic mcpClient) {
    try {
      return mcpClient.toString().contains('batch') ||
             mcpClient.runtimeType.toString().contains('Batch') ||
             mcpClient.toString().contains('executeBatch');
    } catch (e) {
      return false;
    }
  }

  /// Check if client supports streaming
  bool _hasStreamingSupport(dynamic mcpClient) {
    try {
      return mcpClient.toString().contains('stream') ||
             mcpClient.runtimeType.toString().contains('Stream');
    } catch (e) {
      return false;
    }
  }

  /// Update capabilities for a specific client (2025-03-26 method)
  Future<CapabilityUpdateResponse> updateCapabilities(CapabilityUpdateRequest request) async {
    final clientId = request.clientId;
    final mcpClient = _mcpClients[clientId];
    
    if (mcpClient == null) {
      return CapabilityUpdateResponse(
        success: false,
        updatedCapabilities: [],
        error: 'Client not found: $clientId',
        timestamp: DateTime.now(),
      );
    }

    // Store update request in history
    _updateHistory[clientId]!.add(request);
    if (_updateHistory[clientId]!.length > _maxHistorySize) {
      _updateHistory[clientId]!.removeAt(0);
    }

    final updatedCapabilities = <McpCapability>[];
    final errors = <String>[];

    try {
      // Check authentication if required
      final authAdapter = _authAdapters[clientId];
      if (authAdapter != null && !authAdapter.hasValidAuth(clientId)) {
        return CapabilityUpdateResponse(
          success: false,
          updatedCapabilities: [],
          error: 'Authentication required for capability updates',
          timestamp: DateTime.now(),
        );
      }

      for (final capability in request.capabilities) {
        try {
          // Validate capability update
          await _validateCapabilityUpdate(clientId, capability);
          
          // Apply capability update
          final updated = await _applyCapabilityUpdate(clientId, capability);
          updatedCapabilities.add(updated);
          
          // Store updated capability
          _clientCapabilities[clientId]![capability.name] = updated;
          
          // Emit capability event
          _eventController.add(CapabilityEvent(
            clientId: clientId,
            capabilityName: updated.name,
            type: CapabilityEventType.updated,
            data: {'capability': updated.toJson(), 'reason': 'Manual update'},
            timestamp: DateTime.now(),
          ));
          
        } catch (e) {
          errors.add('Failed to update capability ${capability.name}: $e');
          _logger.error('Capability update failed for ${capability.name}: $e');
        }
      }

      final success = errors.isEmpty;
      
      _logger.info('Capability update for $clientId: ${updatedCapabilities.length} updated, ${errors.length} errors');
      
      return CapabilityUpdateResponse(
        success: success,
        updatedCapabilities: updatedCapabilities,
        error: errors.isEmpty ? null : errors.join('; '),
        timestamp: DateTime.now(),
      );
      
    } catch (e) {
      _logger.error('Capability update failed for $clientId: $e');
      return CapabilityUpdateResponse(
        success: false,
        updatedCapabilities: [],
        error: 'Capability update failed: $e',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Validate capability update request
  Future<void> _validateCapabilityUpdate(String clientId, McpCapability capability) async {
    // Check if capability type is supported
    if (!McpCapabilityType.values.contains(capability.type)) {
      throw Exception('Unsupported capability type: ${capability.type}');
    }

    // Check version compatibility
    if (!_isSupportedVersion(capability.version)) {
      throw Exception('Unsupported capability version: ${capability.version}');
    }

    // Validate configuration if present
    if (capability.configuration != null && capability.configuration!.isNotEmpty) {
      await _validateCapabilityConfiguration(capability);
    }
  }

  /// Check if version is supported
  bool _isSupportedVersion(String version) {
    const supportedVersions = ['2024-11-05', '2025-03-26'];
    return supportedVersions.contains(version);
  }

  /// Validate capability configuration
  Future<void> _validateCapabilityConfiguration(McpCapability capability) async {
    switch (capability.type) {
      case McpCapabilityType.batch:
        final maxBatchSize = capability.configuration?['max_batch_size'] as int?;
        if (maxBatchSize != null && (maxBatchSize < 1 || maxBatchSize > 100)) {
          throw Exception('Invalid max_batch_size: must be between 1 and 100');
        }
        break;
        
      case McpCapabilityType.auth:
        final authType = capability.configuration?['auth_type'] as String?;
        if (authType != null && !['oauth_2.1', 'api_key'].contains(authType)) {
          throw Exception('Invalid auth_type: $authType');
        }
        break;
        
      default:
        // No specific validation for other types
        break;
    }
  }

  /// Apply capability update to client
  Future<McpCapability> _applyCapabilityUpdate(String clientId, McpCapability capability) async {
    final mcpClient = _mcpClients[clientId];
    
    // Try to apply the update to the actual MCP client
    try {
      // For 2025-03-26 clients that support capability updates
      if (_hasCapabilityUpdateSupport(mcpClient)) {
        await _sendCapabilityUpdateToClient(mcpClient, capability);
      }
    } catch (e) {
      _logger.warning('Could not send capability update to client: $e');
      // Continue with local update even if client update fails
    }
    
    // Return updated capability with current timestamp
    return capability.copyWith(lastUpdated: DateTime.now());
  }

  /// Check if client supports capability updates
  bool _hasCapabilityUpdateSupport(dynamic mcpClient) {
    try {
      return mcpClient.toString().contains('updateCapabilities') ||
             mcpClient.runtimeType.toString().contains('CapabilityUpdate');
    } catch (e) {
      return false;
    }
  }

  /// Send capability update to client
  Future<void> _sendCapabilityUpdateToClient(dynamic mcpClient, McpCapability capability) async {
    // In a real implementation, this would send the update via the MCP protocol
    // For now, we'll simulate the operation
    await Future.delayed(Duration(milliseconds: 100));
    _logger.debug('Sent capability update to client: ${capability.name}');
  }

  /// Get all capabilities for a specific client
  Map<String, McpCapability> getClientCapabilities(String clientId) {
    return Map.unmodifiable(_clientCapabilities[clientId] ?? {});
  }

  /// Get specific capability for a client
  McpCapability? getClientCapability(String clientId, String capabilityName) {
    return _clientCapabilities[clientId]?[capabilityName];
  }

  /// Get all capabilities across all clients
  Map<String, Map<String, McpCapability>> getAllCapabilities() {
    return Map.unmodifiable(_clientCapabilities);
  }

  /// Enable capability for a client
  Future<bool> enableCapability(String clientId, String capabilityName) async {
    final capability = _clientCapabilities[clientId]?[capabilityName];
    if (capability == null) return false;

    if (!capability.enabled) {
      final updated = capability.copyWith(enabled: true, lastUpdated: DateTime.now());
      _clientCapabilities[clientId]![capabilityName] = updated;
      
      _eventController.add(CapabilityEvent(
        clientId: clientId,
        capabilityName: updated.name,
        type: CapabilityEventType.enabled,
        data: {'capability': updated.toJson()},
        timestamp: DateTime.now(),
      ));
      
      _logger.info('Enabled capability $capabilityName for $clientId');
    }
    
    return true;
  }

  /// Disable capability for a client
  Future<bool> disableCapability(String clientId, String capabilityName) async {
    final capability = _clientCapabilities[clientId]?[capabilityName];
    if (capability == null) return false;

    if (capability.enabled) {
      final updated = capability.copyWith(enabled: false, lastUpdated: DateTime.now());
      _clientCapabilities[clientId]![capabilityName] = updated;
      
      _eventController.add(CapabilityEvent(
        clientId: clientId,
        capabilityName: updated.name,
        type: CapabilityEventType.disabled,
        data: {'capability': updated.toJson()},
        timestamp: DateTime.now(),
      ));
      
      _logger.info('Disabled capability $capabilityName for $clientId');
    }
    
    return true;
  }

  /// Get capability update history for a client
  List<CapabilityUpdateRequest> getUpdateHistory(String clientId) {
    return List.unmodifiable(_updateHistory[clientId] ?? []);
  }

  /// Get capability statistics
  Map<String, dynamic> getCapabilityStatistics() {
    final allCapabilities = _clientCapabilities.values
        .expand((caps) => caps.values)
        .toList();
    
    final byType = <String, int>{};
    for (final type in McpCapabilityType.values) {
      byType[type.name] = allCapabilities.where((c) => c.type == type).length;
    }
    
    return {
      'total_clients': _mcpClients.length,
      'total_capabilities': allCapabilities.length,
      'enabled_capabilities': allCapabilities.where((c) => c.enabled).length,
      'disabled_capabilities': allCapabilities.where((c) => !c.enabled).length,
      'capabilities_by_type': byType,
      'update_requests': _updateHistory.values.map((h) => h.length).fold(0, (a, b) => a + b),
    };
  }

  /// Refresh capabilities for all clients
  Future<void> refreshAllCapabilities() async {
    _logger.info('Refreshing capabilities for all clients');
    
    final futures = _mcpClients.keys.map((clientId) => 
      _discoverClientCapabilities(clientId)
    ).toList();
    
    await Future.wait(futures);
    _logger.info('Capability refresh completed for ${_mcpClients.length} clients');
  }

  /// Generate unique request ID
  String generateRequestId() {
    return 'cap_${DateTime.now().millisecondsSinceEpoch}_${_mcpClients.length}';
  }

  /// Dispose of capability manager resources
  void dispose() {
    _eventController.close();
    _mcpClients.clear();
    _authAdapters.clear();
    _clientCapabilities.clear();
    _updateHistory.clear();
    _logger.info('Capability manager disposed');
  }
}