import 'dart:convert';
import 'dart:io';

import '../core/llm_interface.dart';
import '../core/models.dart';
import '../utils/logger.dart';
import 'provider.dart';

/// Implementation of LLM interface for OpenAI API
class OpenAiProvider implements LlmInterface {
  final String apiKey;
  final String model;
  final String? baseUrl;
  final Map<String, dynamic>? options;
  final HttpClient _client = HttpClient();
  final Logger _logger = Logger.getLogger('mcp_llm.openai_provider');

  OpenAiProvider({
    required this.apiKey,
    this.model = 'gpt-4o',
    this.baseUrl,
    this.options,
  });

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    _logger.debug('OpenAI complete request with model: $model');

    try {
      // Build request body
      final requestBody = _buildRequestBody(request);

      // Prepare API request
      final uri = Uri.parse(baseUrl ?? 'https://api.openai.com/v1/chat/completions');
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
        final error = 'OpenAI API Error: ${httpResponse.statusCode} - $responseBody';
        _logger.error(error);

        return LlmResponse(
          text: 'Error: Unable to get a response from OpenAI.',
          metadata: {'error': error, 'status_code': httpResponse.statusCode},
        );
      }
    } catch (e, stackTrace) {
      _logger.error('Error calling OpenAI API: $e');
      _logger.debug('Stack trace: $stackTrace');

      return LlmResponse(
        text: 'Error: Unable to get a response from OpenAI.',
        metadata: {'error': e.toString()},
      );
    }
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    _logger.debug('OpenAI stream request with model: $model');

    try {
      // Build request body
      final requestBody = _buildRequestBody(request);
      requestBody['stream'] = true;

      // Prepare API request
      final uri = Uri.parse(baseUrl ?? 'https://api.openai.com/v1/chat/completions');
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
                          _logger.warning('Error parsing tool args: $e');
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
                _logger.error('Error parsing chunk: $e');
              }
            }
          }
        }
      } else {
        // Handle error
        final responseBody = await utf8.decoder.bind(httpResponse).join();
        final error = 'OpenAI API Error: ${httpResponse.statusCode} - $responseBody';
        _logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from OpenAI.',
          isDone: true,
          metadata: {'error': error, 'status_code': httpResponse.statusCode},
        );
      }
    } catch (e, stackTrace) {
      _logger.error('Error streaming from OpenAI API: $e');
      _logger.debug('Stack trace: $stackTrace');

      yield LlmResponseChunk(
        textChunk: 'Error: Unable to get a streaming response from OpenAI.',
        isDone: true,
        metadata: {'error': e.toString()},
      );
    }
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    _logger.debug('OpenAI embeddings request');

    try {
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
          throw StateError('No embedding data returned from OpenAI API');
        }
      } else {
        // Handle error
        final error = 'OpenAI API Error: ${httpResponse.statusCode} - $responseBody';
        _logger.error(error);
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error getting embeddings from OpenAI API: $e');
      _logger.debug('Stack trace: $stackTrace');
      throw Exception('Failed to get embeddings: $e');
    }
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    _logger.info('OpenAI provider initialized with model: $model');
  }

  @override
  Future<void> close() async {
    _client.close();
    _logger.debug('OpenAI provider client closed');
  }

  // Helper method to build request body
  Map<String, dynamic> _buildRequestBody(LlmRequest request) {
    // Build messages
    final List<Map<String, dynamic>> messages = [];

    // Add history
    for (final message in request.history) {
      messages.add({
        'role': message.role,
        'content': _convertContentToOpenAiFormat(message.content),
      });
    }

    // Add system message if provided in parameters
    if (request.parameters.containsKey('system') ||
        request.parameters.containsKey('system_instructions')) {
      final systemContent = request.parameters['system'] ??
          request.parameters['system_instructions'];
      if (systemContent != null && systemContent.isNotEmpty) {
        messages.insert(0, {
          'role': 'system',
          'content': systemContent,
        });
      }
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
    };

    // Add parameters
    if (request.parameters.containsKey('max_tokens')) {
      body['max_tokens'] = request.parameters['max_tokens'];
    }

    if (request.parameters.containsKey('temperature')) {
      body['temperature'] = request.parameters['temperature'];
    }

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
          _logger.warning('Error parsing tool arguments: $e');
          arguments = {'_error': 'Failed to parse arguments'};
        }

        return LlmToolCall(
          id: id,
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
    final apiKey = config.apiKey ?? Platform.environment['OPENAI_API_KEY'];
    if (apiKey == null) {
      throw StateError('API key is required for OpenAI provider');
    }

    return OpenAiProvider(
      apiKey: apiKey,
      model: config.model ?? 'gpt-4o',
      baseUrl: config.baseUrl,
      options: config.options,
    );
  }
}