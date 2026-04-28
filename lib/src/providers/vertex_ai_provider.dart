import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../mcp_llm.dart';

/// Implementation of LLM interface for Google Vertex AI.
/// Enterprise-grade access to Gemini and other models with OAuth/Service Account auth.
class VertexAiProvider implements LlmInterface, RetryableLlmProvider {
  @override
  final LlmConfiguration config;

  final String? accessToken;
  final String projectId;
  final String location;
  final String model;
  final String? baseUrl;
  final http.Client _client = http.Client();

  @override
  final Logger logger = Logger('mcp_llm.vertex_ai_provider');

  /// Available model aliases.
  static const Map<String, String> modelAliases = {
    'gemini-pro': 'gemini-1.0-pro-001',
    'gemini-1.5-pro': 'gemini-1.5-pro-001',
    'gemini-1.5-flash': 'gemini-1.5-flash-001',
    'gemini-2.0-flash': 'gemini-2.0-flash-exp',
    'palm2': 'text-bison@002',
  };

  /// Default model.
  static const String defaultModel = 'gemini-1.5-pro-001';

  /// Default embedding model.
  static const String embeddingModel = 'textembedding-gecko@003';

  /// Default location.
  static const String defaultLocation = 'us-central1';

  VertexAiProvider({
    this.accessToken,
    required this.projectId,
    required this.location,
    required this.model,
    this.baseUrl,
    required this.config,
  });

  String get _baseUrl =>
      baseUrl ?? 'https://$location-aiplatform.googleapis.com/v1';

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

  Map<String, String> _getHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (accessToken != null && accessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    return headers;
  }

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return await executeWithRetry(() async {
      logger.debug('Vertex AI complete request with model: $model');

      final resolvedModel = _resolveModel(model);
      final requestBody = _buildRequestBody(request);

      final uri = Uri.parse(
        '$_baseUrl/projects/$projectId/locations/$location/publishers/google/models/$resolvedModel:generateContent',
      );

      final httpResponse = await _client.post(
        uri,
        headers: _getHeaders(),
        body: jsonEncode(requestBody),
      );

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(httpResponse.body) as Map<String, dynamic>;
        return _parseResponse(responseJson);
      } else {
        final error = 'Vertex AI API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    try {
      logger.debug('Vertex AI stream request with model: $model');

      final resolvedModel = _resolveModel(model);
      final requestBody = _buildRequestBody(request);

      final uri = Uri.parse(
        '$_baseUrl/projects/$projectId/locations/$location/publishers/google/models/$resolvedModel:streamGenerateContent?alt=sse',
      );

      final httpRequest = http.Request('POST', uri)
        ..headers.addAll(_getHeaders())
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
            if (line.startsWith('data: ') && line.length > 6) {
              final data = line.substring(6).trim();
              if (data.isEmpty) continue;

              try {
                final chunkJson = jsonDecode(data) as Map<String, dynamic>;

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
                            final toolId = 'vertex_tool_${DateTime.now().millisecondsSinceEpoch}_${toolCalls.length}';

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
        final error = 'Vertex AI API Error: ${streamedResponse.statusCode} - $responseBody';
        logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from Vertex AI.',
          isDone: true,
          metadata: {'error': error, 'status_code': streamedResponse.statusCode},
        );
      }
    } catch (e, stackTrace) {
      logger.error('Error streaming from Vertex AI API: $e\n$stackTrace');

      yield LlmResponseChunk(
        textChunk: 'Error: Unable to get a streaming response from Vertex AI.',
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
          'vertex_tool_${DateTime.now().millisecondsSinceEpoch}';

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
        id: 'vertex_tool_${DateTime.now().millisecondsSinceEpoch}',
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
      logger.debug('Vertex AI embeddings request');

      final uri = Uri.parse(
        '$_baseUrl/projects/$projectId/locations/$location/publishers/google/models/$embeddingModel:predict',
      );

      final requestBody = {
        'instances': [
          {'content': text}
        ],
      };

      final httpResponse = await _client.post(
        uri,
        headers: _getHeaders(),
        body: jsonEncode(requestBody),
      );

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(httpResponse.body) as Map<String, dynamic>;

        final predictions = responseJson['predictions'] as List<dynamic>?;
        if (predictions != null && predictions.isNotEmpty) {
          final prediction = predictions.first as Map<String, dynamic>;
          final embeddings = prediction['embeddings'] as Map<String, dynamic>?;
          if (embeddings != null && embeddings.containsKey('values')) {
            final values = embeddings['values'] as List<dynamic>;
            return values.map((e) => (e as num).toDouble()).toList();
          }
        }
        throw StateError('No embedding data returned from Vertex AI API');
      } else {
        final error = 'Vertex AI API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);
        throw Exception(error);
      }
    });
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    logger.info('Vertex AI provider initialized with model: $model, project: $projectId');
  }

  @override
  Future<void> close() async {
    _client.close();
    logger.debug('Vertex AI provider client closed');
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
                  id: 'vertex_tool_${DateTime.now().millisecondsSinceEpoch}_${toolCalls.length}',
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
      'provider': 'vertex_ai',
      'project_id': projectId,
      'location': location,
    };

    if (response.containsKey('usageMetadata')) {
      metadata['usage'] = response['usageMetadata'];
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

/// Factory for creating Vertex AI providers.
class VertexAiProviderFactory implements LlmProviderFactory {
  @override
  String get name => 'vertex_ai';

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
    final options = config.options ?? {};

    final projectId = options['project_id'] as String?;
    if (projectId == null || projectId.isEmpty) {
      throw StateError('project_id is required in options for Vertex AI provider');
    }

    final location = options['location'] as String? ?? VertexAiProvider.defaultLocation;

    return VertexAiProvider(
      accessToken: config.apiKey,
      projectId: projectId,
      location: location,
      model: config.model ?? VertexAiProvider.defaultModel,
      baseUrl: config.baseUrl,
      config: config,
    );
  }
}
