/// LLM 및 MCP 사용에 대한 성능 모니터링 시스템
class PerformanceMonitor {
  // 싱글톤 코드 제거

  // 성능 메트릭
  int _totalRequests = 0;
  int _failedRequests = 0;
  int _successfulToolCalls = 0;
  int _failedToolCalls = 0;
  Map<String, int> _requestsPerProvider = {};
  Map<String, int> _toolCallsPerTool = {};
  Map<String, List<int>> _responseTimesMs = {};

  // 모니터링 타이머
  Timer? _monitoringTimer;
  bool _isMonitoring = false;

  // 타임스탬프 - 요청 ID 맵
  final Map<String, DateTime> _requestStartTimes = {};

  // 일반 생성자
  PerformanceMonitor();

  /// 요청 시작 기록
  String startRequest(String providerName) {
    _totalRequests++;
    _requestsPerProvider[providerName] = (_requestsPerProvider[providerName] ?? 0) + 1;

    // 요청 ID 생성
    final requestId = 'req_${DateTime.now().millisecondsSinceEpoch}_${_totalRequests}';
    _requestStartTimes[requestId] = DateTime.now();

    return requestId;
  }

  /// 요청 완료 기록
  void endRequest(String requestId, {bool success = true}) {
    final startTime = _requestStartTimes.remove(requestId);
    if (startTime != null) {
      final duration = DateTime.now().difference(startTime);

      if (!success) {
        _failedRequests++;
      }

      // 응답 시간 기록
      final responseTimeMs = duration.inMilliseconds;
      final provider = requestId.split('_').last;
      if (!_responseTimesMs.containsKey(provider)) {
        _responseTimesMs[provider] = [];
      }
      _responseTimesMs[provider]!.add(responseTimeMs);
    }
  }

  /// 도구 호출 기록
  void recordToolCall(String toolName, {bool success = true}) {
    if (success) {
      _successfulToolCalls++;
    } else {
      _failedToolCalls++;
    }

    _toolCallsPerTool[toolName] = (_toolCallsPerTool[toolName] ?? 0) + 1;
  }

  /// 메트릭 초기화
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

  /// 모니터링 시작
  void startMonitoring(Duration interval) {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _monitoringTimer = Timer.periodic(interval, (_) {
      _logPerformanceMetrics();
    });

    log.info('Performance monitoring started with interval: ${interval.inSeconds}s');
  }

  /// 모니터링 중지
  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _isMonitoring = false;

    log.info('Performance monitoring stopped');
  }

  /// 현재 메트릭 보고서 가져오기
  Map<String, dynamic> getMetricsReport() {
    // 평균 응답 시간 계산
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
          ? ((_totalRequests - _failedRequests) / _totalRequests * 100).toStringAsFixed(2) + '%'
          : 'N/A',
      'total_tool_calls': _successfulToolCalls + _failedToolCalls,
      'successful_tool_calls': _successfulToolCalls,
      'tool_call_success_rate': (_successfulToolCalls + _failedToolCalls) > 0
          ? (_successfulToolCalls / (_successfulToolCalls + _failedToolCalls) * 100).toStringAsFixed(2) + '%'
          : 'N/A',
      'requests_per_provider': _requestsPerProvider,
      'tool_calls_per_tool': _toolCallsPerTool,
      'avg_response_times_ms': avgResponseTimes,
      'active_requests': _requestStartTimes.length,
    };
  }

  /// 성능 메트릭 로깅
  void _logPerformanceMetrics() {
    final report = getMetricsReport();
    log.info('=== Performance Metrics ===');
    log.info('Total Requests: ${report['total_requests']}');
    log.info('Success Rate: ${report['success_rate']}');
    log.info('Tool Call Success Rate: ${report['tool_call_success_rate']}');
    log.info('Active Requests: ${report['active_requests']}');
    log.info('===========================');
  }
}