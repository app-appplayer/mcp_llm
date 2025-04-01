import 'models.dart';

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
}
