import '../utils/logger.dart';
import 'models.dart';

/// LLM provider interface for mcp_llm internal use.
///
/// This is mcp_llm's internal interface using its own type system.
/// For integration with other MCP packages, use LlmPortAdapter which
/// implements mcp_bundle.LlmPort and converts between type systems.
abstract class LlmProvider {
  /// Initialize the LLM with configuration.
  ///
  /// [config] The configuration for the LLM.
  ///
  /// Throws [AuthenticationError] if API key is invalid.
  /// Throws [ValidationError] if configuration is invalid.
  Future<void> initialize(LlmConfiguration config);

  /// Close and cleanup resources.
  Future<void> close();

  /// Complete a request using mcp_llm's internal types.
  Future<LlmResponse> complete(LlmRequest request);

  /// Stream completion using mcp_llm's internal types.
  Stream<LlmResponseChunk> streamComplete(LlmRequest request);

  /// Get embeddings for text.
  Future<List<double>> getEmbeddings(String text);

  /// Checks if a metadata map contains tool call information.
  ///
  /// [metadata] The metadata map to check.
  ///
  /// Returns true if the metadata contains tool call information.
  bool hasToolCallMetadata(Map<String, dynamic> metadata);

  /// Extracts a tool call from metadata if present.
  ///
  /// [metadata] The metadata map to extract from.
  ///
  /// Returns a tool call if one could be extracted, null otherwise.
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata);

  /// Standardizes the provider-specific metadata to a common format.
  /// This can be used to ensure consistent metadata across different providers.
  ///
  /// [metadata] The original provider-specific metadata.
  ///
  /// Returns a standardized metadata map.
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata);

  /// Whether this provider applies the [CacheHints] on a request.
  /// Providers that do not implement prompt caching return `false` and
  /// silently ignore hints. See `mcp_llm` package docs for the per-
  /// provider default policy when `LlmRequest.cacheHints` is null.
  bool get supportsPromptCaching => false;
}

/// Extension to add retry capabilities to LLM providers.
extension RetryCapabilities on LlmProvider {
  /// Execute request with retry logic.
  Future<T> executeWithRetry<T>({
    required Future<T> Function() operation,
    required LlmConfiguration config,
    required Logger logger,
  }) async {
    if (!config.retryOnFailure) {
      return await operation();
    }

    int attempts = 0;
    Duration currentDelay = config.retryDelay;

    while (true) {
      try {
        return await operation().timeout(config.timeout);
      } catch (e, stackTrace) {
        attempts++;

        if (attempts >= config.maxRetries) {
          logger.error('Operation failed after $attempts attempts: $e');
          throw Exception('Max retry attempts reached: $e\n$stackTrace');
        }

        logger.warning(
            'Attempt $attempts failed, retrying in ${currentDelay.inMilliseconds}ms: $e');
        await Future.delayed(currentDelay);

        // Apply exponential backoff if enabled
        if (config.useExponentialBackoff) {
          currentDelay = Duration(
            milliseconds: (currentDelay.inMilliseconds * 2)
                .clamp(0, config.maxRetryDelay.inMilliseconds),
          );
        }
      }
    }
  }
}

/// Backward compatibility: LlmInterface is now an alias for LlmProvider.
@Deprecated('Use LlmProvider instead')
typedef LlmInterface = LlmProvider;
