import 'dart:convert';
import 'dart:io';

import '../core/llm_interface.dart';
import '../core/models.dart';
import '../utils/logger.dart';
import 'provider.dart';

/// Implementation of LLM interface for Together AI API
class TogetherProvider implements LlmInterface {
  final String apiKey;
  final String model;
  final String? baseUrl;
  final Map<String, dynamic>? options;
  final HttpClient _client = HttpClient();
  final Logger _logger = Logger.getLogger('mcp_llm.together_provider');

  TogetherProvider({
    required this.apiKey,
    required this.model,
    this.baseUrl,
    this.options,
  });

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    _logger.debug('Together AI complete request with model: $model');

    try {
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
        _logger.error(error);

        return LlmResponse(
          text: 'Error: Unable to get a response from Together AI.',
          metadata: {'error': error, 'status_code': httpResponse.statusCode},
        );
      }
    } catch (e, stackTrace) {
      _logger.error('Error calling Together API: $e');
      _logger.debug('Stack trace: $stackTrace');

      return LlmResponse(
        text: 'Error: Unable to get a response from Together AI.',
        metadata: {'error': e.toString()},
      );
    }
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    _logger.debug('Together AI stream request with model: $model');

    try {
      // Build request body
      final requestBody = _buildRequestBody(request);
      requestBody['stream'] = true;

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
                _logger.error('Error parsing chunk: $e');
              }
            }
          }
        }
      } else {
        // Handle error
        final responseBody = await utf8.decoder.bind(httpResponse).join();
        final error = 'Together API Error: ${httpResponse.statusCode} - $responseBody';
        _logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from Together AI.',
          isDone: true,
          metadata: {'error': error, 'status_code': httpResponse.statusCode},
        );
      }
    } catch (e, stackTrace) {
      _logger.error('Error streaming from Together API: $e');
      _logger.debug('Stack trace: $stackTrace');

      yield LlmResponseChunk(
        textChunk: 'Error: Unable to get a streaming response from Together AI.',
        isDone: true,
        metadata: {'error': e.toString()},
      );
    }
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    _logger.debug('Together AI embeddings request');

    try {
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
        _logger.error(error);
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error getting embeddings from Together API: $e');
      _logger.debug('Stack trace: $stackTrace');
      throw Exception('Failed to get embeddings: $e');
    }
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    _logger.info('Together AI provider initialized with model: $model');
  }

  @override
  Future<void> close() async {
    _client.close();
    _logger.debug('Together AI provider client closed');
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
  };

  @override
  LlmInterface createProvider(LlmConfiguration config) {
    // Remove environment variable dependency and only use the config parameter
    final apiKey = config.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('API key is required for Together AI provider');
    }

    return TogetherProvider(
      apiKey: apiKey,
      model: config.model ?? 'together/mistralai/Mixtral-8x7B-Instruct-v0.1',
      baseUrl: config.baseUrl,
      options: config.options,
    );
  }
}