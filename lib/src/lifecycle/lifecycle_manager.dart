import 'dart:async';
import '../utils/logger.dart';
import '../adapter/mcp_auth_adapter.dart';
import '../health/health_monitor.dart';
import '../capabilities/capability_manager.dart';
import '../core/models.dart';

/// Lifecycle operation request
class LifecycleRequest {
  final String requestId;
  final String serverId;
  final String operation;
  final Map<String, dynamic> parameters;
  final LifecycleTransitionReason reason;
  final DateTime timestamp;

  const LifecycleRequest({
    required this.requestId,
    required this.serverId,
    required this.operation,
    this.parameters = const {},
    required this.reason,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'serverId': serverId,
      'operation': operation,
      'parameters': parameters,
      'reason': reason.name,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Server Lifecycle Manager for 2025-03-26 MCP specification
class ServerLifecycleManager {
  final Logger _logger = Logger('mcp_llm.lifecycle_manager');
  
  final Map<String, dynamic> _mcpServers = {};
  final Map<String, McpAuthAdapter?> _authAdapters = {};
  final Map<String, ServerLifecycleState> _serverStates = {};
  final Map<String, ServerInfo> _serverInfo = {};
  final Map<String, DateTime> _stateTransitionTimes = {};
  
  // Integration with other managers
  final McpHealthMonitor? healthMonitor;
  final McpCapabilityManager? capabilityManager;
  
  // Event stream for lifecycle changes
  final StreamController<LifecycleEvent> _eventController = StreamController<LifecycleEvent>.broadcast();
  Stream<LifecycleEvent> get events => _eventController.stream;
  
  // Lifecycle operation history
  final Map<String, List<LifecycleRequest>> _operationHistory = {};
  final int _maxHistorySize = 200;
  
  // Auto-restart configuration
  final Map<String, bool> _autoRestartEnabled = {};
  final Map<String, int> _restartAttempts = {};
  final int _maxRestartAttempts = 3;

  ServerLifecycleManager({
    this.healthMonitor,
    this.capabilityManager,
  });

  /// Register MCP server for lifecycle management
  void registerServer(
    String serverId, 
    dynamic mcpServer, {
    McpAuthAdapter? authAdapter,
    String? name,
    String? version,
    Map<String, dynamic> configuration = const {},
    bool autoRestart = false,
  }) {
    _mcpServers[serverId] = mcpServer;
    _authAdapters[serverId] = authAdapter;
    _serverStates[serverId] = ServerLifecycleState.stopped;
    _stateTransitionTimes[serverId] = DateTime.now();
    _autoRestartEnabled[serverId] = autoRestart;
    _restartAttempts[serverId] = 0;
    _operationHistory[serverId] = [];
    
    _serverInfo[serverId] = ServerInfo(
      serverId: serverId,
      name: name ?? 'MCP Server $serverId',
      state: ServerLifecycleState.stopped,
      uptime: Duration.zero,
      metadata: {
        'auto_restart': autoRestart,
        'protocol_version': '2025-03-26',
        'version': version ?? '2025-03-26',
        'configuration': configuration,
        'startTime': DateTime.now().toIso8601String(),
      },
    );
    
    _logger.info('Registered MCP server for lifecycle management: $serverId');
    
    // Register with health monitor if available
    if (healthMonitor != null) {
      healthMonitor!.registerClient(serverId, mcpServer, authAdapter: authAdapter);
    }
    
    // Register with capability manager if available
    if (capabilityManager != null) {
      capabilityManager!.registerClient(serverId, mcpServer, authAdapter: authAdapter);
    }
    
    // Emit initial lifecycle event
    _emitLifecycleEvent(
      serverId,
      ServerLifecycleState.stopped,
      ServerLifecycleState.stopped,
      LifecycleTransitionReason.userRequest,
      'Server registered for lifecycle management',
    );
  }

  /// Unregister MCP server
  void unregisterServer(String serverId) {
    // Stop server if running
    if (_serverStates[serverId] == ServerLifecycleState.running) {
      stopServer(serverId, reason: LifecycleTransitionReason.userRequest);
    }
    
    _mcpServers.remove(serverId);
    _authAdapters.remove(serverId);
    _serverStates.remove(serverId);
    _serverInfo.remove(serverId);
    _stateTransitionTimes.remove(serverId);
    _autoRestartEnabled.remove(serverId);
    _restartAttempts.remove(serverId);
    _operationHistory.remove(serverId);
    
    // Unregister from other managers
    if (healthMonitor != null) {
      healthMonitor!.unregisterClient(serverId);
    }
    if (capabilityManager != null) {
      capabilityManager!.unregisterClient(serverId);
    }
    
    _logger.info('Unregistered MCP server from lifecycle management: $serverId');
  }

  /// Start MCP server
  Future<LifecycleResponse> startServer(
    String serverId, {
    LifecycleTransitionReason reason = LifecycleTransitionReason.userRequest,
    Map<String, dynamic> parameters = const {},
  }) async {
    final requestId = _generateRequestId();
    final request = LifecycleRequest(
      requestId: requestId,
      serverId: serverId,
      operation: 'start',
      parameters: parameters,
      reason: reason,
      timestamp: DateTime.now(),
    );
    
    _addToHistory(serverId, request);
    
    final mcpServer = _mcpServers[serverId];
    if (mcpServer == null) {
      return LifecycleResponse(
        success: false,
        error: 'Server not found: $serverId',
        timestamp: DateTime.now(),
      );
    }
    
    final currentState = _serverStates[serverId];
    if (currentState == ServerLifecycleState.running) {
      return LifecycleResponse(
        success: true,
        newState: currentState,
        timestamp: DateTime.now(),
      );
    }
    
    try {
      _logger.info('Starting MCP server: $serverId');
      
      // Transition to starting state
      await _transitionState(serverId, ServerLifecycleState.starting, reason, 'Starting server');
      
      // Perform server startup sequence
      await _performServerStartup(serverId, mcpServer, parameters);
      
      // Transition to running state
      await _transitionState(serverId, ServerLifecycleState.running, reason, 'Server started successfully');
      
      // Reset restart attempts on successful start
      _restartAttempts[serverId] = 0;
      
      _logger.info('MCP server started successfully: $serverId');
      
      return LifecycleResponse(
        success: true,
        newState: ServerLifecycleState.running,
        timestamp: DateTime.now(),
      );
      
    } catch (e) {
      _logger.error('Failed to start MCP server $serverId: $e');
      
      await _transitionState(serverId, ServerLifecycleState.error, reason, 'Failed to start server: $e');
      
      return LifecycleResponse(
        success: false,
        newState: ServerLifecycleState.error,
        error: 'Failed to start server: $e',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Stop MCP server
  Future<LifecycleResponse> stopServer(
    String serverId, {
    LifecycleTransitionReason reason = LifecycleTransitionReason.userRequest,
    Map<String, dynamic> parameters = const {},
    Duration? timeout,
  }) async {
    final requestId = _generateRequestId();
    final request = LifecycleRequest(
      requestId: requestId,
      serverId: serverId,
      operation: 'stop',
      parameters: parameters,
      reason: reason,
      timestamp: DateTime.now(),
    );
    
    _addToHistory(serverId, request);
    
    final mcpServer = _mcpServers[serverId];
    if (mcpServer == null) {
      return LifecycleResponse(
        success: false,
        error: 'Server not found: $serverId',
        timestamp: DateTime.now(),
      );
    }
    
    final currentState = _serverStates[serverId];
    if (currentState == ServerLifecycleState.stopped) {
      return LifecycleResponse(
        success: true,
        newState: currentState,
        timestamp: DateTime.now(),
      );
    }
    
    try {
      _logger.info('Stopping MCP server: $serverId');
      
      // Transition to stopping state
      await _transitionState(serverId, ServerLifecycleState.stopping, reason, 'Stopping server');
      
      // Perform server shutdown sequence
      await _performServerShutdown(serverId, mcpServer, parameters, timeout);
      
      // Transition to stopped state
      await _transitionState(serverId, ServerLifecycleState.stopped, reason, 'Server stopped successfully');
      
      _logger.info('MCP server stopped successfully: $serverId');
      
      return LifecycleResponse(
        success: true,
        newState: ServerLifecycleState.stopped,
        timestamp: DateTime.now(),
      );
      
    } catch (e) {
      _logger.error('Failed to stop MCP server $serverId: $e');
      
      await _transitionState(serverId, ServerLifecycleState.error, reason, 'Failed to stop server: $e');
      
      return LifecycleResponse(
        success: false,
        newState: ServerLifecycleState.error,
        error: 'Failed to stop server: $e',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Restart MCP server
  Future<LifecycleResponse> restartServer(
    String serverId, {
    LifecycleTransitionReason reason = LifecycleTransitionReason.userRequest,
    Map<String, dynamic> parameters = const {},
  }) async {
    _logger.info('Restarting MCP server: $serverId');
    
    // Stop server first
    final stopResponse = await stopServer(serverId, reason: reason, parameters: parameters);
    if (!stopResponse.success) {
      return stopResponse;
    }
    
    // Wait a moment before starting
    await Future.delayed(Duration(milliseconds: 500));
    
    // Start server
    return await startServer(serverId, reason: reason, parameters: parameters);
  }

  /// Pause MCP server
  Future<LifecycleResponse> pauseServer(
    String serverId, {
    LifecycleTransitionReason reason = LifecycleTransitionReason.userRequest,
    Map<String, dynamic> parameters = const {},
  }) async {
    final requestId = _generateRequestId();
    final request = LifecycleRequest(
      requestId: requestId,
      serverId: serverId,
      operation: 'pause',
      parameters: parameters,
      reason: reason,
      timestamp: DateTime.now(),
    );
    
    _addToHistory(serverId, request);
    
    final currentState = _serverStates[serverId];
    if (currentState != ServerLifecycleState.running) {
      return LifecycleResponse(
        success: false,
        error: 'Server must be running to pause',
        timestamp: DateTime.now(),
      );
    }
    
    try {
      _logger.info('Pausing MCP server: $serverId');
      
      await _transitionState(serverId, ServerLifecycleState.pausing, reason, 'Pausing server');
      
      // Perform pause operations (implementation-specific)
      await _performServerPause(serverId, parameters);
      
      await _transitionState(serverId, ServerLifecycleState.paused, reason, 'Server paused successfully');
      
      return LifecycleResponse(
        success: true,
        newState: ServerLifecycleState.paused,
        timestamp: DateTime.now(),
      );
      
    } catch (e) {
      await _transitionState(serverId, ServerLifecycleState.error, reason, 'Failed to pause server: $e');
      
      return LifecycleResponse(
        success: false,
        error: 'Failed to pause server: $e',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Resume MCP server
  Future<LifecycleResponse> resumeServer(
    String serverId, {
    LifecycleTransitionReason reason = LifecycleTransitionReason.userRequest,
    Map<String, dynamic> parameters = const {},
  }) async {
    final requestId = _generateRequestId();
    final request = LifecycleRequest(
      requestId: requestId,
      serverId: serverId,
      operation: 'resume',
      parameters: parameters,
      reason: reason,
      timestamp: DateTime.now(),
    );
    
    _addToHistory(serverId, request);
    
    final currentState = _serverStates[serverId];
    if (currentState != ServerLifecycleState.paused) {
      return LifecycleResponse(
        success: false,
        error: 'Server must be paused to resume',
        timestamp: DateTime.now(),
      );
    }
    
    try {
      _logger.info('Resuming MCP server: $serverId');
      
      await _transitionState(serverId, ServerLifecycleState.starting, reason, 'Resuming server');
      
      // Perform resume operations
      await _performServerResume(serverId, parameters);
      
      await _transitionState(serverId, ServerLifecycleState.running, reason, 'Server resumed successfully');
      
      return LifecycleResponse(
        success: true,
        newState: ServerLifecycleState.running,
        timestamp: DateTime.now(),
      );
      
    } catch (e) {
      await _transitionState(serverId, ServerLifecycleState.error, reason, 'Failed to resume server: $e');
      
      return LifecycleResponse(
        success: false,
        error: 'Failed to resume server: $e',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Perform server startup sequence
  Future<void> _performServerStartup(String serverId, dynamic mcpServer, Map<String, dynamic> parameters) async {
    // Check authentication if required
    final authAdapter = _authAdapters[serverId];
    if (authAdapter != null) {
      final authResult = await authAdapter.authenticate(serverId, mcpServer);
      if (!authResult.isAuthenticated) {
        throw Exception('Authentication failed during startup');
      }
    }
    
    // Initialize server capabilities
    if (capabilityManager != null) {
      await capabilityManager!.refreshAllCapabilities();
    }
    
    // Perform health check
    if (healthMonitor != null) {
      final health = await healthMonitor!.performHealthCheck(clientIds: [serverId]);
      if (health.overallStatus == HealthStatus.unhealthy) {
        throw Exception('Health check failed during startup');
      }
    }
    
    // Custom startup logic can be added here
    await Future.delayed(Duration(milliseconds: 100)); // Simulate startup time
  }

  /// Perform server shutdown sequence
  Future<void> _performServerShutdown(
    String serverId, 
    dynamic mcpServer, 
    Map<String, dynamic> parameters,
    Duration? timeout,
  ) async {
    final shutdownTimeout = timeout ?? Duration(seconds: 30);
    
    try {
      await _executeShutdownSequence(serverId, mcpServer, parameters)
          .timeout(shutdownTimeout);
    } on TimeoutException {
      _logger.warning('Server shutdown timed out for $serverId, forcing shutdown');
      // Force shutdown logic here
    }
  }

  /// Execute shutdown sequence
  Future<void> _executeShutdownSequence(String serverId, dynamic mcpServer, Map<String, dynamic> parameters) async {
    // Close any active connections
    // Clean up resources
    // Save state if needed
    
    await Future.delayed(Duration(milliseconds: 200)); // Simulate shutdown time
  }

  /// Perform server pause operations
  Future<void> _performServerPause(String serverId, Map<String, dynamic> parameters) async {
    // Pause processing but keep connections
    await Future.delayed(Duration(milliseconds: 50));
  }

  /// Perform server resume operations
  Future<void> _performServerResume(String serverId, Map<String, dynamic> parameters) async {
    // Resume processing
    await Future.delayed(Duration(milliseconds: 50));
  }

  /// Transition server state
  Future<void> _transitionState(
    String serverId,
    ServerLifecycleState newState,
    LifecycleTransitionReason reason,
    String message,
  ) async {
    final oldState = _serverStates[serverId];
    if (oldState == newState) return;
    
    final transitionStart = DateTime.now();
    _serverStates[serverId] = newState;
    _stateTransitionTimes[serverId] = transitionStart;
    
    // Update server info
    final oldInfo = _serverInfo[serverId]!;
    final startTimeStr = oldInfo.metadata['startTime'] as String?;
    final startTime = startTimeStr != null ? DateTime.parse(startTimeStr) : transitionStart;
    final uptime = transitionStart.difference(startTime);
    
    _serverInfo[serverId] = ServerInfo(
      serverId: oldInfo.serverId,
      name: oldInfo.name,
      state: newState,
      uptime: uptime,
      metadata: {
        ...oldInfo.metadata,
        'lastStateChange': transitionStart.toIso8601String(),
      },
    );
    
    // Emit lifecycle event
    _emitLifecycleEvent(serverId, oldState!, newState, reason, message);
    
    _logger.debug('Server $serverId transitioned from ${oldState.name} to ${newState.name}');
  }

  /// Emit lifecycle event
  void _emitLifecycleEvent(
    String serverId,
    ServerLifecycleState fromState,
    ServerLifecycleState toState,
    LifecycleTransitionReason reason,
    String? message,
  ) {
    final event = LifecycleEvent(
      serverId: serverId,
      previousState: fromState,
      newState: toState,
      reason: reason,
      timestamp: DateTime.now(),
    );
    
    _eventController.add(event);
  }

  /// Add request to operation history
  void _addToHistory(String serverId, LifecycleRequest request) {
    final history = _operationHistory[serverId];
    if (history != null) {
      history.add(request);
      if (history.length > _maxHistorySize) {
        history.removeAt(0);
      }
    }
  }

  /// Generate unique request ID
  String _generateRequestId() {
    return 'lc_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Get server information
  ServerInfo? getServerInfo(String serverId) {
    return _serverInfo[serverId];
  }

  /// Get all server information
  Map<String, ServerInfo> getAllServersInfo() {
    return Map.unmodifiable(_serverInfo);
  }

  /// Get server state
  ServerLifecycleState? getServerState(String serverId) {
    return _serverStates[serverId];
  }

  /// Get operation history for server
  List<LifecycleRequest> getOperationHistory(String serverId) {
    return List.unmodifiable(_operationHistory[serverId] ?? []);
  }

  /// Get lifecycle statistics
  Map<String, dynamic> getLifecycleStatistics() {
    final states = _serverStates.values.toList();
    final stateCount = <String, int>{};
    
    for (final state in ServerLifecycleState.values) {
      stateCount[state.name] = states.where((s) => s == state).length;
    }
    
    return {
      'total_servers': _mcpServers.length,
      'states': stateCount,
      'auto_restart_enabled': _autoRestartEnabled.values.where((enabled) => enabled).length,
      'total_operations': _operationHistory.values.map((h) => h.length).fold(0, (a, b) => a + b),
    };
  }

  /// Check if auto-restart is enabled for server
  bool isAutoRestartEnabled(String serverId) {
    return _autoRestartEnabled[serverId] ?? false;
  }

  /// Enable/disable auto-restart for server
  void setAutoRestart(String serverId, bool enabled) {
    _autoRestartEnabled[serverId] = enabled;
    _logger.info('Auto-restart ${enabled ? 'enabled' : 'disabled'} for server: $serverId');
  }

  /// Handle server errors and auto-restart if configured
  Future<void> handleServerError(String serverId, String error) async {
    _logger.error('Server error for $serverId: $error');
    
    await _transitionState(
      serverId,
      ServerLifecycleState.error,
      LifecycleTransitionReason.errorRecovery,
      'Server error: $error',
    );
    
    // Check if auto-restart is enabled and within retry limits
    if (_autoRestartEnabled[serverId] == true) {
      final attempts = _restartAttempts[serverId] ?? 0;
      if (attempts < _maxRestartAttempts) {
        _restartAttempts[serverId] = attempts + 1;
        _logger.info('Attempting auto-restart for $serverId (attempt ${attempts + 1}/$_maxRestartAttempts)');
        
        await Future.delayed(Duration(seconds: 5)); // Wait before restart
        await startServer(serverId, reason: LifecycleTransitionReason.errorRecovery);
      } else {
        _logger.error('Max restart attempts reached for $serverId, disabling auto-restart');
        _autoRestartEnabled[serverId] = false;
      }
    }
  }

  /// Dispose of lifecycle manager resources
  void dispose() {
    _eventController.close();
    _mcpServers.clear();
    _authAdapters.clear();
    _serverStates.clear();
    _serverInfo.clear();
    _stateTransitionTimes.clear();
    _autoRestartEnabled.clear();
    _restartAttempts.clear();
    _operationHistory.clear();
    _logger.info('Server lifecycle manager disposed');
  }
}