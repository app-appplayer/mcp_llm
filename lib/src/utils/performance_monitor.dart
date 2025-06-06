// lib/src/utils/performance_monitor.dart improved version

import 'dart:async';
import '../../mcp_llm.dart';

/// Performance monitoring system for LLM and MCP usage
class PerformanceMonitor {
  // Performance metrics
  int _totalRequests = 0;
  int _failedRequests = 0;
  int _successfulToolCalls = 0;
  int _failedToolCalls = 0;
  final Map<String, int> _requestsPerProvider = {};
  final Map<String, int> _toolCallsPerTool = {};
  final Map<String, List<int>> _responseTimesMs = {};

  // Monitoring timer
  Timer? _monitoringTimer;
  bool _isMonitoring = false;

  // Timestamp - request ID map
  final Map<String, DateTime> _requestStartTimes = {};

  final Logger _logger = Logger('mcp_llm.performance_monitor');

  // Default constructor
  PerformanceMonitor();

  /// Check if monitoring is active
  bool get isMonitoring => _isMonitoring;

  /// Record request start
  String startRequest(String providerName) {
    _totalRequests++;
    _requestsPerProvider[providerName] =
        (_requestsPerProvider[providerName] ?? 0) + 1;

    // Generate request ID
    final requestId =
        'req_${DateTime.now().millisecondsSinceEpoch}_${_totalRequests}_$providerName';
    _requestStartTimes[requestId] = DateTime.now();

    _logger.debug('Started tracking request: $requestId for provider: $providerName');
    return requestId;
  }

  /// Record request completion
  void endRequest(String requestId, {bool success = true}) {
    if (requestId.isEmpty) return;

    final startTime = _requestStartTimes.remove(requestId);
    if (startTime != null) {
      final duration = DateTime.now().difference(startTime);

      if (!success) {
        _failedRequests++;
        _logger.debug('Request $requestId failed after ${duration.inMilliseconds}ms');
      } else {
        _logger.debug('Request $requestId completed successfully in ${duration.inMilliseconds}ms');
      }

      // Record response time
      final responseTimeMs = duration.inMilliseconds;

      // Extract provider from request ID
      final parts = requestId.split('_');
      final provider = parts.length > 3 ? parts[3] : 'unknown';

      if (!_responseTimesMs.containsKey(provider)) {
        _responseTimesMs[provider] = [];
      }
      _responseTimesMs[provider]!.add(responseTimeMs);
    }
  }

  /// Record tool call
  void recordToolCall(String toolName, {bool success = true}) {
    if (success) {
      _successfulToolCalls++;
      _logger.debug('Tool call to $toolName succeeded');
    } else {
      _failedToolCalls++;
      _logger.debug('Tool call to $toolName failed');
    }

    _toolCallsPerTool[toolName] = (_toolCallsPerTool[toolName] ?? 0) + 1;
  }

  /// Reset metrics
  void resetMetrics() {
    _totalRequests = 0;
    _failedRequests = 0;
    _successfulToolCalls = 0;
    _failedToolCalls = 0;
    _requestsPerProvider.clear();
    _toolCallsPerTool.clear();
    _responseTimesMs.clear();
    _requestStartTimes.clear();
    _logger.info('Performance metrics have been reset');
  }

  /// Start monitoring
  void startMonitoring(Duration interval) {
    if (_isMonitoring) {
      _logger.warning('Performance monitoring is already active');
      return;
    }

    _isMonitoring = true;
    _monitoringTimer = Timer.periodic(interval, (_) {
      _logPerformanceMetrics();
    });

    _logger.info(
        'Performance monitoring started with interval: ${interval.inSeconds}s');
  }

  /// Stop monitoring
  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;

    if (_isMonitoring) {
      _isMonitoring = false;
      _logger.info('Performance monitoring stopped');
    }
  }

  /// Get current metrics report
  Map<String, dynamic> getMetricsReport() {
    // Calculate average response times
    final Map<String, double> avgResponseTimes = {};
    for (final entry in _responseTimesMs.entries) {
      if (entry.value.isNotEmpty) {
        final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
        avgResponseTimes[entry.key] = avg;
      }
    }

    // Calculate percentiles for response times (if enough data)
    final Map<String, Map<String, double>> responseTimePercentiles = {};
    for (final entry in _responseTimesMs.entries) {
      if (entry.value.length >= 10) { // Need enough samples for meaningful percentiles
        final sortedTimes = List<int>.from(entry.value)..sort();
        final p50Index = (sortedTimes.length * 0.5).floor();
        final p90Index = (sortedTimes.length * 0.9).floor();
        final p99Index = (sortedTimes.length * 0.99).floor();

        responseTimePercentiles[entry.key] = {
          'p50': sortedTimes[p50Index].toDouble(),
          'p90': sortedTimes[p90Index].toDouble(),
          'p99': sortedTimes[p99Index].toDouble(),
        };
      }
    }

    return {
      'total_requests': _totalRequests,
      'failed_requests': _failedRequests,
      'success_rate': _totalRequests > 0
          ? '${((_totalRequests - _failedRequests) / _totalRequests * 100)
          .toStringAsFixed(2)}%'
          : 'N/A',
      'total_tool_calls': _successfulToolCalls + _failedToolCalls,
      'successful_tool_calls': _successfulToolCalls,
      'tool_call_success_rate': (_successfulToolCalls + _failedToolCalls) > 0
          ? '${(_successfulToolCalls /
          (_successfulToolCalls + _failedToolCalls) *
          100)
          .toStringAsFixed(2)}%'
          : 'N/A',
      'requests_per_provider': _requestsPerProvider,
      'tool_calls_per_tool': _toolCallsPerTool,
      'avg_response_times_ms': avgResponseTimes,
      'response_time_percentiles': responseTimePercentiles,
      'active_requests': _requestStartTimes.length,
      'monitoring_active': _isMonitoring,
    };
  }

  /// Get detailed metrics for a specific provider
  Map<String, dynamic> getProviderMetrics(String providerName) {
    final totalRequests = _requestsPerProvider[providerName] ?? 0;
    final responseTimesForProvider = _responseTimesMs[providerName] ?? [];

    double avgResponseTime = 0;
    if (responseTimesForProvider.isNotEmpty) {
      avgResponseTime = responseTimesForProvider.reduce((a, b) => a + b) /
          responseTimesForProvider.length;
    }

    return {
      'total_requests': totalRequests,
      'avg_response_time_ms': avgResponseTime,
      'response_times': responseTimesForProvider,
    };
  }

  /// Get detailed metrics for a specific tool
  Map<String, dynamic> getToolMetrics(String toolName) {
    final totalCalls = _toolCallsPerTool[toolName] ?? 0;

    return {
      'total_calls': totalCalls,
    };
  }

  /// Log performance metrics
  void _logPerformanceMetrics() {
    final report = getMetricsReport();
    _logger.info('=== Performance Metrics ===');
    _logger.info('Total Requests: ${report['total_requests']}');
    _logger.info('Success Rate: ${report['success_rate']}');
    _logger.info('Tool Call Success Rate: ${report['tool_call_success_rate']}');
    _logger.info('Active Requests: ${report['active_requests']}');

    // Log provider stats
    if (_requestsPerProvider.isNotEmpty) {
      _logger.info('Provider Stats:');
      for (final entry in _requestsPerProvider.entries) {
        final avgTime = report['avg_response_times_ms'][entry.key] ?? 'N/A';
        _logger.info('  ${entry.key}: ${entry.value} reqs, avg: ${avgTime}ms');
      }
    }

    _logger.info('===========================');
  }
}