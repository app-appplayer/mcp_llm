import 'dart:convert';
import 'dart:io';

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
  final HttpClient _client = HttpClient();

  @override
  final Logger logger = Logger.getLogger('mcp_llm.together_provider');

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
      final httpRequest = await _client.postUrl(uri);

      // Set headers
      httpRequest.headers.set('Content-Type', 'application/json');
      httpRequest.headers.set('Authorization', 'Bearer $apiKey');

      // Add request body
      httpRequest.write(jsonEncode(requestBody));

      // Get response
      final httpResponse = await httpRequest.close();
      final responseBody = await utf8.decoder.bind(httpResponse).join();

      // Handle response
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(responseBody) as Map<String, dynamic>;

        // Parse response
        return _parseResponse(responseJson);
      } else {
        // Handle error
        final error = 'Together API Error: ${httpResponse.statusCode} - $responseBody';
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

      // Prepare API request with retry for connection phase
      final uri = Uri.parse(baseUrl ?? 'https://api.together.xyz/v1/completions');
      final httpRequest = await executeWithRetry(() async {
        return await _client.postUrl(uri);
      });

      // Set headers
      httpRequest.headers.set('Content-Type', 'application/json');
      httpRequest.headers.set('Authorization', 'Bearer $apiKey');

      // Add request body
      httpRequest.write(jsonEncode(requestBody));

      // Get response with retry
      final httpResponse = await executeWithRetry(() async {
        return await httpRequest.close();
      });

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        // Handle streaming response
        await for (final chunk in utf8.decoder.bind(httpResponse)) {
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
        final responseBody = await utf8.decoder.bind(httpResponse).join();
        final error = 'Together API Error: ${httpResponse.statusCode} - $responseBody';
        logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from Together AI.',
          isDone: true,
          metadata: {'error': error, 'status_code': httpResponse.statusCode},
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
    // Together 모델은 현재 도구 호출을 지원하지 않으므로 false 반환
    return false;
  }

  @override
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) {
    // Together 모델은 현재 도구 호출을 지원하지 않으므로 null 반환
    return null;
  }

  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) {
    // Together의 메타데이터를 표준화된 형식으로 변환
    final standardizedMetadata = Map<String, dynamic>.from(metadata);

    // finish_reason 필드가 있으면 유지
    if (metadata.containsKey('finish_reason')) {
      // 이미 표준 형식이므로 변경 불필요
    }

    // error 필드가 있으면 유지
    if (metadata.containsKey('error')) {
      // 이미 표준 형식이므로 변경 불필요
    }

    return standardizedMetadata;
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return await executeWithRetry(() async {
      logger.debug('Together AI embeddings request');

      // Prepare API request
      final uri = Uri.parse(baseUrl ?? 'https://api.together.xyz/v1/embeddings');
      final httpRequest = await _client.postUrl(uri);

      // Set headers
      httpRequest.headers.set('Content-Type', 'application/json');
      httpRequest.headers.set('Authorization', 'Bearer $apiKey');

      // Add request body
      final requestBody = {
        'input': text,
        'model': 'togethercomputer/m2-bert-80M-8k-retrieval',
      };
      httpRequest.write(jsonEncode(requestBody));

      // Get response
      final httpResponse = await httpRequest.close();
      final responseBody = await utf8.decoder.bind(httpResponse).join();

      // Handle response
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(responseBody) as Map<String, dynamic>;

        final data = responseJson['data'] as List<dynamic>;
        if (data.isNotEmpty) {
          final embedding = data.first['embedding'] as List<dynamic>;
          return embedding.cast<double>();
        } else {
          throw StateError('No embedding data returned from Together API');
        }
      } else {
        // Handle error
        final error = 'Together API Error: ${httpResponse.statusCode} - $responseBody';
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