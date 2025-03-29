import '../../mcp_llm.dart';

/// 여러 LLM에 대한 병렬 작업을 관리하는 클래스
class ParallelExecutor {
  final List<LlmInterface> _providers;
  final ResultAggregator _aggregator;
  final Logger _logger = Logger.getLogger('mcp_llm.parallel_executor');

  ParallelExecutor({
    required List<LlmInterface> providers,
    ResultAggregator? aggregator,
  }) : _providers = providers,
        _aggregator = aggregator ?? SimpleResultAggregator();

  /// 여러 LLM 제공자에게 병렬로 요청 실행
  Future<LlmResponse> executeParallel(LlmRequest request) async {
    final futures = <Future<LlmResponse>>[];

    // 모든 제공자에 대해 병렬로 요청 실행
    for (final provider in _providers) {
      futures.add(_executeWithTimeout(provider, request));
    }

    // 모든 결과 수집
    final responses = await Future.wait(futures);

    // 결과 집계
    return _aggregator.aggregate(responses);
  }

  /// 타임아웃 있는 LLM 요청 실행
  Future<LlmResponse> _executeWithTimeout(
      LlmInterface provider,
      LlmRequest request, {
        Duration timeout = const Duration(seconds: 30),
      }) async {
    try {
      return await provider.complete(request).timeout(timeout);
    } catch (e) {
      _logger.error('Provider execution error: $e');
      return LlmResponse(
        text: 'Error: $e',
        metadata: {'error': e.toString(), 'provider': provider.toString()},
      );
    }
  }
}


