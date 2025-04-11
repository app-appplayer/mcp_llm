import '../../mcp_llm.dart';

/// Interface for LLM providers
abstract class LlmInterface {
  /// Generate a completion from the LLM
  ///
  /// [request] The request containing prompt, parameters and history
  ///
  /// Returns a response with generated text
  ///
  /// Throws [AuthenticationError] if API key is invalid
  /// Throws [TimeoutError] if request times out
  /// Throws [NetworkError] if connection fails
  Future<LlmResponse> complete(LlmRequest request);

  /// Stream a completion from the LLM
  ///
  /// [request] The request containing prompt, parameters and history
  ///
  /// Returns a stream of response chunks
  ///
  /// Throws [AuthenticationError] if API key is invalid
  /// Throws [NetworkError] if connection fails
  Stream<LlmResponseChunk> streamComplete(LlmRequest request);

  /// Get embeddings for text
  ///
  /// [text] The text to embed
  ///
  /// Returns a vector of floating-point numbers representing the text
  ///
  /// Throws [AuthenticationError] if API key is invalid
  /// Throws [TimeoutError] if request times out
  Future<List<double>> getEmbeddings(String text);

  /// Initialize the LLM with configuration
  ///
  /// [config] The configuration for the LLM
  ///
  /// Throws [AuthenticationError] if API key is invalid
  /// Throws [ValidationError] if configuration is invalid
  Future<void> initialize(LlmConfiguration config);

  /// Close and cleanup resources
  Future<void> close();

  /// Checks if a metadata map contains tool call information
  ///
  /// [metadata] The metadata map to check
  ///
  /// Returns true if the metadata contains tool call information
  bool hasToolCallMetadata(Map<String, dynamic> metadata);

  /// Extracts a tool call from metadata if present
  ///
  /// [metadata] The metadata map to extract from
  ///
  /// Returns a tool call if one could be extracted, null otherwise
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata);

  /// Standardizes the provider-specific metadata to a common format
  /// This can be used to ensure consistent metadata across different providers
  ///
  /// [metadata] The original provider-specific metadata
  ///
  /// Returns a standardized metadata map
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata);
}

/// Extension to add retry capabilities to LLM providers
extension RetryCapabilities on LlmInterface {
  /// Execute request with retry logic
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

        logger.warning('Attempt $attempts failed, retrying in ${currentDelay.inMilliseconds}ms: $e');
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