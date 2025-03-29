import 'models.dart';

/// Interface for LLM providers
abstract class LlmInterface {
  /// Generate a completion from the LLM
  Future<LlmResponse> complete(LlmRequest request);

  /// Stream a completion from the LLM
  Stream<LlmResponseChunk> streamComplete(LlmRequest request);

  /// Get embeddings for text
  Future<List<double>> getEmbeddings(String text);

  /// Initialize the LLM with configuration
  Future<void> initialize(LlmConfiguration config);

  /// Close and cleanup resources
  Future<void> close();
}
