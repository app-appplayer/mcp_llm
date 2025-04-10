import 'dart:convert';
import 'dart:io';

import '../core/llm_interface.dart';
import '../core/models.dart';
import '../utils/logger.dart';
import 'provider.dart';

/// Implementation of LLM interface for Claude API
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

        logger.warning(
            'Attempt $attempts failed, retrying in ${currentDelay.inMilliseconds}ms: $e');
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

      // Build request body
      final requestBody = _buildRequestBody(request);
      logger.debug('Claude API request body structure created');

      // Prepare API request
      final uri = Uri.parse(baseUrl ?? 'https://api.anthropic.com/v1/messages');
      final httpRequest = await _client.postUrl(uri);

      // Set headers
      httpRequest.headers.set('Content-Type', 'application/json');
      httpRequest.headers.set('x-api-key', apiKey);
      httpRequest.headers.set('anthropic-version', '2023-06-01');

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
        logger.debug('Claude API response received successfully');

        // Parse response
        return _parseResponse(responseJson);
      } else {
        // Handle error
        final error =
            'Claude API Error: ${httpResponse.statusCode} - $responseBody';
        logger.error(error);

        throw Exception(error);
      }
    });
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    try {
      logger.debug('Claude stream request with model: $model');

      // Build request body
      final requestBody = _buildRequestBody(request);
      requestBody['stream'] = true;
      logger.debug('Claude API request body structure created');

      // Prepare API request with retry for connection phase
      final uri = Uri.parse(baseUrl ?? 'https://api.anthropic.com/v1/messages');
      final httpRequest = await executeWithRetry(() async {
        return await _client.postUrl(uri);
      });

      // Set headers
      httpRequest.headers.set('Content-Type', 'application/json');
      httpRequest.headers.set('x-api-key', apiKey);
      httpRequest.headers.set('anthropic-version', '2023-06-01');

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
                logger.debug('Streaming chunk type: ${chunkJson['type']}');

                // Check for different chunk types based on API docs
                final chunkType = chunkJson['type'] as String?;

                if (chunkType == 'content_block_start') {
                  final blockType = chunkJson['content_block']?['type'] as String?;
                  logger.debug('Content block start: $blockType');

                  // If this is a tool_use block start, emit a special chunk
                  if (blockType == 'tool_use') {
                    final toolUse = chunkJson['content_block'] as Map<String, dynamic>?;
                    if (toolUse != null) {
                      final toolName = toolUse['name'] as String? ?? 'unknown';
                      final toolId = toolUse['id'] as String? ?? 'unknown';

                      yield LlmResponseChunk(
                        textChunk: '',
                        isDone: false,
                        metadata: {
                          'is_tool_call': true,
                          'tool_name': toolName,
                          'tool_id': toolId
                        },
                      );
                    }
                  }
                } else if (chunkType == 'content_block_delta') {
                  final delta = chunkJson['delta'] as Map<String, dynamic>?;
                  if (delta != null && delta['type'] == 'text_delta') {
                    final text = delta['text'] as String? ?? '';
                    yield LlmResponseChunk(
                      textChunk: text,
                      isDone: false,
                      metadata: {},
                    );
                  }
                } else if (chunkType == 'message_delta') {
                  // Handle stop reason changes
                  final stopReason = chunkJson['delta']?['stop_reason'] as String?;
                  if (stopReason != null && stopReason.isNotEmpty) {
                    // If stop_reason is tool_use, indicate this in metadata
                    if (stopReason == 'tool_use') {
                      yield LlmResponseChunk(
                        textChunk: '',
                        isDone: true,
                        metadata: {'stop_reason': stopReason, 'expects_tool_result': true},
                      );
                    } else {
                      yield LlmResponseChunk(
                        textChunk: '',
                        isDone: true,
                        metadata: {'stop_reason': stopReason},
                      );
                    }
                  }
                } else if (chunkJson.containsKey('content')) {
                  // Handle legacy format (may be removed in future)
                  final content = chunkJson['content'] as String? ?? '';
                  yield LlmResponseChunk(
                    textChunk: content,
                    isDone: false,
                    metadata: {},
                  );

                  // Check for completion reason
                  final completeReason = chunkJson['stop_reason'] as String?;
                  if (completeReason != null && completeReason.isNotEmpty) {
                    yield LlmResponseChunk(
                      textChunk: '',
                      isDone: true,
                      metadata: {'stop_reason': completeReason},
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
        final error =
            'Claude API Error: ${httpResponse.statusCode} - $responseBody';
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
    throw UnimplementedError('Embeddings are not yet supported for Claude.');
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    logger.info('Claude provider initialized with model: $model');
  }

  @override
  Future<void> close() async {
    _client.close();
    logger.debug('Claude provider client closed');
  }

// Helper method to build request body
  Map<String, dynamic> _buildRequestBody(LlmRequest request) {
    // Build messages
    final List<Map<String, dynamic>> messages = [];
    String? systemContent;

    // Separate system message - Claude API requires it as a separate parameter
    if (request.parameters.containsKey('system') ||
        request.parameters.containsKey('system_instructions')) {
      systemContent = request.parameters['system'] ??
          request.parameters['system_instructions'];
    }

    // Extract system messages from history
    for (final message in request.history) {
      if (message.role == 'system') {
        // System messages are provided as a separate parameter (skip)
        if (systemContent == null || systemContent.isEmpty) {
          systemContent = message.content.toString();
        }
        continue;
      } else if (message.role == 'tool') {
        // Tool result message handling
        final toolContent = message.content;
        dynamic toolResult = '';
        String toolName = '';

        if (toolContent is Map) {
          if (toolContent.containsKey('content')) {
            toolResult = toolContent['content'];
          }
          if (toolContent.containsKey('tool')) {
            toolName = toolContent['tool'];
          } else if (message.metadata.containsKey('tool_name')) {
            toolName = message.metadata['tool_name'];
          }
        }

        // For Claude, we'll format tool results as user messages to ensure they're recognized
        messages.add({
          'role': 'user',
          'content': "Here's the result from the $toolName tool: $toolResult",
        });
      } else if (message.role == 'assistant' && message.metadata.containsKey('tool_call')) {
        // Handle tool calls from assistant
        final toolCallContent = message.content;

        if (toolCallContent is Map && toolCallContent.containsKey('tool_calls')) {
          // For Claude, we need to format the tool calls in a way it understands
          final toolCalls = toolCallContent['tool_calls'] as List;
          String formattedContent = "";

          for (final toolCall in toolCalls) {
            final name = toolCall['name'] ?? '';
            final args = toolCall['arguments'] ?? {};

            formattedContent += "<function>\n";
            formattedContent += '{"name": "$name", "parameters": ${jsonEncode(args)}}';
            formattedContent += "\n</function>\n";
          }

          messages.add({
            'role': 'assistant',
            'content': formattedContent,
          });
        } else {
          // Regular assistant message
          messages.add({
            'role': 'assistant',
            'content': message.content,
          });
        }
      } else {
        // Regular message handling (user 또는 assistant)
        messages.add({
          'role': message.role,
          'content': message.content,
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
      'max_tokens': request.parameters['max_tokens'] ?? 1024,
      'temperature': request.parameters['temperature'] ?? 0.7,
    };

    if (request.parameters.containsKey('top_p')) {
      body['top_p'] = request.parameters['top_p'];
    }

    // Add tool configuration if provided
    if (request.parameters.containsKey('tools')) {
      final tools = request.parameters['tools'] as List<dynamic>;

      // Convert to Claude's tool format
      final claudeTools = tools.map((tool) {
        return {
          'name': tool['name'],
          'description': tool['description'],
          'input_schema': tool['parameters'],
        };
      }).toList();

      body['tools'] = claudeTools;
    }

    if (systemContent != null && systemContent.isNotEmpty) {
      body['system'] = systemContent;
    }

    logger.debug('Claude API request body prepared: ${body.keys.join(', ')}');
    return body;
  }

  // In claude_provider.dart, simplified _parseResponse method
  LlmResponse _parseResponse(Map<String, dynamic> response) {
    try {
      // Log the received response structure for debugging
      logger.debug('Claude response structure: ${response.keys.join(', ')}');

      // Initialize variables
      String text = '';
      List<LlmToolCall>? toolCalls;

      // Check if this is a tool use response
      final stopReason = response['stop_reason'] as String?;
      final isToolUseResponse = stopReason == 'tool_use';

      if (isToolUseResponse) {
        logger.debug('Response has stop_reason "tool_use", indicating a tool call');
      }

      // Process content blocks
      if (response.containsKey('content') && response['content'] is List) {
        final contentList = response['content'] as List;
        logger.debug('Content blocks: ${contentList.length}');

        // Extract all text from text blocks
        for (final item in contentList) {
          if (item is Map<String, dynamic> && item['type'] == 'text') {
            text += item['text'] as String? ?? '';
          }
        }

        // Extract all tool calls from tool_use blocks
        toolCalls = [];
        for (final item in contentList) {
          if (item is Map<String, dynamic> && item['type'] == 'tool_use') {
            final name = item['name'] as String? ?? 'unknown';
            final id = item['id'] as String? ?? 'claude_tool_${DateTime.now().millisecondsSinceEpoch}';

            Map<String, dynamic> arguments = {};
            if (item.containsKey('input') && item['input'] is Map<String, dynamic>) {
              arguments = item['input'] as Map<String, dynamic>;
            }

            logger.debug('Tool use block: name=$name, id=$id');

            toolCalls.add(LlmToolCall(
              id: id,
              name: name,
              arguments: arguments,
            ));
          }
        }

        // If no tool calls were found, set to null
        if (toolCalls.isEmpty) {
          toolCalls = null;
        }
      } else if (response.containsKey('content') && response['content'] is String) {
        // Handle simple string content (less common with newer API versions)
        text = response['content'] as String;
      }

      // Build metadata
      final metadata = <String, dynamic>{
        'model': response['model'] ?? 'unknown',
      };

      // Include stop_reason in metadata
      if (stopReason != null) {
        metadata['stop_reason'] = stopReason;
      }

      // Add tool call IDs to metadata
      if (toolCalls != null && toolCalls.isNotEmpty) {
        metadata['tool_call_ids'] = toolCalls.map((tc) => tc.id).toList();
        logger.debug('Added ${toolCalls.length} tool calls to response');
      }

      return LlmResponse(
        text: text,
        metadata: metadata,
        toolCalls: toolCalls,
      );
    } catch (e, stackTrace) {
      // Log the error and return a basic response
      logger.error('Error parsing Claude response: $e\n$stackTrace');
      return LlmResponse(
        text: "Error parsing the API response. Please try again.",
        metadata: {'error': e.toString()},
        toolCalls: null,
      );
    }
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
    // LlmCapability.embeddings, // 아직 지원하지 않음
    LlmCapability.toolUse,
  };

  @override
  LlmInterface createProvider(LlmConfiguration config) {
    final apiKey = config.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw StateError('API key is required for Claude provider');
    }

    return ClaudeProvider(
      apiKey: apiKey,
      model: config.model ?? 'claude-3-sonnet-20240229',
      baseUrl: config.baseUrl,
      config: config,
    );
  }
}
