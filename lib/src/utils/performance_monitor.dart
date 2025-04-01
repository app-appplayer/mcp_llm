import 'dart:async';
import '../../mcp_llm.dart';

/// Performance monitoring system for LLM and MCP usage
class PerformanceMonitor {
  // Performance metrics
  int _totalRequests = 0;
  int _failedRequests = 0;
  int _successfulToolCalls = 0;
  int _failedToolCalls = 0;
  Map<String, int> _requestsPerProvider = {};
  Map<String, int> _toolCallsPerTool = {};
  Map<String, List<int>> _responseTimesMs = {};

  // Monitoring timer
  Timer? _monitoringTimer;
  bool _isMonitoring = false;

  // Timestamp - request ID map
  final Map<String, DateTime> _requestStartTimes = {};

  final Logger _logger = Logger.getLogger('mcp_llm.performance_monitor');

  // Default constructor
  PerformanceMonitor();

  /// Record request start
  String startRequest(String providerName) {
    _totalRequests++;
    _requestsPerProvider[providerName] =
        (_requestsPerProvider[providerName] ?? 0) + 1;

    // Generate request ID
    final requestId =
        'req_${DateTime.now().millisecondsSinceEpoch}_${_totalRequests}';
    _requestStartTimes[requestId] = DateTime.now();

    return requestId;
  }

  /// Record request completion
  void endRequest(String requestId, {bool success = true}) {
    final startTime = _requestStartTimes.remove(requestId);
    if (startTime != null) {
      final duration = DateTime.now().difference(startTime);

      if (!success) {
        _failedRequests++;
      }

      // Record response time
      final responseTimeMs = duration.inMilliseconds;
      final provider = requestId.split('_').last;
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
    } else {
      _failedToolCalls++;
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
  }

  /// Start monitoring
  void startMonitoring(Duration interval) {
    if (_isMonitoring) return;

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
    _isMonitoring = false;

    _logger.info('Performance monitoring stopped');
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

    return {
      'total_requests': _totalRequests,
      'failed_requests': _failedRequests,
      'success_rate': _totalRequests > 0
          ? ((_totalRequests - _failedRequests) / _totalRequests * 100)
                  .toStringAsFixed(2) +
              '%'
          : 'N/A',
      'total_tool_calls': _successfulToolCalls + _failedToolCalls,
      'successful_tool_calls': _successfulToolCalls,
      'tool_call_success_rate': (_successfulToolCalls + _failedToolCalls) > 0
          ? (_successfulToolCalls /
                      (_successfulToolCalls + _failedToolCalls) *
                      100)
                  .toStringAsFixed(2) +
              '%'
          : 'N/A',
      'requests_per_provider': _requestsPerProvider,
      'tool_calls_per_tool': _toolCallsPerTool,
      'avg_response_times_ms': avgResponseTimes,
      'active_requests': _requestStartTimes.length,
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
    _logger.info('===========================');
  }
}
