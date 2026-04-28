import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../mcp_llm.dart';

/// Implementation of LLM interface for Mistral AI API.
/// Supports completion, streaming, embeddings, and tool calling.
class MistralProvider implements LlmInterface, RetryableLlmProvider {
  @override
  final LlmConfiguration config;

  final String apiKey;
  final String model;
  final String? baseUrl;
  final http.Client _client = http.Client();

  @override
  final Logger logger = Logger('mcp_llm.mistral_provider');

  /// Default Mistral API base URL.
  static const String defaultBaseUrl = 'https://api.mistral.ai/v1';

  /// Available model aliases.
  static const Map<String, String> modelAliases = {
    'mistral-large': 'mistral-large-latest',
    'mistral-medium': 'mistral-medium-latest',
    'mistral-small': 'mistral-small-latest',
    'codestral': 'codestral-latest',
    'pixtral': 'pixtral-12b-2409',
    'ministral-8b': 'ministral-8b-latest',
    'ministral-3b': 'ministral-3b-latest',
  };

  /// Default model.
  static const String defaultModel = 'mistral-large-latest';

  /// Default embedding model.
  static const String embeddingModel = 'mistral-embed';

  MistralProvider({
    required this.apiKey,
    required this.model,
    this.baseUrl,
    required this.config,
  });

  /// Resolve model alias to actual model ID.
  String _resolveModel(String modelName) {
    return modelAliases[modelName] ?? modelName;
  }

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
      logger.debug('Mistral complete request with model: $model');

      final requestBody = _buildRequestBody(request);

      final uri = Uri.parse('${baseUrl ?? defaultBaseUrl}/chat/completions');

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      final httpResponse = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(httpResponse.body) as Map<String, dynamic>;
        return _parseResponse(responseJson);
      } else {
        final error = 'Mistral API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    try {
      logger.debug('Mistral stream request with model: $model');

      final requestBody = _buildRequestBody(request);
      requestBody['stream'] = true;

      final uri = Uri.parse('${baseUrl ?? defaultBaseUrl}/chat/completions');

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      final httpRequest = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = jsonEncode(requestBody);

      final streamedResponse = await executeWithRetry(() async {
        return await _client.send(httpRequest);
      });

      if (streamedResponse.statusCode >= 200 && streamedResponse.statusCode < 300) {
        final Map<String, Map<String, dynamic>> toolCallsMap = {};
        List<LlmToolCall>? toolCalls;
        String currentToolCallId = '';

        final StringBuffer responseText = StringBuffer();
        String? finishReason;

        final Map<String, Map<String, dynamic>> toolDefinitionCache = {};

        if (request.parameters.containsKey('tools')) {
          final tools = request.parameters['tools'] as List<dynamic>;
          for (final tool in tools) {
            if (tool is Map<String, dynamic> && tool.containsKey('name')) {
              final toolName = tool['name'] as String;
              toolDefinitionCache[toolName] = Map<String, dynamic>.from(tool);
            }
          }
        }

        final StringBuffer lineBuffer = StringBuffer();
        await for (final chunk in utf8.decoder.bind(streamedResponse.stream)) {
          lineBuffer.write(chunk);
          final text = lineBuffer.toString();
          final lastNewline = text.lastIndexOf('\n');
          if (lastNewline == -1) continue;
          final toProcess = text.substring(0, lastNewline);
          lineBuffer.clear();
          lineBuffer.write(text.substring(lastNewline + 1));

          for (final line in toProcess.split('\n')) {
            if (line.startsWith('data: ') && line.length > 6) {
              final data = line.substring(6);
              if (data == '[DONE]') {
                if (toolCalls != null && toolCalls.isNotEmpty) {
                  _validateAndFillToolCallArguments(toolCalls, toolDefinitionCache);
                }

                yield LlmResponseChunk(
                  textChunk: '',
                  isDone: true,
                  metadata: {'finish_reason': finishReason ?? 'stop'},
                  toolCalls: toolCalls,
                );
                break;
              }

              try {
                final chunkJson = jsonDecode(data) as Map<String, dynamic>;

                final choices = chunkJson['choices'] as List<dynamic>?;
                if (choices != null && choices.isNotEmpty) {
                  final choice = choices[0] as Map<String, dynamic>;
                  finishReason = choice['finish_reason'] as String?;
                  final delta = choice['delta'] as Map<String, dynamic>?;

                  if (delta != null) {
                    if (delta.containsKey('content') && delta['content'] != null) {
                      final content = delta['content'] as String;
                      responseText.write(content);

                      yield LlmResponseChunk(
                        textChunk: content,
                        isDone: false,
                        metadata: {},
                        toolCalls: toolCalls,
                      );
                    }

                    if (delta.containsKey('tool_calls')) {
                      final deltaToolCalls = delta['tool_calls'] as List<dynamic>?;

                      if (deltaToolCalls != null && deltaToolCalls.isNotEmpty) {
                        toolCalls ??= [];

                        for (final deltaToolCall in deltaToolCalls) {
                          final function = deltaToolCall['function'] as Map<String, dynamic>?;

                          if (deltaToolCall.containsKey('id')) {
                            currentToolCallId = deltaToolCall['id'] as String;
                          }

                          if (function != null && function.containsKey('name')) {
                            final toolName = function['name'] as String;

                            if (!toolCallsMap.containsKey(currentToolCallId)) {
                              toolCallsMap[currentToolCallId] = {
                                'name': toolName,
                                'arguments': '',
                              };

                              final toolIndex = toolCalls.indexWhere((tc) => tc.id == currentToolCallId);
                              if (toolIndex == -1) {
                                toolCalls.add(LlmToolCall(
                                  id: currentToolCallId,
                                  name: toolName,
                                  arguments: <String, dynamic>{},
                                ));
                              }

                              yield LlmResponseChunk(
                                textChunk: '',
                                isDone: false,
                                metadata: {
                                  'tool_call_start': true,
                                  'tool_name': toolName,
                                  'tool_call_id': currentToolCallId,
                                },
                                toolCalls: toolCalls,
                              );
                            }
                          }

                          if (function != null && function.containsKey('arguments')) {
                            final args = function['arguments'] as String;

                            if (toolCallsMap.containsKey(currentToolCallId)) {
                              toolCallsMap[currentToolCallId]!['arguments'] += args;
                              final argsStr = toolCallsMap[currentToolCallId]!['arguments'] as String;

                              try {
                                if (_isValidJson(argsStr)) {
                                  final toolArgs = jsonDecode(argsStr) as Map<String, dynamic>;

                                  final toolIndex = toolCalls.indexWhere((tc) => tc.id == currentToolCallId);
                                  if (toolIndex >= 0) {
                                    toolCalls[toolIndex] = LlmToolCall(
                                      id: currentToolCallId,
                                      name: toolCallsMap[currentToolCallId]!['name'] as String,
                                      arguments: toolArgs,
                                    );
                                  }

                                  yield LlmResponseChunk(
                                    textChunk: '',
                                    isDone: false,
                                    metadata: {
                                      'tool_call_update': true,
                                      'tool_call_id': currentToolCallId,
                                    },
                                    toolCalls: toolCalls,
                                  );
                                }
                              } catch (e) {
                                logger.debug('Accumulating arguments for tool call: $currentToolCallId');
                              }
                            }
                          }
                        }
                      }
                    }
                  }

                  if (finishReason != null && finishReason.isNotEmpty) {
                    if (finishReason == 'tool_calls') {
                      for (final entry in toolCallsMap.entries) {
                        final toolId = entry.key;
                        final toolInfo = entry.value;
                        final argsStr = toolInfo['arguments'] as String;

                        try {
                          if (argsStr.isNotEmpty) {
                            final toolArgs = jsonDecode(argsStr) as Map<String, dynamic>;

                            final toolIndex = toolCalls!.indexWhere((tc) => tc.id == toolId);
                            if (toolIndex >= 0) {
                              toolCalls[toolIndex] = LlmToolCall(
                                id: toolId,
                                name: toolInfo['name'] as String,
                                arguments: toolArgs,
                              );
                            }
                          }
                        } catch (e) {
                          logger.warning('Failed to parse tool arguments: $e');
                        }
                      }

                      if (toolCalls != null) {
                        _validateAndFillToolCallArguments(toolCalls, toolDefinitionCache);
                      }

                      yield LlmResponseChunk(
                        textChunk: '',
                        isDone: true,
                        metadata: {
                          'finish_reason': 'tool_calls',
                          'expects_tool_result': true,
                        },
                        toolCalls: toolCalls,
                      );
                      return;
                    }
                  }
                }
              } catch (e) {
                logger.warning('Error parsing chunk: $e');
              }
            }
          }
        }
      } else {
        final responseBody = await utf8.decoder.bind(streamedResponse.stream).join();
        final error = 'Mistral API Error: ${streamedResponse.statusCode} - $responseBody';
        logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from Mistral.',
          isDone: true,
          metadata: {'error': error, 'status_code': streamedResponse.statusCode},
        );
      }
    } catch (e, stackTrace) {
      logger.error('Error streaming from Mistral API: $e\n$stackTrace');

      yield LlmResponseChunk(
        textChunk: 'Error: Unable to get a streaming response from Mistral.',
        isDone: true,
        metadata: {'error': e.toString()},
      );
    }
  }

  bool _isValidJson(String jsonString) {
    try {
      jsonDecode(jsonString);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _validateAndFillToolCallArguments(List<LlmToolCall> toolCalls,
      Map<String, Map<String, dynamic>> toolDefinitionCache) {
    for (int i = 0; i < toolCalls.length; i++) {
      final toolCall = toolCalls[i];
      final toolName = toolCall.name;

      if (toolDefinitionCache.containsKey(toolName)) {
        final toolDef = toolDefinitionCache[toolName]!;
        final inputSchema = toolDef['parameters'] as Map<String, dynamic>?;

        if (inputSchema != null && inputSchema.containsKey('required')) {
          final required = inputSchema['required'] as List<dynamic>;
          final args = toolCall.arguments;
          final propertyDefs = inputSchema.containsKey('properties') &&
              inputSchema['properties'] is Map<String, dynamic>
              ? inputSchema['properties'] as Map<String, dynamic>
              : {};

          bool needsUpdate = false;
          final updatedArgs = Map<String, dynamic>.from(args);

          for (final req in required) {
            final argName = req.toString();
            if (!args.containsKey(argName) || args[argName] == null) {
              needsUpdate = true;

              dynamic defaultValue;
              String? type = 'string';

              if (propertyDefs.containsKey(argName)) {
                final propDef = propertyDefs[argName] as Map<String, dynamic>;

                if (propDef.containsKey('default')) {
                  defaultValue = propDef['default'];
                }

                if (propDef.containsKey('type')) {
                  type = propDef['type'] as String?;
                }
              }

              if (defaultValue == null) {
                switch (type) {
                  case 'number':
                  case 'integer':
                    defaultValue = 0;
                    break;
                  case 'boolean':
                    defaultValue = false;
                    break;
                  case 'array':
                    defaultValue = [];
                    break;
                  case 'object':
                    defaultValue = {};
                    break;
                  case 'string':
                  default:
                    if (propertyDefs.containsKey(argName) &&
                        propertyDefs[argName] is Map<String, dynamic> &&
                        propertyDefs[argName].containsKey('enum') &&
                        propertyDefs[argName]['enum'] is List &&
                        (propertyDefs[argName]['enum'] as List).isNotEmpty) {
                      defaultValue = (propertyDefs[argName]['enum'] as List).first;
                    } else {
                      defaultValue = '';
                    }
                    break;
                }
              }

              updatedArgs[argName] = defaultValue;
            }
          }

          if (needsUpdate) {
            toolCalls[i] = LlmToolCall(
              id: toolCall.id,
              name: toolCall.name,
              arguments: updatedArgs,
            );
          }
        }
      }
    }
  }

  @override
  bool hasToolCallMetadata(Map<String, dynamic> metadata) {
    if (metadata.containsKey('tool_call_start') && metadata['tool_call_start'] == true) {
      return true;
    }

    if (metadata.containsKey('finish_reason') && metadata['finish_reason'] == 'tool_calls') {
      return true;
    }

    final toolKeys = ['tool_call_id', 'tool_calls', 'tool_call_update'];
    for (final key in toolKeys) {
      if (metadata.containsKey(key)) {
        return true;
      }
    }

    return false;
  }

  @override
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) {
    if ((metadata.containsKey('tool_call_start') || metadata.containsKey('tool_call_update')) &&
        (metadata.containsKey('tool_name') || metadata.containsKey('tool_call_id'))) {
      final toolName = metadata['tool_name'] as String? ?? 'unknown_tool';
      final toolId = metadata['tool_call_id'] as String? ??
          'mistral_tool_${DateTime.now().millisecondsSinceEpoch}';

      Map<String, dynamic> arguments = {};

      if (metadata.containsKey('tool_call_args') &&
          metadata['tool_call_args'] is Map<String, dynamic>) {
        arguments = metadata['tool_call_args'] as Map<String, dynamic>;
      }

      return LlmToolCall(
        id: toolId,
        name: toolName,
        arguments: arguments,
      );
    }

    if (metadata.containsKey('tool_calls') &&
        metadata['tool_calls'] is List &&
        (metadata['tool_calls'] as List).isNotEmpty) {
      final toolCalls = metadata['tool_calls'] as List;
      final firstToolCall = toolCalls.first;

      if (firstToolCall is Map<String, dynamic>) {
        final toolName = firstToolCall['name'] as String? ?? 'unknown_tool';
        final toolId = firstToolCall['id'] as String? ??
            'mistral_tool_${DateTime.now().millisecondsSinceEpoch}';

        Map<String, dynamic> arguments = {};

        if (firstToolCall.containsKey('arguments')) {
          if (firstToolCall['arguments'] is String) {
            try {
              arguments = jsonDecode(firstToolCall['arguments'] as String) as Map<String, dynamic>;
            } catch (e) {
              logger.warning('Failed to parse arguments JSON: $e');
            }
          } else if (firstToolCall['arguments'] is Map) {
            arguments = Map<String, dynamic>.from(firstToolCall['arguments'] as Map);
          }
        }

        return LlmToolCall(
          id: toolId,
          name: toolName,
          arguments: arguments,
        );
      }
    }

    return null;
  }

  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) {
    final standardMetadata = Map<String, dynamic>.from(metadata);

    if (metadata.containsKey('finish_reason') && metadata['finish_reason'] == 'tool_calls') {
      if (!standardMetadata.containsKey('expects_tool_result')) {
        standardMetadata['expects_tool_result'] = true;
      }
    }

    if (metadata.containsKey('tool_call_start') && metadata['tool_call_start'] == true) {
      standardMetadata['is_tool_call'] = true;
    }

    if (metadata.containsKey('tool_call_id') && !standardMetadata.containsKey('tool_id')) {
      standardMetadata['tool_id'] = metadata['tool_call_id'];
    }

    return standardMetadata;
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return await executeWithRetry(() async {
      logger.debug('Mistral embeddings request');

      final uri = Uri.parse('${baseUrl ?? defaultBaseUrl}/embeddings');

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      final requestBody = {
        'model': embeddingModel,
        'input': [text],
      };

      final httpResponse = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(httpResponse.body) as Map<String, dynamic>;

        final data = responseJson['data'] as List<dynamic>;
        if (data.isNotEmpty) {
          final embedding = data.first['embedding'] as List<dynamic>;
          return embedding.map((e) => (e as num).toDouble()).toList();
        } else {
          throw StateError('No embedding data returned from Mistral API');
        }
      } else {
        final error = 'Mistral API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    logger.info('Mistral provider initialized with model: $model');
  }

  @override
  Future<void> close() async {
    _client.close();
    logger.debug('Mistral provider client closed');
  }

  Map<String, dynamic> _buildRequestBody(LlmRequest request) {
    final List<Map<String, dynamic>> messages = [];
    String? systemContent;

    if (request.parameters.containsKey('system') ||
        request.parameters.containsKey('system_instructions')) {
      systemContent = request.parameters['system'] ??
          request.parameters['system_instructions'];
    }

    for (final message in request.history) {
      if (message.role == 'system') {
        if (systemContent == null || systemContent.isEmpty) {
          systemContent = message.content.toString();
        }
        continue;
      } else if (message.role == 'tool') {
        final toolContent = message.content;
        dynamic toolResult = '';
        String toolCallId = '';

        if (toolContent is Map) {
          if (toolContent.containsKey('content')) {
            toolResult = toolContent['content'];
          }
          if (message.metadata.containsKey('tool_call_id')) {
            toolCallId = message.metadata['tool_call_id'].toString();
          } else if (toolContent.containsKey('tool_call_id')) {
            toolCallId = toolContent['tool_call_id'].toString();
          } else {
            toolCallId = 'call_${DateTime.now().millisecondsSinceEpoch}';
          }
        }

        messages.add({
          'role': 'tool',
          'tool_call_id': toolCallId,
          'content': toolResult.toString(),
        });
      } else if (message.role == 'assistant' && message.metadata.containsKey('tool_call')) {
        final toolCallContent = message.content;
        if (toolCallContent is Map && toolCallContent.containsKey('tool_calls')) {
          final toolCalls = (toolCallContent['tool_calls'] as List<dynamic>).map((toolCall) {
            return {
              'id': toolCall['id'],
              'type': 'function',
              'function': {
                'name': toolCall['name'],
                'arguments': toolCall['arguments'] is String
                    ? toolCall['arguments']
                    : jsonEncode(toolCall['arguments']),
              },
            };
          }).toList();
          messages.add({
            'role': 'assistant',
            'content': null,
            'tool_calls': toolCalls,
          });
        } else {
          messages.add({
            'role': message.role,
            'content': message.content.toString(),
          });
        }
      } else {
        messages.add({
          'role': message.role,
          'content': message.content.toString(),
        });
      }
    }

    if (systemContent != null && systemContent.isNotEmpty) {
      messages.insert(0, {
        'role': 'system',
        'content': systemContent,
      });
    }

    messages.add({
      'role': 'user',
      'content': request.prompt,
    });

    final resolvedModel = _resolveModel(model);

    final Map<String, dynamic> body = {
      'model': resolvedModel,
      'messages': messages,
      'max_tokens': request.parameters['max_tokens'] ?? 1024,
      'temperature': request.parameters['temperature'] ?? 0.7,
    };

    if (request.parameters.containsKey('top_p')) {
      body['top_p'] = request.parameters['top_p'];
    }

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

      if (request.parameters.containsKey('tool_choice')) {
        body['tool_choice'] = request.parameters['tool_choice'];
      }
    }

    return body;
  }

  LlmResponse _parseResponse(Map<String, dynamic> response) {
    final choices = response['choices'] as List<dynamic>;
    final choice = choices.first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>;

    String text = '';
    final content = message['content'];
    if (content != null && content is String) {
      text = content;
    }

    List<LlmToolCall>? toolCalls;
    final toolCallsList = message['tool_calls'] as List<dynamic>?;
    if (toolCallsList != null && toolCallsList.isNotEmpty) {
      toolCalls = toolCallsList.map((toolCallData) {
        final id = toolCallData['id'] as String;
        final function = toolCallData['function'] as Map<String, dynamic>;
        final name = function['name'] as String;

        Map<String, dynamic> arguments;
        try {
          arguments = jsonDecode(function['arguments'] as String) as Map<String, dynamic>;
        } catch (e) {
          logger.warning('Error parsing tool arguments: $e');
          arguments = {'_error': 'Failed to parse arguments'};
        }

        return LlmToolCall(
          id: id,
          name: name,
          arguments: arguments,
        );
      }).toList();
    }

    final metadata = <String, dynamic>{
      'model': response['model'],
      'finish_reason': choice['finish_reason'],
      'provider': 'mistral',
    };

    if (response.containsKey('usage')) {
      metadata['usage'] = response['usage'];
    }

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

/// Factory for creating Mistral providers.
class MistralProviderFactory implements LlmProviderFactory {
  @override
  String get name => 'mistral';

  @override
  Set<LlmCapability> get capabilities => {
    LlmCapability.completion,
    LlmCapability.streaming,
    LlmCapability.embeddings,
    LlmCapability.toolUse,
    LlmCapability.functionCalling,
    LlmCapability.imageUnderstanding,
  };

  @override
  LlmInterface createProvider(LlmConfiguration config) {
    final apiKey = config.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('API key is required for Mistral provider');
    }

    return MistralProvider(
      apiKey: apiKey,
      model: config.model ?? MistralProvider.defaultModel,
      baseUrl: config.baseUrl,
      config: config,
    );
  }
}
