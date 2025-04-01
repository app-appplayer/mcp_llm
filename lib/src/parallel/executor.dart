import '../../mcp_llm.dart';
import '../core/models.dart';

/// Class that manages parallel operations for multiple LLMs
class ParallelExecutor {
  final List<LlmInterface> _providers;
  final ResultAggregator _aggregator;
  final Logger _logger = Logger.getLogger('mcp_llm.parallel_executor');

  ParallelExecutor({
    required List<LlmInterface> providers,
    ResultAggregator? aggregator,
  })  : _providers = providers,
        _aggregator = aggregator ?? SimpleResultAggregator();

  /// Execute requests in parallel to multiple LLM providers
  Future<LlmResponse> executeParallel(LlmRequest request) async {
    final futures = <Future<LlmResponse>>[];

    // Execute requests in parallel for all providers
    for (final provider in _providers) {
      futures.add(_executeWithTimeout(provider, request));
    }

    // Collect all results
    final responses = await Future.wait(futures);

    // Aggregate results
    return _aggregator.aggregate(responses);
  }

  /// Execute LLM request with timeout
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
