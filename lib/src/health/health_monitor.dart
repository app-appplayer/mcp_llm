import 'dart:async';
import '../utils/logger.dart';
import '../core/models.dart';

/// Health check configuration (using models from core/models.dart)
class HealthCheckConfig {
  final Duration timeout;
  final int maxRetries;
  final Duration retryDelay;
  final bool includeSystemMetrics;
  final List<String> excludeComponents;

  const HealthCheckConfig({
    this.timeout = const Duration(seconds: 5),
    this.maxRetries = 2,
    this.retryDelay = const Duration(milliseconds: 500),
    this.includeSystemMetrics = true,
    this.excludeComponents = const [],
  });
}

/// Health of the MCP peers mcp_llm holds. MCP defines no health method; a
/// client is checked with `ping` and a server by its own health record
/// (see [_checkPeer]).
class McpHealthMonitor {
  final HealthCheckConfig config;
  final DateTime _createdAt = DateTime.now();
  final Logger _logger = Logger('mcp_llm.health_monitor');
  
  final Map<String, dynamic> _mcpClients = {};
  final Map<String, HealthCheckResult> _lastResults = {};
  
  // Health check history for trending
  final Map<String, List<HealthCheckResult>> _healthHistory = {};
  final int _maxHistorySize = 50;

  McpHealthMonitor({
    this.config = const HealthCheckConfig(),
  });

  /// Register MCP client for health monitoring
  void registerClient(String clientId, dynamic mcpClient) {
    _mcpClients[clientId] = mcpClient;
    _healthHistory[clientId] = [];
    _logger.info('Registered MCP client for health monitoring: $clientId');
  }

  /// Unregister MCP client
  void unregisterClient(String clientId) {
    _mcpClients.remove(clientId);
    _lastResults.remove(clientId);
    _healthHistory.remove(clientId);
    _logger.info('Unregistered MCP client from health monitoring: $clientId');
  }

  /// Perform comprehensive health check on all registered clients
  Future<HealthReport> performHealthCheck({
    List<String>? clientIds,
    bool includeSystemMetrics = true,
  }) async {
    final startTime = DateTime.now();
    final effectiveClientIds = clientIds ?? _mcpClients.keys.toList();
    final resultsMap = <String, HealthCheckResult>{};

    _logger.info('Starting health check for ${effectiveClientIds.length} MCP clients');

    // Perform health checks in parallel for better performance
    final futures = effectiveClientIds.map((clientId) => 
      _performClientHealthCheck(clientId)
    ).toList();

    final clientResults = await Future.wait(futures);
    
    // Build results map
    for (int i = 0; i < effectiveClientIds.length; i++) {
      resultsMap[effectiveClientIds[i]] = clientResults[i];
    }

    // Add system-level health checks if requested
    if (includeSystemMetrics) {
      final systemResult = await _performSystemHealthCheck();
      resultsMap['system'] = systemResult;
    }

    // Calculate overall status
    final overallStatus = _calculateOverallStatus(resultsMap.values.toList());
    final totalCheckTime = DateTime.now().difference(startTime);

    final report = HealthReport(
      overallStatus: overallStatus,
      componentResults: resultsMap,
      timestamp: DateTime.now(),
      totalCheckTime: totalCheckTime,
    );

    _logger.info('Health check completed in ${totalCheckTime.inMilliseconds}ms - Overall status: ${overallStatus.name}');
    return report;
  }

  /// Perform health check on a specific MCP client
  Future<HealthCheckResult> _performClientHealthCheck(String clientId) async {
    if (config.excludeComponents.contains(clientId)) {
      return HealthCheckResult(
        clientId: clientId,
        status: HealthStatus.unknown,
        metrics: {},
        error: 'Component excluded from health checks',
        timestamp: DateTime.now(),
      );
    }

    final mcpClient = _mcpClients[clientId];
    if (mcpClient == null) {
      return HealthCheckResult(
        clientId: clientId,
        status: HealthStatus.unhealthy,
        metrics: {},
        error: 'MCP client not found',
        timestamp: DateTime.now(),
      );
    }

    final startTime = DateTime.now();
    
    for (int attempt = 0; attempt <= config.maxRetries; attempt++) {
      try {
        final reported = await _checkPeer(clientId, mcpClient);

        final responseTime = DateTime.now().difference(startTime);
        final result = HealthCheckResult(
          clientId: clientId,
          status: HealthStatus.healthy,
          metrics: {
            ...reported,
            'attempt': attempt + 1,
            'responseTimeMs': responseTime.inMilliseconds,
          },
          timestamp: DateTime.now(),
        );

        _updateHealthHistory(clientId, result);
        _lastResults[clientId] = result;
        return result;

      } catch (e) {
        _logger.warning('Health check attempt ${attempt + 1} failed for $clientId: $e');
        
        if (attempt < config.maxRetries) {
          await Future.delayed(config.retryDelay);
          continue;
        }
        
        // Final attempt failed
        final responseTime = DateTime.now().difference(startTime);
        final result = HealthCheckResult(
          clientId: clientId,
          status: HealthStatus.unhealthy,
          metrics: {
            'attempts': attempt + 1,
            'responseTimeMs': responseTime.inMilliseconds,
          },
          error: 'Health check failed: $e',
          timestamp: DateTime.now(),
        );

        _updateHealthHistory(clientId, result);
        _lastResults[clientId] = result;
        return result;
      }
    }

    // Should not reach here, but provide fallback
    return HealthCheckResult(
      clientId: clientId,
      status: HealthStatus.unknown,
      metrics: {},
      error: 'Unexpected health check state',
      timestamp: DateTime.now(),
    );
  }

  /// Checks one peer the way the protocol allows, and returns what it
  /// reported. A client (mcp_client) is pinged — `ping` exists in every
  /// revision — and reports the capabilities the server declared; a server
  /// (mcp_server) reports its own health record, and is unhealthy when it is
  /// not running.
  Future<Map<String, dynamic>> _checkPeer(String clientId, dynamic peer) async {
    final dynamic ping;
    try {
      ping = peer.ping;
    } on NoSuchMethodError {
      return _checkServer(clientId, peer);
    }
    await (ping() as Future<dynamic>).timeout(config.timeout);
    return {
      'kind': 'client',
      'protocolVersion': _read(() => peer.negotiatedProtocolVersion),
      'serverCapabilities': _jsonOf(_read(() => peer.serverCapabilities)),
    };
  }

  Map<String, dynamic> _checkServer(String clientId, dynamic peer) {
    final Object? health;
    try {
      health = peer.getHealth();
    } on NoSuchMethodError {
      throw StateError('$clientId has neither ping (a client) nor getHealth (a server)');
    }
    final json = _jsonOf(health) ?? const <String, dynamic>{};
    if (json['isRunning'] == false) {
      throw StateError('$clientId is not running (no transport connected)');
    }
    return {
      'kind': 'server',
      'health': json,
    };
  }

  static Object? _read(Object? Function() getter) {
    try {
      return getter();
    } on NoSuchMethodError {
      return null;
    }
  }

  static Map<String, dynamic>? _jsonOf(Object? value) {
    if (value == null) return null;
    if (value is Map) return Map<String, dynamic>.from(value);
    try {
      return Map<String, dynamic>.from((value as dynamic).toJson() as Map);
    } on NoSuchMethodError {
      return null;
    }
  }

  /// Perform system-level health check
  Future<HealthCheckResult> _performSystemHealthCheck() async {
    final startTime = DateTime.now();
    
    try {
      final systemStatus = <String, dynamic>{
        'registered_clients': _mcpClients.length,
        'healthy_clients': _lastResults.values.where((r) => r.status == HealthStatus.healthy).length,
        'uptimeSeconds': DateTime.now().difference(_createdAt).inSeconds,
      };

      final responseTime = DateTime.now().difference(startTime);
      
      return HealthCheckResult(
        clientId: 'system',
        status: HealthStatus.healthy,
        metrics: {
          ...systemStatus,
          'responseTimeMs': responseTime.inMilliseconds,
        },
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return HealthCheckResult(
        clientId: 'system',
        status: HealthStatus.unhealthy,
        metrics: {},
        error: 'System health check failed: $e',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Calculate overall health status from component results
  HealthStatus _calculateOverallStatus(List<HealthCheckResult> results) {
    if (results.isEmpty) return HealthStatus.unknown;
    
    final hasUnhealthy = results.any((r) => r.status == HealthStatus.unhealthy);
    if (hasUnhealthy) return HealthStatus.unhealthy;
    
    final hasDegraded = results.any((r) => r.status == HealthStatus.degraded);
    if (hasDegraded) return HealthStatus.degraded;
    
    final hasUnknown = results.any((r) => r.status == HealthStatus.unknown);
    if (hasUnknown) return HealthStatus.degraded; // Treat unknown as degraded
    
    return HealthStatus.healthy;
  }

  /// Update health history for trending analysis
  void _updateHealthHistory(String clientId, HealthCheckResult result) {
    final history = _healthHistory[clientId];
    if (history != null) {
      history.add(result);
      
      // Keep only the most recent results
      if (history.length > _maxHistorySize) {
        history.removeAt(0);
      }
    }
  }


  /// Get health status for specific client
  HealthCheckResult? getClientHealth(String clientId) {
    return _lastResults[clientId];
  }

  /// Get health history for trending analysis
  List<HealthCheckResult> getClientHealthHistory(String clientId) {
    return List.unmodifiable(_healthHistory[clientId] ?? []);
  }

  /// Check if all clients are healthy
  bool get allClientsHealthy {
    return _lastResults.values.every((result) => result.status == HealthStatus.healthy);
  }

  /// Get list of unhealthy clients
  List<String> get unhealthyClients {
    return _lastResults.entries
        .where((entry) => entry.value.status != HealthStatus.healthy)
        .map((entry) => entry.key)
        .toList();
  }

  /// Get health statistics
  Map<String, dynamic> getHealthStatistics() {
    final allResults = _lastResults.values.toList();
    
    return {
      'total_clients': _mcpClients.length,
      'healthy': allResults.where((r) => r.status == HealthStatus.healthy).length,
      'degraded': allResults.where((r) => r.status == HealthStatus.degraded).length,
      'unhealthy': allResults.where((r) => r.status == HealthStatus.unhealthy).length,
      'unknown': allResults.where((r) => r.status == HealthStatus.unknown).length,
      'average_response_time': _calculateAverageResponseTime(allResults),
      'last_check': allResults.isNotEmpty 
          ? allResults.map((r) => r.timestamp).reduce((a, b) => a.isAfter(b) ? a : b).toIso8601String()
          : null,
    };
  }

  /// Calculate average response time
  double _calculateAverageResponseTime(List<HealthCheckResult> results) {
    final validTimes = results
        .where((r) => r.metrics.containsKey('responseTimeMs'))
        .map((r) => r.metrics['responseTimeMs'] as int)
        .toList();
    
    if (validTimes.isEmpty) return 0.0;
    
    return validTimes.reduce((a, b) => a + b) / validTimes.length;
  }

  /// Dispose of health monitor resources
  void dispose() {
    _mcpClients.clear();
    _lastResults.clear();
    _healthHistory.clear();
    _logger.info('Health monitor disposed');
  }
}