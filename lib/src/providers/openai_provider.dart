import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../mcp_llm.dart';

/// Implementation of LLM interface for OpenAI API
class OpenAiProvider implements LlmInterface, RetryableLlmProvider {
  @override
  final LlmConfiguration config;

  final String apiKey;
  final String model;
  final String? baseUrl;
  final http.Client _client = http.Client();

  @override
  final Logger logger = Logger('mcp_llm.openai_provider');

  OpenAiProvider({
    required this.apiKey,
    required this.model,
    this.baseUrl,
    required this.config,
  });

  /// Concrete implementation of the executeWithRetry method from RetryableLlmProvider
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
      final uri = Uri.parse('${baseUrl ?? 'https://api.openai.com'}/v1/chat/completions');
      
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
        final error = 'OpenAI API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);

        throw Exception(error);
      }
    });
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    try {
      logger.debug('OpenAI stream request with model: $model');

      // Generate request body
      final requestBody = _buildRequestBody(request);
      requestBody['stream'] = true;
      logger.debug('OpenAI API request body structure created');

      // Prepare API request
      final uri = Uri.parse('${baseUrl ?? 'https://api.openai.com'}/v1/chat/completions');
      
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
        // Variables to track tool call information
        final Map<String, Map<String, dynamic>> toolCallsMap = {}; // Variables to track tool call information
        List<LlmToolCall>? toolCalls;
        String currentToolCallId = '';

        // Variables for accumulating response chunks
        final StringBuffer responseText = StringBuffer();
        String? finishReason;

        // Tool definition cache
        final Map<String, Map<String, dynamic>> toolDefinitionCache = {};

        // Cache tool definitions from request
        if (request.parameters.containsKey('tools')) {
          final tools = request.parameters['tools'] as List<dynamic>;
          for (final tool in tools) {
            if (tool is Map<String, dynamic> && tool.containsKey('name')) {
              final toolName = tool['name'] as String;
              toolDefinitionCache[toolName] = Map<String, dynamic>.from(tool);
            }
          }
        }

        // Process streaming response
        await for (final chunk in utf8.decoder.bind(streamedResponse.stream)) {
          // Parse SSE format
          for (final line in chunk.split('\n')) {
            if (line.startsWith('data: ') && line.length > 6) {
              final data = line.substring(6);
              if (data == '[DONE]') {
                // Streaming complete
                if (toolCalls != null && toolCalls.isNotEmpty) {
                  // Check if required arguments are empty and apply default values if needed
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

                // Extract information from response chunk
                final choices = chunkJson['choices'] as List<dynamic>?;
                if (choices != null && choices.isNotEmpty) {
                  final choice = choices[0] as Map<String, dynamic>;
                  finishReason = choice['finish_reason'] as String?;
                  final delta = choice['delta'] as Map<String, dynamic>?;

                  if (delta != null) {
                    // Process text content
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

                    // Process tool calls
                    if (delta.containsKey('tool_calls')) {
                      final deltaToolCalls = delta['tool_calls'] as List<dynamic>?;

                      if (deltaToolCalls != null && deltaToolCalls.isNotEmpty) {
                        toolCalls ??= [];

                        for (final deltaToolCall in deltaToolCalls) {
                          final function = deltaToolCall['function'] as Map<String, dynamic>?;

                          // Process tool call ID
                          if (deltaToolCall.containsKey('id')) {
                            currentToolCallId = deltaToolCall['id'] as String;
                          }

                          // Process tool name
                          if (function != null && function.containsKey('name')) {
                            final toolName = function['name'] as String;

                            // Create new tool call
                            if (!toolCallsMap.containsKey(currentToolCallId)) {
                              toolCallsMap[currentToolCallId] = {
                                'name': toolName,
                                'arguments': '',
                              };

                              // Add to tool calls list
                              final toolIndex = toolCalls.indexWhere((tc) => tc.id == currentToolCallId);
                              if (toolIndex == -1) {
                                toolCalls.add(LlmToolCall(
                                  id: currentToolCallId,
                                  name: toolName,
                                  arguments: <String, dynamic>{},
                                ));
                              }

                              // Emit tool call start event
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

                          // Process tool arguments
                          if (function != null && function.containsKey('arguments')) {
                            final args = function['arguments'] as String;

                            if (toolCallsMap.containsKey(currentToolCallId)) {
                              // Accumulate argument string
                              toolCallsMap[currentToolCallId]!['arguments'] += args;
                              final argsStr = toolCallsMap[currentToolCallId]!['arguments'] as String;

                              try {
                                // Check if accumulated arguments form valid JSON and parse
                                if (_isValidJson(argsStr)) {
                                  final toolArgs = jsonDecode(argsStr) as Map<String, dynamic>;

                                  // Update tool call
                                  final toolIndex = toolCalls.indexWhere((tc) => tc.id == currentToolCallId);
                                  if (toolIndex >= 0) {
                                    toolCalls[toolIndex] = LlmToolCall(
                                      id: currentToolCallId,
                                      name: toolCallsMap[currentToolCallId]!['name'] as String,
                                      arguments: toolArgs,
                                    );
                                  }

                                  // Emit tool argument update event
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
                                // Incomplete JSON - continue accumulating
                                logger.debug('Accumulating arguments for tool call: $currentToolCallId');
                              }
                            }
                          }
                        }
                      }
                    }
                  }

                  // Handle completion
                  if (finishReason != null && finishReason.isNotEmpty) {
                    if (finishReason == 'tool_calls') {
                      // Parse argument strings to JSON for all tool calls
                      for (final entry in toolCallsMap.entries) {
                        final toolId = entry.key;
                        final toolInfo = entry.value;
                        final argsStr = toolInfo['arguments'] as String;

                        try {
                          if (argsStr.isNotEmpty) {
                            final toolArgs = jsonDecode(argsStr) as Map<String, dynamic>;

                            // Update tool calls list
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

                      // Validate and fill tool call arguments
                      if (toolCalls != null) {
                        _validateAndFillToolCallArguments(toolCalls, toolDefinitionCache);
                      }

                      // Emit final tool call event
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
        // Handle error
        final responseBody = await utf8.decoder.bind(streamedResponse.stream).join();
        final error = 'OpenAI API Error: ${streamedResponse.statusCode} - $responseBody';
        logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from OpenAI.',
          isDone: true,
          metadata: {'error': error, 'status_code': streamedResponse.statusCode},
        );
      }
    } catch (e, stackTrace) {
      logger.error('Error streaming from OpenAI API: $e\n$stackTrace');

      yield LlmResponseChunk(
        textChunk: 'Error: Unable to get a streaming response from OpenAI.',
        isDone: true,
        metadata: {'error': e.toString()},
      );
    }
  }

  /// Helper method to check if a JSON string is valid
  bool _isValidJson(String jsonString) {
    try {
      jsonDecode(jsonString);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Validate and fill tool call arguments
  void _validateAndFillToolCallArguments(List<LlmToolCall> toolCalls,
      Map<String, Map<String, dynamic>> toolDefinitionCache) {
    for (int i = 0; i < toolCalls.length; i++) {
      final toolCall = toolCalls[i];
      final toolName = toolCall.name;

      // Get tool definition
      if (toolDefinitionCache.containsKey(toolName)) {
        final toolDef = toolDefinitionCache[toolName]!;
        final inputSchema = toolDef['parameters'] as Map<String, dynamic>?;

        if (inputSchema != null && inputSchema.containsKey('required')) {
          final required = inputSchema['required'] as List<dynamic>;
          final args = toolCall.arguments;
          final propertyDefs = inputSchema.containsKey('properties') &&
              inputSchema['properties'] is Map<String, dynamic> ?
          inputSchema['properties'] as Map<String, dynamic> : {};

          // Check for missing arguments
          bool needsUpdate = false;
          final updatedArgs = Map<String, dynamic>.from(args);

          for (final req in required) {
            final argName = req.toString();
            if (!args.containsKey(argName) || args[argName] == null) {
              needsUpdate = true;

              // Extract default value from property definition
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

              // Generate default value
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

              // Apply generated default value
              updatedArgs[argName] = defaultValue;
            }
          }

          // If update is needed
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
    // Check for OpenAI style metadata
    if (metadata.containsKey('tool_call_start') && metadata['tool_call_start'] == true) {
      logger.debug('Tool call metadata detected: OpenAI style (tool_call_start)');
      return true;
    }

    if (metadata.containsKey('finish_reason') && metadata['finish_reason'] == 'tool_calls') {
      logger.debug('Tool call metadata detected: OpenAI style (finish_reason=tool_calls)');
      return true;
    }

    // Check for OpenAI related tool keys
    final openaiToolKeys = ['tool_call_id', 'tool_calls', 'tool_call_update'];
    for (final key in openaiToolKeys) {
      if (metadata.containsKey(key)) {
        logger.debug('Tool call metadata detected: OpenAI related key ($key)');
        return true;
      }
    }

    return false;
  }

  @override
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) {
    logger.debug('Extracting tool call from OpenAI metadata');

    // Tool call start or update metadata
    if ((metadata.containsKey('tool_call_start') || metadata.containsKey('tool_call_update')) &&
        (metadata.containsKey('tool_name') || metadata.containsKey('tool_call_id'))) {

      final toolName = metadata['tool_name'] as String? ?? 'unknown_tool';
      final toolId = metadata['tool_call_id'] as String? ??
          'openai_tool_${DateTime.now().millisecondsSinceEpoch}';

      // Extract arguments
      Map<String, dynamic> arguments = {};

      // Check 'tool_call_args' field
      if (metadata.containsKey('tool_call_args') &&
          metadata['tool_call_args'] is Map<String, dynamic>) {
        arguments = metadata['tool_call_args'] as Map<String, dynamic>;
      }

      logger.debug('Extracted OpenAI tool call: name=$toolName, id=$toolId, args=${jsonEncode(arguments)}');

      return LlmToolCall(
        id: toolId,
        name: toolName,
        arguments: arguments,
      );
    }

    // If there's a tool_calls array
    if (metadata.containsKey('tool_calls') &&
        metadata['tool_calls'] is List &&
        (metadata['tool_calls'] as List).isNotEmpty) {

      final toolCalls = metadata['tool_calls'] as List;
      final firstToolCall = toolCalls.first;

      if (firstToolCall is Map<String, dynamic>) {
        final toolName = firstToolCall['name'] as String? ?? 'unknown_tool';
        final toolId = firstToolCall['id'] as String? ??
            'openai_tool_${DateTime.now().millisecondsSinceEpoch}';

        Map<String, dynamic> arguments = {};

        // Check arguments field
        if (firstToolCall.containsKey('arguments')) {
          // Parse if it's a JSON string
          if (firstToolCall['arguments'] is String) {
            try {
              arguments = jsonDecode(firstToolCall['arguments'] as String) as Map<String, dynamic>;
            } catch (e) {
              logger.warning('Failed to parse arguments JSON: $e');
            }
          }
          // Use as-is if it's already a Map
          else if (firstToolCall['arguments'] is Map) {
            arguments = Map<String, dynamic>.from(firstToolCall['arguments'] as Map);
          }
        }

        logger.debug('Extracted OpenAI tool call from array: name=$toolName, id=$toolId, args=${jsonEncode(arguments)}');

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
    // Convert OpenAI metadata to standard format
    final standardMetadata = Map<String, dynamic>.from(metadata);

    // Standardize tool call related fields
    if (metadata.containsKey('finish_reason') && metadata['finish_reason'] == 'tool_calls') {
      if (!standardMetadata.containsKey('expects_tool_result')) {
        standardMetadata['expects_tool_result'] = true;
      }
    }

    // Convert tool_call_start to is_tool_call
    if (metadata.containsKey('tool_call_start') && metadata['tool_call_start'] == true) {
      standardMetadata['is_tool_call'] = true;
    }

    // Convert tool_call_id to tool_id
    if (metadata.containsKey('tool_call_id') && !standardMetadata.containsKey('tool_id')) {
      standardMetadata['tool_id'] = metadata['tool_call_id'];
    }

    return standardMetadata;
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return await executeWithRetry(() async {
      logger.debug('OpenAI embeddings request');

      // Prepare API request
      final uri = Uri.parse('${baseUrl ?? 'https://api.openai.com'}/v1/embeddings');
      
      // Set headers
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

      // Add request body
      final requestBody = {
        'input': text,
        'model': 'text-embedding-3-large',
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
          throw StateError('No embedding data returned from OpenAI API');
        }
      } else {
        // Handle error
        final error = 'OpenAI API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
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

  /// Helper method to build request body
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
      if (request.parameters.containsKey('tool_choice')) {
        body['tool_choice'] = request.parameters['tool_choice'];
      }
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

  /// Helper method to parse response
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

    // Add tool call IDs to metadata
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
