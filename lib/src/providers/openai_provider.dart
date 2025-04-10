import 'dart:convert';
import 'dart:io';

import '../core/llm_interface.dart';
import '../core/models.dart';
import '../utils/logger.dart';
import 'provider.dart';

/// Implementation of LLM interface for OpenAI API
class OpenAiProvider implements LlmInterface, RetryableLlmProvider {
  @override
  final LlmConfiguration config;

  final String apiKey;
  final String model;
  final String? baseUrl;
  final HttpClient _client = HttpClient();

  @override
  final Logger logger = Logger.getLogger('mcp_llm.openai_provider');

  OpenAiProvider({
    required this.apiKey,
    required this.model,
    this.baseUrl,
    required this.config,
  });

  // Concrete implementation of the executeWithRetry method from RetryableLlmProvider
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
      logger.debug('OpenAI complete request with model: $model');

      // Build request body
      final requestBody = _buildRequestBody(request);

      // Prepare API request
      final uri = Uri.parse(baseUrl ?? 'https://api.openai.com/v1/chat/completions');
      final httpRequest = await _client.postUrl(uri);

      // Set headers
      httpRequest.headers.set('Content-Type', 'application/json');
      httpRequest.headers.set('Authorization', 'Bearer $apiKey');

      // Add request body
      final jsonString = jsonEncode(requestBody);
      final encodedBody = utf8.encode(jsonString);
      httpRequest.contentLength = encodedBody.length;
      httpRequest.add(encodedBody);

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
        final error = 'OpenAI API Error: ${httpResponse.statusCode} - $responseBody';
        logger.error(error);

        throw Exception(error);
      }
    });
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    try {
      logger.debug('OpenAI stream request with model: $model');

      // Build request body
      final requestBody = _buildRequestBody(request);
      requestBody['stream'] = true;

      // Prepare API request with retry for connection phase
      final uri = Uri.parse(baseUrl ?? 'https://api.openai.com/v1/chat/completions');
      final httpRequest = await executeWithRetry(() async {
        return await _client.postUrl(uri);
      });

      // Set headers
      httpRequest.headers.set('Content-Type', 'application/json');
      httpRequest.headers.set('Authorization', 'Bearer $apiKey');

      // Add request body
      final jsonString = jsonEncode(requestBody);
      final encodedBody = utf8.encode(jsonString);
      httpRequest.contentLength = encodedBody.length;
      httpRequest.add(encodedBody);

      // Get response with retry for connection phase
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
                  final delta = choice['delta'] as Map<String, dynamic>?;

                  if (delta != null && delta.containsKey('content')) {
                    final content = delta['content'] as String? ?? '';

                    yield LlmResponseChunk(
                      textChunk: content,
                      isDone: false,
                      metadata: {},
                    );
                  } else if (delta != null && delta.containsKey('tool_calls')) {
                    // Handle tool calls in streaming
                    final toolCalls = delta['tool_calls'] as List<dynamic>?;
                    if (toolCalls != null && toolCalls.isNotEmpty) {
                      final toolCall = toolCalls.first as Map<String, dynamic>;
                      final toolName = toolCall['function']?['name'] as String?;

                      if (toolName != null) {
                        yield LlmResponseChunk(
                          textChunk: '',
                          isDone: false,
                          metadata: {
                            'tool_call_start': true,
                            'tool_name': toolName,
                            'tool_call_id': toolCall['id'],
                          },
                        );
                      }

                      // Handle tool arguments
                      final args = toolCall['function']?['arguments'] as String?;
                      if (args != null && args.isNotEmpty) {
                        try {
                          final argsMap = jsonDecode(args) as Map<String, dynamic>;
                          yield LlmResponseChunk(
                            textChunk: '',
                            isDone: false,
                            metadata: {
                              'tool_call_args': argsMap,
                            },
                          );
                        } catch (e) {
                          logger.warning('Error parsing tool args: $e');
                        }
                      }
                    }
                  }

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
        final error = 'OpenAI API Error: ${httpResponse.statusCode} - $responseBody';
        logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from OpenAI.',
          isDone: true,
          metadata: {'error': error, 'status_code': httpResponse.statusCode},
        );
      }
    } catch (e) {
      logger.error('Error streaming from OpenAI API: $e');

      yield LlmResponseChunk(
        textChunk: 'Error: Unable to get a streaming response from OpenAI.',
        isDone: true,
        metadata: {'error': e.toString()},
      );
    }
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return await executeWithRetry(() async {
      logger.debug('OpenAI embeddings request');

      // Prepare API request
      final uri = Uri.parse(baseUrl ?? 'https://api.openai.com/v1/embeddings');
      final httpRequest = await _client.postUrl(uri);

      // Set headers
      httpRequest.headers.set('Content-Type', 'application/json');
      httpRequest.headers.set('Authorization', 'Bearer $apiKey');

      // Add request body
      final requestBody = {
        'input': text,
        'model': 'text-embedding-3-large',
      };
      //httpRequest.write(jsonEncode(requestBody));
      final jsonString = jsonEncode(requestBody);
      final encodedBody = utf8.encode(jsonString);
      httpRequest.contentLength = encodedBody.length;
      httpRequest.add(encodedBody);

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
          throw StateError('No embedding data returned from OpenAI API');
        }
      } else {
        // Handle error
        final error = 'OpenAI API Error: ${httpResponse.statusCode} - $responseBody';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    logger.info('OpenAI provider initialized with model: $model');
  }

  @override
  Future<void> close() async {
    _client.close();
    logger.debug('OpenAI provider client closed');
  }

  // Helper method to build request body
  Map<String, dynamic> _buildRequestBody(LlmRequest request) {
    // Build messages
    final List<Map<String, dynamic>> messages = [];
    String? systemContent;

    // Check for system message in parameters
    if (request.parameters.containsKey('system') ||
        request.parameters.containsKey('system_instructions')) {
      systemContent = request.parameters['system'] ??
          request.parameters['system_instructions'];
    }

    // Extract system message from history
    for (final message in request.history) {
      if (message.role == 'system') {
        // Use system message from history if none in parameters
        if (systemContent == null || systemContent.isEmpty) {
          systemContent = message.content.toString();
        }
        // Skip adding system message here (will be added later)
        continue;
      } else if (message.role == 'tool') {
        // Process tool message
        final toolContent = message.content;
        dynamic toolResult = '';
        String toolCallId = '';

        if (toolContent is Map) {
          if (toolContent.containsKey('content')) {
            toolResult = toolContent['content'];
          }
          // Use tool_call_id if available
          if (message.metadata.containsKey('tool_call_id')) {
            toolCallId = message.metadata['tool_call_id'].toString();
          } else if (toolContent.containsKey('tool_call_id')) {
            toolCallId = toolContent['tool_call_id'].toString();
          } else {
            // Generate random ID if not in metadata
            toolCallId = 'call_${DateTime.now().millisecondsSinceEpoch}';
          }
        }

        messages.add({
          'role': 'tool', // Use OpenAI's 'tool' role
          'tool_call_id': toolCallId,
          'content': toolResult.toString(),
        });
      } else if (message.role == 'assistant' && message.metadata.containsKey('tool_call')) {
        // Process assistant message with tool call
        final toolCallContent = message.content;
        if (toolCallContent is Map && toolCallContent.containsKey('tool_calls')) {
          messages.add({
            'role': 'assistant',
            'content': null,
            'tool_calls': toolCallContent['tool_calls'],
          });
        } else {
          messages.add({
            'role': message.role,
            'content': _convertContentToOpenAiFormat(message.content),
          });
        }
      } else {
        // Process regular message
        messages.add({
          'role': message.role,
          'content': _convertContentToOpenAiFormat(message.content),
        });
      }
    }

    // Add system message if present
    if (systemContent != null && systemContent.isNotEmpty) {
      messages.insert(0, {
        'role': 'system',
        'content': systemContent,
      });
    }

    // Add current prompt
    messages.add({
      'role': 'user',
      'content': request.prompt,
    });

    // Build request body
    final Map<String, dynamic> body = {
      'model': model,
      'messages': messages,
      'max_tokens': request.parameters['max_tokens'] ?? 1024,
      'temperature': request.parameters['temperature'] ?? 0.7,
    };

    if (request.parameters.containsKey('top_p')) {
      body['top_p'] = request.parameters['top_p'];
    }

    // Add tool configuration if provided
    if (request.parameters.containsKey('tools')) {
      final tools = request.parameters['tools'] as List<dynamic>;
      body['tools'] = tools.map((tool) {
        return {
          'type': 'function',
          'function': {
            'name': tool['name'],
            'description': tool['description'],
            'parameters': tool['parameters'],
          }
        };
      }).toList();

      // Enable tool calling
      body['tool_choice'] = 'auto';
    }

    logger.debug('OpenAI API request body prepared: ${body.keys.join(', ')}');
    return body;
  }

  // Helper method to convert content to OpenAI format
  dynamic _convertContentToOpenAiFormat(dynamic content) {
    // If it's a string, return as is
    if (content is String) {
      return content;
    }

    // If it's a map, convert to OpenAI format
    if (content is Map) {
      // Handle image content
      if (content['type'] == 'image') {
        return {
          'type': 'image_url',
          'image_url': {
            'url': content['url'] ?? content['base64Data'] != null
                ? 'data:${content['mimeType']};base64,${content['base64Data']}'
                : '',
          }
        };
      }

      // Handle text content
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
    final choices = response['choices'] as List<dynamic>;
    final choice = choices.first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>;

    // Extract text content
    String text = '';
    final content = message['content'];
    if (content != null && content is String) {
      text = content;
    }

    // Extract tool calls if any
    List<LlmToolCall>? toolCalls;
    final toolCallsList = message['tool_calls'] as List<dynamic>?;
    if (toolCallsList != null && toolCallsList.isNotEmpty) {
      toolCalls = toolCallsList.map((toolCallData) {
        // Parse tool call
        final id = toolCallData['id'] as String;
        final function = toolCallData['function'] as Map<String, dynamic>;
        final name = function['name'] as String;

        // Parse arguments (comes as JSON string)
        Map<String, dynamic> arguments;
        try {
          arguments = jsonDecode(function['arguments'] as String) as Map<String, dynamic>;
        } catch (e) {
          logger.warning('Error parsing tool arguments: $e');
          arguments = {'_error': 'Failed to parse arguments'};
        }

        // ID를 반드시 포함
        return LlmToolCall(
          id: id,  // ID 유지하여 반환
          name: name,
          arguments: arguments,
        );
      }).toList();
    }

    // Build metadata
    final metadata = <String, dynamic>{
      'model': response['model'],
      'finish_reason': choice['finish_reason'],
    };

    // Add usage info if available
    if (response.containsKey('usage')) {
      metadata['usage'] = response['usage'];
    }

    // 도구 호출 ID 정보도 메타데이터에 추가
    if (toolCalls != null && toolCalls.isNotEmpty) {
      metadata['tool_call_ids'] = toolCalls.map((tc) => tc.id).toList();
    }

    return LlmResponse(
      text: text,
      metadata: metadata,
      toolCalls: toolCalls,
    );
  }
}

/// Factory for creating OpenAI providers
class OpenAiProviderFactory implements LlmProviderFactory {
  @override
  String get name => 'openai';

  @override
  Set<LlmCapability> get capabilities => {
    LlmCapability.completion,
    LlmCapability.streaming,
    LlmCapability.embeddings,
    LlmCapability.toolUse,
    LlmCapability.imageUnderstanding,
    LlmCapability.functionCalling,
  };

  @override
  LlmInterface createProvider(LlmConfiguration config) {
    final apiKey = config.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('API key is required for OpenAI provider');
    }

    return OpenAiProvider(
      apiKey: apiKey,
      model: config.model ?? 'gpt-4o',
      baseUrl: config.baseUrl,
      config: config,
    );
  }
}