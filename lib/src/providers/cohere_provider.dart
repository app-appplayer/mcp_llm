import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../mcp_llm.dart';

/// Implementation of LLM interface for Cohere API.
/// Supports completion, streaming, embeddings (strong), and tool calling.
class CohereProvider implements LlmInterface, RetryableLlmProvider {
  @override
  final LlmConfiguration config;

  final String apiKey;
  final String model;
  final String? baseUrl;
  final http.Client _client = http.Client();

  @override
  final Logger logger = Logger('mcp_llm.cohere_provider');

  /// Default Cohere API base URL.
  static const String defaultBaseUrl = 'https://api.cohere.ai/v1';

  /// Available model aliases.
  static const Map<String, String> modelAliases = {
    'command': 'command',
    'command-r': 'command-r',
    'command-r-plus': 'command-r-plus',
    'command-light': 'command-light',
    'command-nightly': 'command-nightly',
  };

  /// Default model.
  static const String defaultModel = 'command-r-plus';

  /// Default embedding model.
  static const String embeddingModel = 'embed-english-v3.0';

  CohereProvider({
    required this.apiKey,
    required this.model,
    this.baseUrl,
    required this.config,
  });

  /// Cohere does not expose a prompt-caching mechanism.
  @override
  bool get supportsPromptCaching => false;

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
      logger.debug('Cohere complete request with model: $model');

      final requestBody = _buildRequestBody(request);

      final uri = Uri.parse('${baseUrl ?? defaultBaseUrl}/chat');

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
        final error = 'Cohere API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    try {
      logger.debug('Cohere stream request with model: $model');

      final requestBody = _buildRequestBody(request);
      requestBody['stream'] = true;

      final uri = Uri.parse('${baseUrl ?? defaultBaseUrl}/chat');

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
        final StringBuffer responseText = StringBuffer();
        List<LlmToolCall>? toolCalls;
        String? finishReason;

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
            if (line.trim().isEmpty) continue;

            try {
              final chunkJson = jsonDecode(line) as Map<String, dynamic>;
              final eventType = chunkJson['event_type'] as String?;

              switch (eventType) {
                case 'text-generation':
                  final textContent = chunkJson['text'] as String? ?? '';
                  if (textContent.isNotEmpty) {
                    responseText.write(textContent);
                    yield LlmResponseChunk(
                      textChunk: textContent,
                      isDone: false,
                      metadata: {},
                      toolCalls: toolCalls,
                    );
                  }
                  break;

                case 'tool-calls-generation':
                  final toolCallsData = chunkJson['tool_calls'] as List<dynamic>?;
                  if (toolCallsData != null) {
                    toolCalls ??= [];
                    for (final tc in toolCallsData) {
                      final tcMap = tc as Map<String, dynamic>;
                      final toolName = tcMap['name'] as String;
                      final parameters = tcMap['parameters'] as Map<String, dynamic>? ?? {};
                      final toolId = 'cohere_tool_${DateTime.now().millisecondsSinceEpoch}_${toolCalls.length}';

                      toolCalls.add(LlmToolCall(
                        id: toolId,
                        name: toolName,
                        arguments: parameters,
                      ));

                      yield LlmResponseChunk(
                        textChunk: '',
                        isDone: false,
                        metadata: {
                          'tool_call_start': true,
                          'tool_name': toolName,
                          'tool_call_id': toolId,
                        },
                        toolCalls: toolCalls,
                      );
                    }
                  }
                  break;

                case 'stream-end':
                  finishReason = chunkJson['finish_reason'] as String?;
                  final hasToolCalls = toolCalls != null && toolCalls.isNotEmpty;

                  yield LlmResponseChunk(
                    textChunk: '',
                    isDone: true,
                    metadata: {
                      'finish_reason': hasToolCalls ? 'tool_calls' : (finishReason ?? 'stop'),
                      if (hasToolCalls) 'expects_tool_result': true,
                    },
                    toolCalls: toolCalls,
                  );
                  break;
              }
            } catch (e) {
              logger.warning('Error parsing chunk: $e');
            }
          }
        }
      } else {
        final responseBody = await utf8.decoder.bind(streamedResponse.stream).join();
        final error = 'Cohere API Error: ${streamedResponse.statusCode} - $responseBody';
        logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from Cohere.',
          isDone: true,
          metadata: {'error': error, 'status_code': streamedResponse.statusCode},
        );
      }
    } catch (e, stackTrace) {
      logger.error('Error streaming from Cohere API: $e\n$stackTrace');

      yield LlmResponseChunk(
        textChunk: 'Error: Unable to get a streaming response from Cohere.',
        isDone: true,
        metadata: {'error': e.toString()},
      );
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
          'cohere_tool_${DateTime.now().millisecondsSinceEpoch}';

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
      logger.debug('Cohere embeddings request');

      final uri = Uri.parse('${baseUrl ?? defaultBaseUrl}/embed');

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      final requestBody = {
        'model': embeddingModel,
        'texts': [text],
        'input_type': 'search_document',
      };

      final httpResponse = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(httpResponse.body) as Map<String, dynamic>;

        final embeddings = responseJson['embeddings'] as List<dynamic>?;
        if (embeddings != null && embeddings.isNotEmpty) {
          final embedding = embeddings.first as List<dynamic>;
          return embedding.map((e) => (e as num).toDouble()).toList();
        } else {
          throw StateError('No embedding data returned from Cohere API');
        }
      } else {
        final error = 'Cohere API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    logger.info('Cohere provider initialized with model: $model');
  }

  @override
  Future<void> close() async {
    _client.close();
    logger.debug('Cohere provider client closed');
  }

  Map<String, dynamic> _buildRequestBody(LlmRequest request) {
    final resolvedModel = _resolveModel(model);

    final Map<String, dynamic> body = {
      'model': resolvedModel,
      'message': request.prompt,
    };

    String? preamble;
    if (request.parameters.containsKey('system') ||
        request.parameters.containsKey('system_instructions')) {
      preamble = request.parameters['system'] ??
          request.parameters['system_instructions'];
    }

    final List<Map<String, dynamic>> chatHistory = [];

    for (final message in request.history) {
      if (message.role == 'system') {
        if (preamble == null || preamble.isEmpty) {
          preamble = message.content.toString();
        }
        continue;
      }

      final role = message.role == 'assistant' ? 'CHATBOT' : 'USER';

      if (message.role == 'tool') {
        final toolContent = message.content;
        if (toolContent is Map) {
          body['tool_results'] ??= [];
          (body['tool_results'] as List).add({
            'call': {
              'name': toolContent['tool_name'] ?? message.metadata['tool_name'] ?? 'unknown',
              'parameters': {},
            },
            'outputs': [
              {'result': toolContent['content'] ?? toolContent.toString()},
            ],
          });
        }
        continue;
      }

      if (message.metadata.containsKey('tool_call') && message.content is Map) {
        final content = message.content as Map;
        final toolCalls = content['tool_calls'] as List<dynamic>?;
        if (toolCalls != null) {
          for (final tc in toolCalls) {
            chatHistory.add({
              'role': 'CHATBOT',
              'message': '',
              'tool_calls': [
                {
                  'name': tc['name'],
                  'parameters': tc['arguments'],
                },
              ],
            });
          }
          continue;
        }
      }

      chatHistory.add({
        'role': role,
        'message': message.content.toString(),
      });
    }

    if (chatHistory.isNotEmpty) {
      body['chat_history'] = chatHistory;
    }

    if (preamble != null && preamble.isNotEmpty) {
      body['preamble'] = preamble;
    }

    if (request.parameters.containsKey('temperature')) {
      body['temperature'] = request.parameters['temperature'];
    }
    if (request.parameters.containsKey('max_tokens')) {
      body['max_tokens'] = request.parameters['max_tokens'];
    }
    if (request.parameters.containsKey('top_p')) {
      body['p'] = request.parameters['top_p'];
    }
    if (request.parameters.containsKey('top_k')) {
      body['k'] = request.parameters['top_k'];
    }

    if (request.parameters.containsKey('tools')) {
      final tools = request.parameters['tools'] as List<dynamic>;
      body['tools'] = tools.map((tool) {
        final parameters = tool['parameters'] as Map<String, dynamic>?;
        final properties = parameters?['properties'] as Map<String, dynamic>? ?? {};
        final required = parameters?['required'] as List<dynamic>? ?? [];

        return {
          'name': tool['name'],
          'description': tool['description'],
          'parameter_definitions': properties.map((key, value) {
            final propDef = value as Map<String, dynamic>;
            return MapEntry(key, {
              'description': propDef['description'] ?? '',
              'type': propDef['type'] ?? 'string',
              'required': required.contains(key),
            });
          }),
        };
      }).toList();
    }

    return body;
  }

  LlmResponse _parseResponse(Map<String, dynamic> response) {
    String text = response['text'] as String? ?? '';
    List<LlmToolCall>? toolCalls;
    String? finishReason = response['finish_reason'] as String?;

    final toolCallsData = response['tool_calls'] as List<dynamic>?;
    if (toolCallsData != null && toolCallsData.isNotEmpty) {
      toolCalls = [];
      for (final tc in toolCallsData) {
        final tcMap = tc as Map<String, dynamic>;
        final toolName = tcMap['name'] as String;
        final parameters = tcMap['parameters'] as Map<String, dynamic>? ?? {};

        toolCalls.add(LlmToolCall(
          id: 'cohere_tool_${DateTime.now().millisecondsSinceEpoch}_${toolCalls.length}',
          name: toolName,
          arguments: parameters,
        ));
      }
    }

    final metadata = <String, dynamic>{
      'model': model,
      'finish_reason': toolCalls != null ? 'tool_calls' : (finishReason ?? 'stop'),
      'provider': 'cohere',
    };

    if (response.containsKey('meta')) {
      metadata['usage'] = response['meta'];
    }

    if (toolCalls != null && toolCalls.isNotEmpty) {
      metadata['tool_call_ids'] = toolCalls.map((tc) => tc.id).toList();
      metadata['expects_tool_result'] = true;
    }

    return LlmResponse(
      text: text,
      metadata: metadata,
      toolCalls: toolCalls,
    );
  }
}

/// Factory for creating Cohere providers.
class CohereProviderFactory implements LlmProviderFactory {
  @override
  String get name => 'cohere';

  @override
  Set<LlmCapability> get capabilities => {
    LlmCapability.completion,
    LlmCapability.streaming,
    LlmCapability.embeddings,
    LlmCapability.toolUse,
    LlmCapability.functionCalling,
  };

  @override
  LlmInterface createProvider(LlmConfiguration config) {
    final apiKey = config.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('API key is required for Cohere provider');
    }

    return CohereProvider(
      apiKey: apiKey,
      model: config.model ?? CohereProvider.defaultModel,
      baseUrl: config.baseUrl,
      config: config,
    );
  }
}
