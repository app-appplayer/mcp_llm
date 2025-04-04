import 'dart:convert';
import 'dart:io';

import '../core/llm_interface.dart';
import '../core/models.dart';
import '../utils/logger.dart';
import 'provider.dart';

/// Implementation of LLM interface for Claude (Anthropic) API
class ClaudeProvider implements LlmInterface, RetryableLlmProvider {
  @override
  final LlmConfiguration config;

  final String apiKey;
  final String model;
  final String? baseUrl;
  final HttpClient _client = HttpClient();

  @override
  final Logger logger = Logger.getLogger('mcp_llm.claude_provider');

  ClaudeProvider({
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
      logger.debug('Claude complete request with model: $model');

      // Configure request data
      final requestBody = _buildRequestBody(request);

      // API request
      final uri = Uri.parse(baseUrl ?? 'https://api.anthropic.com/v1/messages');
      final httpRequest = await _client.postUrl(uri);

      // Set headers
      httpRequest.headers.set('Content-Type', 'application/json');
      httpRequest.headers.set('x-api-key', apiKey);
      httpRequest.headers.set('anthropic-version', '2023-06-01');

      // Add request body
      httpRequest.write(jsonEncode(requestBody));

      // Get response
      final httpResponse = await httpRequest.close();
      final responseBody = await utf8.decoder.bind(httpResponse).join();

      // Parse response
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(responseBody) as Map<String, dynamic>;

        // Create result
        final response = _parseResponse(responseJson);
        return response;
      } else {
        // Handle error
        final error = 'Claude API Error: ${httpResponse.statusCode} - $responseBody';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    try {
      logger.debug('Claude stream request with model: $model');

      // Configure request data
      final requestBody = _buildRequestBody(request);
      requestBody['stream'] = true;

      // API request with retry
      final uri = Uri.parse(baseUrl ?? 'https://api.anthropic.com/v1/messages');
      final httpRequest = await executeWithRetry(() async {
        return await _client.postUrl(uri);
      });

      // Set headers
      httpRequest.headers.set('Content-Type', 'application/json');
      httpRequest.headers.set('x-api-key', apiKey);
      httpRequest.headers.set('anthropic-version', '2023-06-01');

      // Add request body
      httpRequest.write(jsonEncode(requestBody));

      // Get response with retry
      final httpResponse = await executeWithRetry(() async {
        return await httpRequest.close();
      });

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        // Process streaming response
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
                final type = chunkJson['type'] as String?;

                if (type == 'content_block_delta') {
                  final delta = chunkJson['delta'] as Map<String, dynamic>?;
                  if (delta != null && delta.containsKey('text')) {
                    final text = delta['text'] as String? ?? '';

                    yield LlmResponseChunk(
                      textChunk: text,
                      isDone: false,
                      metadata: {},
                    );
                  }
                } else if (type == 'tool_use') {
                  // Tool use response
                  final toolUse = chunkJson['tool_use'] as Map<String, dynamic>?;
                  if (toolUse != null) {
                    yield LlmResponseChunk(
                      textChunk: '',
                      isDone: false,
                      metadata: {
                        'tool_call_start': true,
                        'tool_name': toolUse['name'],
                        'tool_call_id': toolUse['id'],
                      },
                    );
                  }
                } else if (type == 'tool_use_input_delta') {
                  // Tool input data
                  final delta = chunkJson['delta'] as Map<String, dynamic>?;
                  final inputDelta = delta?['input'] as Map<String, dynamic>?;
                  if (inputDelta != null) {
                    yield LlmResponseChunk(
                      textChunk: '',
                      isDone: false,
                      metadata: {
                        'tool_call_args': inputDelta,
                      },
                    );
                  }
                } else if (type == 'message_stop') {
                  // Message stop
                  yield LlmResponseChunk(
                    textChunk: '',
                    isDone: true,
                    metadata: {'complete': true},
                  );
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
        final error = 'Claude API Error: ${httpResponse.statusCode} - $responseBody';
        logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from Claude.',
          isDone: true,
          metadata: {'error': error, 'status_code': httpResponse.statusCode},
        );
      }
    } catch (e) {
      logger.error('Error streaming from Claude API: $e');

      yield LlmResponseChunk(
        textChunk: 'Error: Unable to get a streaming response from Claude.',
        isDone: true,
        metadata: {'error': e.toString()},
      );
    }
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return await executeWithRetry(() async {
      logger.debug('Claude embeddings request');

      // Prepare API request
      final uri = Uri.parse(baseUrl ?? 'https://api.anthropic.com/v1/embeddings');
      final httpRequest = await _client.postUrl(uri);

      // Set headers
      httpRequest.headers.set('Content-Type', 'application/json');
      httpRequest.headers.set('x-api-key', apiKey);
      httpRequest.headers.set('anthropic-version', '2023-06-01');

      // Add request body
      final requestBody = {
        'model': 'claude-3-haiku-20240307', // Using appropriate embedding model
        'input': text,
        'dimensions': 1536, // Standard embedding dimensions
      };
      httpRequest.write(jsonEncode(requestBody));

      // Get response
      final httpResponse = await httpRequest.close();
      final responseBody = await utf8.decoder.bind(httpResponse).join();

      // Handle response
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(responseBody) as Map<String, dynamic>;
        final embedding = responseJson['embedding'] as List<dynamic>;
        return embedding.cast<double>();
      } else {
        // Handle error
        final error = 'Claude API Error: ${httpResponse.statusCode} - $responseBody';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    // Initialization logic
    logger.info('Claude provider initialized with model: $model');
  }

  @override
  Future<void> close() async {
    _client.close();
    logger.info('Claude provider resources closed');
  }

  // Helper method to build request body
  Map<String, dynamic> _buildRequestBody(LlmRequest request) {
    // Build messages
    final List<Map<String, dynamic>> messages = [];

    // Add history
    for (final message in request.history) {
      messages.add({
        'role': message.role,
        'content': _convertContentToClaudeFormat(message.content),
      });
    }

    // Add current message
    messages.add({
      'role': 'user',
      'content': request.prompt,
    });

    // Build request body
    final Map<String, dynamic> body = {
      'model': model,
      'messages': messages,
      'max_tokens': request.parameters['max_tokens'] ?? 1024,
    };

    // Add system prompt if present
    if (request.parameters.containsKey('system')) {
      body['system'] = request.parameters['system'];
    }

    // Add tool information if present
    if (request.parameters.containsKey('tools')) {
      body['tools'] = request.parameters['tools'];
    }

    // Apply additional parameters
    if (request.parameters.containsKey('temperature')) {
      body['temperature'] = request.parameters['temperature'];
    }

    return body;
  }

  // Convert content to Claude format
  dynamic _convertContentToClaudeFormat(dynamic content) {
    // Return as is if simple text
    if (content is String) {
      return content;
    }

    // Convert message structure
    if (content is Map) {
      // Convert image content
      if (content['type'] == 'image') {
        return {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': content['mimeType'] ?? 'image/jpeg',
            'data': content['data'] ?? content['base64'],
          }
        };
      }

      // Convert text content
      if (content['type'] == 'text') {
        return content['text'];
      }
    }

    // Default to string conversion
    return content.toString();
  }

  // Helper method to parse response
  LlmResponse _parseResponse(Map<String, dynamic> response) {
    // Extract response content
    final content = response['content'] as List<dynamic>;
    final text = content
        .where((item) => item['type'] == 'text')
        .map<String>((item) => item['text'] as String)
        .join('\n');

    // Extract tool calls
    List<LlmToolCall>? toolCalls;
    final toolUses = response['tool_uses'] as List<dynamic>?;
    if (toolUses != null && toolUses.isNotEmpty) {
      toolCalls = toolUses.map((tool) {
        return LlmToolCall(
          name: tool['name'] as String,
          arguments: tool['input'] as Map<String, dynamic>,
        );
      }).toList();
    }

    // Build metadata
    final metadata = <String, dynamic>{
      'model': response['model'],
      'stop_reason': response['stop_reason'],
      'usage': response['usage'],
    };

    return LlmResponse(
      text: text,
      metadata: metadata,
      toolCalls: toolCalls,
    );
  }
}

/// Factory for creating Claude providers
class ClaudeProviderFactory implements LlmProviderFactory {
  @override
  String get name => 'claude';

  @override
  Set<LlmCapability> get capabilities => {
    LlmCapability.completion,
    LlmCapability.streaming,
    LlmCapability.toolUse,
    LlmCapability.imageUnderstanding,
    LlmCapability.embeddings,
  };

  @override
  LlmInterface createProvider(LlmConfiguration config) {
    final apiKey = config.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('API key is required for Claude provider');
    }

    return ClaudeProvider(
      apiKey: apiKey,
      model: config.model ?? 'claude-3-5-sonnet-20241022',
      baseUrl: config.baseUrl,
      config: config,
    );
  }
}