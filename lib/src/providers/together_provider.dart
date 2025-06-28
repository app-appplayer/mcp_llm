import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/llm_interface.dart';
import '../core/models.dart';
import '../utils/logger.dart';
import 'provider.dart';

/// Implementation of LLM interface for Together AI API
class TogetherProvider implements LlmInterface, RetryableLlmProvider {
  @override
  final LlmConfiguration config;

  final String apiKey;
  final String model;
  final String? baseUrl;
  final http.Client _client = http.Client();

  @override
  final Logger logger = Logger('mcp_llm.together_provider');

  TogetherProvider({
    required this.apiKey,
    required this.model,
    this.baseUrl,
    required this.config,
  });

  // Concrete implementation of the executeWithRetry method
  @override
  Future<T> executeWithRetry<T>(Future<T> Function() operation) async {
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

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return await executeWithRetry(() async {
      logger.debug('Together AI complete request with model: $model');

      // Build request body
      final requestBody = _buildRequestBody(request);

      // Prepare API request
      final uri = Uri.parse(baseUrl ?? 'https://api.together.xyz/v1/completions');
      
      // Set headers
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      // Send request
      final httpResponse = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      // Handle response
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(httpResponse.body) as Map<String, dynamic>;

        // Parse response
        return _parseResponse(responseJson);
      } else {
        // Handle error
        final error = 'Together API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    try {
      logger.debug('Together AI stream request with model: $model');

      // Build request body
      final requestBody = _buildRequestBody(request);
      requestBody['stream'] = true;

      // Prepare API request
      final uri = Uri.parse(baseUrl ?? 'https://api.together.xyz/v1/completions');
      
      // Set headers
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      // Create streaming request
      final httpRequest = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = jsonEncode(requestBody);

      // Send request and get streaming response
      final streamedResponse = await executeWithRetry(() async {
        return await _client.send(httpRequest);
      });

      if (streamedResponse.statusCode >= 200 && streamedResponse.statusCode < 300) {
        // Handle streaming response
        await for (final chunk in utf8.decoder.bind(streamedResponse.stream)) {
          // Parse SSE format
          for (final line in chunk.split('\n')) {
            if (line.startsWith('data: ') && line.length > 6) {
              final data = line.substring(6);
              if (data == '[DONE]') {
                // Streaming complete
                break;
              }

              try {
                final chunkJson = jsonDecode(data) as Map<String, dynamic>;
                final choices = chunkJson['choices'] as List<dynamic>?;

                if (choices != null && choices.isNotEmpty) {
                  final choice = choices.first as Map<String, dynamic>;
                  final text = choice['text'] as String? ?? '';

                  yield LlmResponseChunk(
                    textChunk: text,
                    isDone: false,
                    metadata: {},
                  );

                  // Check for finish reason
                  final finishReason = choice['finish_reason'] as String?;
                  if (finishReason != null && finishReason != 'null') {
                    yield LlmResponseChunk(
                      textChunk: '',
                      isDone: true,
                      metadata: {'finish_reason': finishReason},
                    );
                  }
                }
              } catch (e) {
                logger.error('Error parsing chunk: $e');
              }
            }
          }
        }
      } else {
        // Handle error
        final responseBody = await utf8.decoder.bind(streamedResponse.stream).join();
        final error = 'Together API Error: ${streamedResponse.statusCode} - $responseBody';
        logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from Together AI.',
          isDone: true,
          metadata: {'error': error, 'status_code': streamedResponse.statusCode},
        );
      }
    } catch (e) {
      logger.error('Error streaming from Together API: $e');

      yield LlmResponseChunk(
        textChunk: 'Error: Unable to get a streaming response from Together AI.',
        isDone: true,
        metadata: {'error': e.toString()},
      );
    }
  }

  @override
  bool hasToolCallMetadata(Map<String, dynamic> metadata) {
    // Together models do not currently support tool calls, so return false
    return false;
  }

  @override
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) {
    // Together models do not currently support tool calls, so return null
    return null;
  }

  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) {
    // Convert Together's metadata to a standardized format
    final standardizedMetadata = Map<String, dynamic>.from(metadata);

    // Keep the finish_reason field if it exists
    if (metadata.containsKey('finish_reason')) {
      // No changes needed as it's already in the standard format
    }

    // Keep the error field if it exists
    if (metadata.containsKey('error')) {
      // No changes needed as it's already in the standard format
    }

    return standardizedMetadata;
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return await executeWithRetry(() async {
      logger.debug('Together AI embeddings request');

      // Prepare API request
      final uri = Uri.parse(baseUrl ?? 'https://api.together.xyz/v1/embeddings');
      
      // Set headers
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      // Add request body
      final requestBody = {
        'input': text,
        'model': 'togethercomputer/m2-bert-80M-8k-retrieval',
      };

      // Send request
      final httpResponse = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      // Handle response
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(httpResponse.body) as Map<String, dynamic>;

        final data = responseJson['data'] as List<dynamic>;
        if (data.isNotEmpty) {
          final embedding = data.first['embedding'] as List<dynamic>;
          return embedding.cast<double>();
        } else {
          throw StateError('No embedding data returned from Together API');
        }
      } else {
        // Handle error
        final error = 'Together API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    logger.info('Together AI provider initialized with model: $model');
  }

  @override
  Future<void> close() async {
    _client.close();
    logger.debug('Together AI provider client closed');
  }

  // Helper method to build request body
  Map<String, dynamic> _buildRequestBody(LlmRequest request) {
    // Build prompt
    String fullPrompt = '';

    // Add system instruction if provided
    if (request.parameters.containsKey('system')) {
      fullPrompt += '<system>${request.parameters['system']}</system>\n';
    }

    // Add chat history
    for (final message in request.history) {
      final role = message.role.toLowerCase();
      final content = message.content is String
          ? message.content as String
          : jsonEncode(message.content);

      fullPrompt += '<$role>$content</$role>\n';
    }

    // Add current prompt
    fullPrompt += '<user>${request.prompt}</user>\n';
    fullPrompt += '<assistant>';

    // Build request body
    final Map<String, dynamic> body = {
      'model': model,
      'prompt': fullPrompt,
      'max_tokens': request.parameters['max_tokens'] ?? 1024,
      'temperature': request.parameters['temperature'] ?? 0.7,
      'stop': ['</assistant>'],
    };

    // Add optional parameters
    if (request.parameters.containsKey('top_p')) {
      body['top_p'] = request.parameters['top_p'];
    }

    if (request.parameters.containsKey('frequency_penalty')) {
      body['frequency_penalty'] = request.parameters['frequency_penalty'];
    }

    if (request.parameters.containsKey('presence_penalty')) {
      body['presence_penalty'] = request.parameters['presence_penalty'];
    }

    return body;
  }

  // Helper method to parse response
  LlmResponse _parseResponse(Map<String, dynamic> response) {
    // Extract text
    final choices = response['choices'] as List<dynamic>;
    final choice = choices.first as Map<String, dynamic>;
    final text = choice['text'] as String? ?? '';

    // Build metadata
    final metadata = <String, dynamic>{
      'model': response['model'],
      'finish_reason': choice['finish_reason'],
    };

    // Add usage info if available
    if (response.containsKey('usage')) {
      metadata['usage'] = response['usage'];
    }

    return LlmResponse(
      text: text,
      metadata: metadata,
    );
  }
}

/// Factory for creating Together AI providers
class TogetherProviderFactory implements LlmProviderFactory {
  @override
  String get name => 'together';

  @override
  Set<LlmCapability> get capabilities => {
    LlmCapability.completion,
    LlmCapability.streaming,
    LlmCapability.embeddings,
  };

  @override
  LlmInterface createProvider(LlmConfiguration config) {
    final apiKey = config.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('API key is required for Together AI provider');
    }

    return TogetherProvider(
      apiKey: apiKey,
      model: config.model ?? 'together/mistralai/Mixtral-8x7B-Instruct-v0.1',
      baseUrl: config.baseUrl,
      config: config,
    );
  }
}
