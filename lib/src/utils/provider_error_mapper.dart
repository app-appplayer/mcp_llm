import '../utils/error_handler.dart';

class ProviderErrorMapper {
  // Map provider-specific errors to standardized McpLlmError
  static McpLlmError mapError(dynamic error, String providerName, {StackTrace? stackTrace}) {
    // Check if already an McpLlmError
    if (error is McpLlmError) {
      return error;
    }

    // Map error based on provider and error message pattern
    if (providerName.toLowerCase() == 'openai') {
      return _mapOpenAiError(error, stackTrace);
    } else if (providerName.toLowerCase() == 'claude' ||
        providerName.toLowerCase() == 'anthropic') {
      return _mapClaudeError(error, stackTrace);
    } else if (providerName.toLowerCase() == 'together') {
      return _mapTogetherError(error, stackTrace);
    }

    // Default error mapping
    return McpLlmError(
      'Provider error: $error',
      type: ErrorType.provider,
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  // Map OpenAI-specific errors
  static McpLlmError _mapOpenAiError(dynamic error, StackTrace? stackTrace) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('authentication') || errorStr.contains('api key')) {
      return AuthenticationError(
        'OpenAI authentication error: $error',
        originalError: error,
        stackTrace: stackTrace,
      );
    } else if (errorStr.contains('rate limit') || errorStr.contains('ratelimit')) {
      return McpLlmError(
        'OpenAI rate limit exceeded: $error',
        type: ErrorType.provider,
        originalError: error,
        stackTrace: stackTrace,
      );
    } else if (errorStr.contains('timeout')) {
      return TimeoutError(
        'OpenAI request timed out: $error',
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    return ProviderError(
      'OpenAI error: $error',
      providerName: 'openai',
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  // Map Claude-specific errors
  static McpLlmError _mapClaudeError(dynamic error, StackTrace? stackTrace) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('authentication') || errorStr.contains('api key')) {
      return AuthenticationError(
        'Claude authentication error: $error',
        originalError: error,
        stackTrace: stackTrace,
      );
    } else if (errorStr.contains('rate limit') || errorStr.contains('ratelimit')) {
      return McpLlmError(
        'Claude rate limit exceeded: $error',
        type: ErrorType.provider,
        originalError: error,
        stackTrace: stackTrace,
      );
    } else if (errorStr.contains('timeout')) {
      return TimeoutError(
        'Claude request timed out: $error',
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    return ProviderError(
      'Claude error: $error',
      providerName: 'claude',
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  // Map Together-specific errors
  static McpLlmError _mapTogetherError(dynamic error, StackTrace? stackTrace) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('authentication') || errorStr.contains('api key')) {
      return AuthenticationError(
        'Together AI authentication error: $error',
        originalError: error,
        stackTrace: stackTrace,
      );
    } else if (errorStr.contains('rate limit') || errorStr.contains('ratelimit')) {
      return McpLlmError(
        'Together AI rate limit exceeded: $error',
        type: ErrorType.provider,
        originalError: error,
        stackTrace: stackTrace,
      );
    } else if (errorStr.contains('timeout')) {
      return TimeoutError(
        'Together AI request timed out: $error',
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    return ProviderError(
      'Together AI error: $error',
      providerName: 'together',
      originalError: error,
      stackTrace: stackTrace,
    );
  }
}