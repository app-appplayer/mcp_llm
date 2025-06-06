import 'dart:core';

import '../core/llm_interface.dart';
import '../core/models.dart';
import '../utils/logger.dart';
import 'provider.dart';

/// Base class for implementing custom LLM providers
abstract class CustomLlmProvider implements LlmInterface {
  /// Logger instance
  final Logger _logger = Logger('mcp_llm.providers.custom');

  /// Provider name
  final String name;

  /// Provider options
  final ProviderOptions options;

  /// Create a custom LLM provider
  CustomLlmProvider({
    required this.name,
    ProviderOptions? options,
  }) : options = options ?? ProviderOptions();

  /// Execute a request with retry logic
  Future<T> _executeWithRetry<T>({
    required Future<T> Function() operation,
    int? maxRetries,
    Duration? retryDelay,
  }) async {
    final attempts = maxRetries ?? options.maxRetries;
    final delay = retryDelay ?? options.retryDelay;

    int currentAttempt = 0;
    Duration currentDelay = delay;

    while (true) {
      try {
        return await operation();
      } catch (e) {
        currentAttempt++;

        if (currentAttempt > attempts) {
          _logger.error('Operation failed after $currentAttempt attempts: $e');
          rethrow;
        }

        _logger.warning(
            'Attempt $currentAttempt failed, retrying in ${currentDelay.inMilliseconds}ms: $e'
        );

        await Future.delayed(currentDelay);

        // exponential backoff
        currentDelay *= 2;
      }
    }
  }


  /// Transform a request for the specific provider
  Future<Map<String, dynamic>> transformRequest(LlmRequest request) async {
    // Base implementation - override in provider-specific subclasses
    return {
      'prompt': request.prompt,
      'temperature': request.parameters['temperature'] ?? 0.7,
      'max_tokens': request.parameters['max_tokens'] ?? 1024,
    };
  }

  /// Transform a response from the provider format
  Future<LlmResponse> transformResponse(Map<String, dynamic> rawResponse) async {
    // Base implementation - override in provider-specific subclasses
    return LlmResponse(
      text: rawResponse['text'] ?? '',
      metadata: {'raw_response': rawResponse},
    );
  }

  /// Transform a streaming chunk from the provider format
  Future<LlmResponseChunk> transformChunk(dynamic rawChunk) async {
    // Base implementation - override in provider-specific subclasses
    if (rawChunk is String) {
      return LlmResponseChunk(textChunk: rawChunk);
    } else if (rawChunk is Map) {
      return LlmResponseChunk(
        textChunk: rawChunk['text'] ?? '',
        isDone: rawChunk['done'] == true,
        metadata: {'raw_chunk': rawChunk},
      );
    } else {
      return LlmResponseChunk(textChunk: rawChunk.toString());
    }
  }

  /// Execute the actual API request - must be implemented by subclasses
  Future<Map<String, dynamic>> executeRequest(
      Map<String, dynamic> requestData,
      String endpoint,
      Map<String, String> headers,
      );

  /// Execute the actual API request - must be implemented by subclasses
  Stream<dynamic> executeStreamingRequest(
      Map<String, dynamic> requestData,
      String endpoint,
      Map<String, String> headers,
      );

  /// Get API headers
  Map<String, String> getHeaders() {
    // Base implementation - override in provider-specific subclasses
    return {
      'Content-Type': 'application/json',
    };
  }

  /// Get API endpoint for completions
  String getCompletionEndpoint() {
    // Override in provider-specific subclasses
    throw UnimplementedError('Completion endpoint not specified');
  }

  /// Get API endpoint for embeddings
  String getEmbeddingEndpoint() {
    // Override in provider-specific subclasses
    throw UnimplementedError('Embedding endpoint not specified');
  }

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return await _executeWithRetry(
      operation: () async {
        _logger.debug('Sending completion request to $name');

        final transformedRequest = await transformRequest(request);
        final headers = getHeaders();
        final endpoint = getCompletionEndpoint();

        final rawResponse = await executeRequest(
          transformedRequest,
          endpoint,
          headers,
        );

        final response = await transformResponse(rawResponse);
        _logger.debug('Received completion response from $name');

        return response;
      },
      maxRetries: options.maxRetries,
      retryDelay: options.retryDelay,
    );
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    try {
      _logger.debug('Sending streaming completion request to $name');

      final transformedRequest = await transformRequest(request);
      // Add streaming flag if not already present
      transformedRequest['stream'] = true;

      final headers = getHeaders();
      final endpoint = getCompletionEndpoint();

      final rawStream = executeStreamingRequest(
        transformedRequest,
        endpoint,
        headers,
      );

      await for (final rawChunk in rawStream) {
        try {
          final chunk = await transformChunk(rawChunk);
          yield chunk;

          if (chunk.isDone) {
            _logger.debug('Streaming completed from $name');
            break;
          }
        } catch (e) {
          _logger.error('Error processing chunk: $e');
          yield LlmResponseChunk(
            textChunk: 'Error processing response: $e',
            isDone: true,
            metadata: {'error': e.toString()},
          );
          break;
        }
      }
    } catch (e) {
      _logger.error('Error in streaming completion: $e');
      yield LlmResponseChunk(
        textChunk: 'Error in streaming: $e',
        isDone: true,
        metadata: {'error': e.toString()},
      );
    }
  }
}

/// Base factory for custom LLM providers
abstract class CustomLlmProviderFactory implements LlmProviderFactory {
  @override
  String get name;

  @override
  Set<LlmCapability> get capabilities;

  @override
  LlmInterface createProvider(LlmConfiguration config);
}