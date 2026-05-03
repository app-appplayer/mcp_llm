import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../mcp_llm.dart';

/// Implementation of LLM interface for Google Gemini API.
/// Supports completion, streaming, embeddings, tool calling, and vision.
class GeminiProvider implements LlmInterface, RetryableLlmProvider {
  @override
  final LlmConfiguration config;

  final String apiKey;
  final String model;
  final String? baseUrl;
  final http.Client _client = http.Client();

  @override
  final Logger logger = Logger('mcp_llm.gemini_provider');

  /// Default Gemini API base URL.
  static const String defaultBaseUrl = 'https://generativelanguage.googleapis.com/v1beta';

  /// Available model aliases.
  static const Map<String, String> modelAliases = {
    'gemini-pro': 'gemini-1.0-pro',
    'gemini-1.5-pro': 'gemini-1.5-pro-latest',
    'gemini-1.5-flash': 'gemini-1.5-flash-latest',
    'gemini-2.0-flash': 'gemini-2.0-flash-exp',
  };

  /// Default model.
  static const String defaultModel = 'gemini-1.5-pro-latest';

  /// Default embedding model.
  static const String embeddingModel = 'text-embedding-004';

  /// Gemini supports prompt caching via the `cachedContent` resource
  /// (separate POST + reference). The package-wide default policy is
  /// OFF for Gemini because the resource carries a per-minute storage
  /// charge and a 32K-token minimum (Pro models) — small or one-shot
  /// prompts cost more than they save. Callers opt in by creating a
  /// cachedContent themselves and passing its name through
  /// `parameters['cached_content']`. See `mcp_llm` package docs.
  @override
  bool get supportsPromptCaching => true;

  GeminiProvider({
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
      logger.debug('Gemini complete request with model: $model');

      final resolvedModel = _resolveModel(model);
      final requestBody = _buildRequestBody(request);

      final uri = Uri.parse(
        '${baseUrl ?? defaultBaseUrl}/models/$resolvedModel:generateContent?key=$apiKey',
      );

      final headers = {
        'Content-Type': 'application/json',
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
        final error = 'Gemini API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    try {
      logger.debug('Gemini stream request with model: $model');

      final resolvedModel = _resolveModel(model);
      final requestBody = _buildRequestBody(request);

      final uri = Uri.parse(
        '${baseUrl ?? defaultBaseUrl}/models/$resolvedModel:streamGenerateContent?alt=sse&key=$apiKey',
      );

      final headers = {
        'Content-Type': 'application/json',
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
              final data = line.substring(6).trim();
              if (data.isEmpty) continue;

              try {
                final chunkJson = jsonDecode(data) as Map<String, dynamic>;

                // Gemini emits `usageMetadata` on each SSE chunk
                // (cumulative). When the request used a cachedContent
                // reference the metadata carries `cachedContentTokenCount`
                // — surface it on the canonical mcp_llm key.
                final usage = chunkJson['usageMetadata'];
                if (usage is Map<String, dynamic>) {
                  final cached = usage['cachedContentTokenCount'];
                  if (cached is int) {
                    yield LlmResponseChunk(
                      textChunk: '',
                      isDone: false,
                      metadata: {
                        LlmCacheMetadataKeys.cacheReadTokens: cached,
                      },
                    );
                  }
                }

                final candidates = chunkJson['candidates'] as List<dynamic>?;
                if (candidates != null && candidates.isNotEmpty) {
                  final candidate = candidates[0] as Map<String, dynamic>;
                  finishReason = candidate['finishReason'] as String?;

                  final content = candidate['content'] as Map<String, dynamic>?;
                  if (content != null) {
                    final parts = content['parts'] as List<dynamic>?;
                    if (parts != null) {
                      for (final part in parts) {
                        if (part is Map<String, dynamic>) {
                          if (part.containsKey('text')) {
                            final textContent = part['text'] as String;
                            responseText.write(textContent);

                            yield LlmResponseChunk(
                              textChunk: textContent,
                              isDone: false,
                              metadata: {},
                              toolCalls: toolCalls,
                            );
                          }

                          if (part.containsKey('functionCall')) {
                            final functionCall = part['functionCall'] as Map<String, dynamic>;
                            final toolName = functionCall['name'] as String;
                            final args = functionCall['args'] as Map<String, dynamic>? ?? {};

                            toolCalls ??= [];
                            final toolId = 'gemini_tool_${DateTime.now().millisecondsSinceEpoch}_${toolCalls.length}';

                            toolCalls.add(LlmToolCall(
                              id: toolId,
                              name: toolName,
                              arguments: args,
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
                      }
                    }
                  }
                }

                if (finishReason != null && finishReason.isNotEmpty) {
                  if (finishReason == 'STOP' || finishReason == 'MAX_TOKENS') {
                    yield LlmResponseChunk(
                      textChunk: '',
                      isDone: true,
                      metadata: {'finish_reason': finishReason.toLowerCase()},
                      toolCalls: toolCalls,
                    );
                  } else if (finishReason == 'TOOL_CODE' || toolCalls != null) {
                    yield LlmResponseChunk(
                      textChunk: '',
                      isDone: true,
                      metadata: {
                        'finish_reason': 'tool_calls',
                        'expects_tool_result': true,
                      },
                      toolCalls: toolCalls,
                    );
                  }
                }
              } catch (e) {
                logger.warning('Error parsing chunk: $e');
              }
            }
          }
        }

        yield LlmResponseChunk(
          textChunk: '',
          isDone: true,
          metadata: {'finish_reason': finishReason?.toLowerCase() ?? 'stop'},
          toolCalls: toolCalls,
        );
      } else {
        final responseBody = await utf8.decoder.bind(streamedResponse.stream).join();
        final error = 'Gemini API Error: ${streamedResponse.statusCode} - $responseBody';
        logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from Gemini.',
          isDone: true,
          metadata: {'error': error, 'status_code': streamedResponse.statusCode},
        );
      }
    } catch (e, stackTrace) {
      logger.error('Error streaming from Gemini API: $e\n$stackTrace');

      yield LlmResponseChunk(
        textChunk: 'Error: Unable to get a streaming response from Gemini.',
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

    final toolKeys = ['tool_call_id', 'tool_calls', 'tool_call_update', 'functionCall'];
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
          'gemini_tool_${DateTime.now().millisecondsSinceEpoch}';

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

    if (metadata.containsKey('functionCall') && metadata['functionCall'] is Map<String, dynamic>) {
      final functionCall = metadata['functionCall'] as Map<String, dynamic>;
      final toolName = functionCall['name'] as String? ?? 'unknown_tool';
      final args = functionCall['args'] as Map<String, dynamic>? ?? {};

      return LlmToolCall(
        id: 'gemini_tool_${DateTime.now().millisecondsSinceEpoch}',
        name: toolName,
        arguments: args,
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
      logger.debug('Gemini embeddings request');

      final uri = Uri.parse(
        '${baseUrl ?? defaultBaseUrl}/models/$embeddingModel:embedContent?key=$apiKey',
      );

      final headers = {
        'Content-Type': 'application/json',
      };

      final requestBody = {
        'model': 'models/$embeddingModel',
        'content': {
          'parts': [
            {'text': text}
          ]
        },
      };

      final httpResponse = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(httpResponse.body) as Map<String, dynamic>;

        final embedding = responseJson['embedding'] as Map<String, dynamic>?;
        if (embedding != null && embedding.containsKey('values')) {
          final values = embedding['values'] as List<dynamic>;
          return values.map((e) => (e as num).toDouble()).toList();
        } else {
          throw StateError('No embedding data returned from Gemini API');
        }
      } else {
        final error = 'Gemini API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    logger.info('Gemini provider initialized with model: $model');
  }

  @override
  Future<void> close() async {
    _client.close();
    logger.debug('Gemini provider client closed');
  }

  Map<String, dynamic> _buildRequestBody(LlmRequest request) {
    final List<Map<String, dynamic>> contents = [];
    String? systemInstruction;

    if (request.parameters.containsKey('system') ||
        request.parameters.containsKey('system_instructions')) {
      systemInstruction = request.parameters['system'] ??
          request.parameters['system_instructions'];
    }

    for (final message in request.history) {
      if (message.role == 'system') {
        if (systemInstruction == null || systemInstruction.isEmpty) {
          systemInstruction = message.content.toString();
        }
        continue;
      }

      final role = message.role == 'assistant' ? 'model' : 'user';
      final content = message.content;

      if (message.role == 'tool') {
        final toolContent = content is Map ? content : {};
        final toolResult = toolContent['content'] ?? content.toString();
        final toolName = toolContent['tool_name'] ?? message.metadata['tool_name'] ?? 'unknown';

        contents.add({
          'role': 'function',
          'parts': [
            {
              'functionResponse': {
                'name': toolName,
                'response': {
                  'result': toolResult,
                },
              },
            },
          ],
        });
      } else if (message.metadata.containsKey('tool_call') && content is Map) {
        final toolCalls = content['tool_calls'] as List<dynamic>?;
        if (toolCalls != null) {
          final parts = <Map<String, dynamic>>[];
          for (final tc in toolCalls) {
            parts.add({
              'functionCall': {
                'name': tc['name'],
                'args': tc['arguments'],
              },
            });
          }
          contents.add({
            'role': 'model',
            'parts': parts,
          });
        }
      } else {
        final parts = _buildContentParts(content);
        contents.add({
          'role': role,
          'parts': parts,
        });
      }
    }

    contents.add({
      'role': 'user',
      'parts': [
        {'text': request.prompt},
      ],
    });

    final Map<String, dynamic> body = {
      'contents': contents,
    };

    if (systemInstruction != null && systemInstruction.isNotEmpty) {
      body['systemInstruction'] = {
        'parts': [
          {'text': systemInstruction},
        ],
      };
    }

    final generationConfig = <String, dynamic>{};
    if (request.parameters.containsKey('max_tokens')) {
      generationConfig['maxOutputTokens'] = request.parameters['max_tokens'];
    }
    if (request.parameters.containsKey('temperature')) {
      generationConfig['temperature'] = request.parameters['temperature'];
    }
    if (request.parameters.containsKey('top_p')) {
      generationConfig['topP'] = request.parameters['top_p'];
    }
    if (request.parameters.containsKey('top_k')) {
      generationConfig['topK'] = request.parameters['top_k'];
    }
    if (generationConfig.isNotEmpty) {
      body['generationConfig'] = generationConfig;
    }

    if (request.parameters.containsKey('tools')) {
      final tools = request.parameters['tools'] as List<dynamic>;
      body['tools'] = [
        {
          'functionDeclarations': tools.map((tool) {
            return {
              'name': tool['name'],
              'description': tool['description'],
              'parameters': tool['parameters'],
            };
          }).toList(),
        },
      ];
    }

    // Gemini's prompt caching uses a separate `cachedContent` resource
    // (POST /v1beta/cachedContents) with explicit lifecycle and a
    // per-minute storage charge. Because that economics breaks for
    // small / one-shot prompts, the package-wide default policy is
    // OFF for Gemini — callers manage the cachedContent themselves
    // and forward the resource name through `parameters`. When
    // provided, attach the reference and Gemini reuses the prebuilt
    // prefix.
    //
    // Constraint: a request that carries `cachedContent` MUST NOT
    // also carry `systemInstruction` or `tools` — Gemini rejects the
    // combination with 400 INVALID_ARGUMENT because the cached
    // resource already pins those. Strip them when forwarding.
    final cachedContent = request.parameters['cached_content'] ??
        request.parameters['cachedContent'];
    if (cachedContent is String && cachedContent.isNotEmpty) {
      body['cachedContent'] = cachedContent;
      body.remove('systemInstruction');
      body.remove('tools');
    }

    return body;
  }

  List<Map<String, dynamic>> _buildContentParts(dynamic content) {
    if (content is String) {
      return [
        {'text': content},
      ];
    }

    if (content is Map) {
      if (content['type'] == 'image') {
        final mimeType = content['mimeType'] ?? 'image/png';
        final base64Data = content['base64Data'];

        if (base64Data != null) {
          return [
            {
              'inlineData': {
                'mimeType': mimeType,
                'data': base64Data,
              },
            },
          ];
        }
      }

      if (content['type'] == 'text') {
        return [
          {'text': content['text']},
        ];
      }
    }

    return [
      {'text': content.toString()},
    ];
  }

  LlmResponse _parseResponse(Map<String, dynamic> response) {
    String text = '';
    List<LlmToolCall>? toolCalls;
    String? finishReason;

    final candidates = response['candidates'] as List<dynamic>?;
    if (candidates != null && candidates.isNotEmpty) {
      final candidate = candidates[0] as Map<String, dynamic>;
      finishReason = candidate['finishReason'] as String?;

      final content = candidate['content'] as Map<String, dynamic>?;
      if (content != null) {
        final parts = content['parts'] as List<dynamic>?;
        if (parts != null) {
          final textParts = StringBuffer();
          for (final part in parts) {
            if (part is Map<String, dynamic>) {
              if (part.containsKey('text')) {
                textParts.write(part['text']);
              }

              if (part.containsKey('functionCall')) {
                final functionCall = part['functionCall'] as Map<String, dynamic>;
                final toolName = functionCall['name'] as String;
                final args = functionCall['args'] as Map<String, dynamic>? ?? {};

                toolCalls ??= [];
                toolCalls.add(LlmToolCall(
                  id: 'gemini_tool_${DateTime.now().millisecondsSinceEpoch}_${toolCalls.length}',
                  name: toolName,
                  arguments: args,
                ));
              }
            }
          }
          text = textParts.toString();
        }
      }
    }

    final metadata = <String, dynamic>{
      'model': model,
      'finish_reason': finishReason?.toLowerCase() ?? 'stop',
      'provider': 'gemini',
    };

    if (response.containsKey('usageMetadata')) {
      metadata['usage'] = response['usageMetadata'];
      final usage = response['usageMetadata'];
      if (usage is Map<String, dynamic>) {
        // Gemini surfaces cached prefix tokens under
        // `cachedContentTokenCount` when a `cachedContent` reference
        // was used. Promote to the canonical mcp_llm key.
        final cached = usage['cachedContentTokenCount'];
        if (cached is int) {
          metadata[LlmCacheMetadataKeys.cacheReadTokens] = cached;
        }
      }
    }

    if (toolCalls != null && toolCalls.isNotEmpty) {
      metadata['tool_call_ids'] = toolCalls.map((tc) => tc.id).toList();
      if (finishReason == null || finishReason == 'STOP') {
        metadata['finish_reason'] = 'tool_calls';
        metadata['expects_tool_result'] = true;
      }
    }

    return LlmResponse(
      text: text,
      metadata: metadata,
      toolCalls: toolCalls,
    );
  }
}

/// Factory for creating Gemini providers.
class GeminiProviderFactory implements LlmProviderFactory {
  @override
  String get name => 'gemini';

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
      throw StateError('API key is required for Gemini provider');
    }

    return GeminiProvider(
      apiKey: apiKey,
      model: config.model ?? GeminiProvider.defaultModel,
      baseUrl: config.baseUrl,
      config: config,
    );
  }
}
