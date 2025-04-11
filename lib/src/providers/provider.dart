import '../../mcp_llm.dart';

/// Abstract base class for LLM providers
abstract class LlmProvider implements LlmInterface {
  @override
  Future<LlmResponse> complete(LlmRequest request);

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request);

  @override
  Future<List<double>> getEmbeddings(String text);

  @override
  Future<void> initialize(LlmConfiguration config);

  @override
  Future<void> close();
}


/// Factory interface for creating LLM providers
abstract class LlmProviderFactory {
  /// Provider name
  String get name;

  /// Provider capabilities
  Set<LlmCapability> get capabilities;

  /// Create a provider instance with the given configuration
  LlmInterface createProvider(LlmConfiguration config);
}

/// Configuration options for LLM providers
class ProviderOptions {
  /// Timeout for requests
  final Duration timeout;

  /// Whether to retry failed requests
  final bool retryOnFailure;

  /// Maximum number of retries
  final int maxRetries;

  /// Retry delay
  final Duration retryDelay;

  /// Default model to use
  final String? defaultModel;

  /// Additional provider-specific options
  final Map<String, dynamic> additionalOptions;

  /// Create provider options
  ProviderOptions({
    this.timeout = const Duration(seconds: 30),
    this.retryOnFailure = true,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
    this.defaultModel,
    this.additionalOptions = const {},
  });

  /// Create a copy with modified values
  ProviderOptions copyWith({
    Duration? timeout,
    bool? retryOnFailure,
    int? maxRetries,
    Duration? retryDelay,
    String? defaultModel,
    Map<String, dynamic>? additionalOptions,
  }) {
    return ProviderOptions(
      timeout: timeout ?? this.timeout,
      retryOnFailure: retryOnFailure ?? this.retryOnFailure,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      defaultModel: defaultModel ?? this.defaultModel,
      additionalOptions: additionalOptions ?? this.additionalOptions,
    );
  }
}

/// Interface for LLM providers with retry capabilities
abstract class RetryableLlmProvider {
  /// LLM configuration with retry settings
  LlmConfiguration get config;

  /// Logger for recording retry attempts
  Logger get logger;

  /// Execute an operation with retry logic
  Future<T> executeWithRetry<T>(Future<T> Function() operation);
}