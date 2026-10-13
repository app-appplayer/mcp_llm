import 'dart:async';
import '../utils/logger.dart';
import '../core/models.dart';

/// The capabilities of the MCP peers mcp_llm holds, as they declared them —
/// a client reports the server's `ServerCapabilities`, a server its own.
/// MCP has no method to change a peer's capabilities after initialization;
/// [updateCapabilities], [enableCapability] and [disableCapability] change
/// only mcp_llm's own record.
class McpCapabilityManager {
  final Logger _logger = Logger('mcp_llm.capability_manager');
  
  final Map<String, dynamic> _mcpClients = {};
  final Map<String, Map<String, McpCapability>> _clientCapabilities = {};
  
  // Event stream for capability changes
  final StreamController<CapabilityEvent> _eventController = StreamController<CapabilityEvent>.broadcast();
  Stream<CapabilityEvent> get events => _eventController.stream;
  
  // Capability update history
  final Map<String, List<CapabilityUpdateRequest>> _updateHistory = {};
  final int _maxHistorySize = 100;

  McpCapabilityManager();

  /// Register MCP client for capability management
  void registerClient(String clientId, dynamic mcpClient) {
    _mcpClients[clientId] = mcpClient;
    _clientCapabilities[clientId] = {};
    _updateHistory[clientId] = [];
    _logger.info('Registered MCP client for capability management: $clientId');
    
    // Perform initial capability discovery
    _discoverClientCapabilities(clientId);
  }

  /// Unregister MCP client
  void unregisterClient(String clientId) {
    _mcpClients.remove(clientId);
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
      final declared = _declaredCapabilities(mcpClient);
      final version = _protocolVersion(mcpClient);
      for (final entry in declared.entries) {
        final type = McpCapabilityType.values.where((t) => t.name == entry.key).firstOrNull;
        if (type == null) {
          _logger.debug('$clientId declares "${entry.key}", which mcp_llm does not track');
          continue;
        }
        discoveredCapabilities.add(McpCapability(
          type: type,
          name: entry.key,
          version: version,
          enabled: true,
          configuration: entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : null,
          lastUpdated: DateTime.now(),
        ));
      }

      // Store discovered capabilities
      for (final capability in discoveredCapabilities) {
        _clientCapabilities[clientId]![capability.name] = capability;
        
        _eventController.add(CapabilityEvent(
          clientId: clientId,
          capabilityName: capability.name,
          type: CapabilityEventType.enabled,
          data: {'capability': capability.toJson(), 'reason': 'Declared by the peer'},
          timestamp: DateTime.now(),
        ));
      }

      _logger.info('Discovered ${discoveredCapabilities.length} capabilities for $clientId');
    } catch (e) {
      _logger.error('Error discovering capabilities for $clientId: $e');
    }
  }

  /// The capabilities [peer] declared, as protocol JSON: a client
  /// (mcp_client) holds the server's declaration after initialization, a
  /// server (mcp_server) its own.
  static Map<String, dynamic> _declaredCapabilities(dynamic peer) {
    Object? caps;
    try {
      caps = peer.serverCapabilities;
    } on NoSuchMethodError {
      try {
        caps = peer.capabilities;
      } on NoSuchMethodError {
        caps = null;
      }
    }
    if (caps == null) return const {};
    if (caps is Map) return Map<String, dynamic>.from(caps);
    try {
      return Map<String, dynamic>.from((caps as dynamic).toJson() as Map);
    } on NoSuchMethodError {
      return const {};
    }
  }

  /// The revision a client negotiated; a server's declaration is not tied to
  /// one, and reads as the newest revision.
  static String _protocolVersion(dynamic peer) {
    try {
      final v = peer.negotiatedProtocolVersion;
      if (v is String) return v;
    } on NoSuchMethodError {
      // A server: falls through.
    }
    return _supportedVersions.first;
  }

  /// The revisions mcp_llm works with, newest first.
  static const _supportedVersions = ['2026-07-28', '2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05'];

  /// Record a change to capabilities in mcp_llm's own record. Nothing is
  /// sent to the peer: MCP has no method for it.
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

  }

  /// Check if version is supported
  bool _isSupportedVersion(String version) => _supportedVersions.contains(version);

  /// The capability as recorded now.
  Future<McpCapability> _applyCapabilityUpdate(String clientId, McpCapability capability) async =>
      capability.copyWith(lastUpdated: DateTime.now());

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
    _clientCapabilities.clear();
    _updateHistory.clear();
    _logger.info('Capability manager disposed');
  }
}