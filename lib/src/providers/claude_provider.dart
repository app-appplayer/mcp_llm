import 'dart:convert';

import 'package:http/http.dart' as http;

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
  final http.Client _client = http.Client();

  @override
  final Logger logger = Logger('mcp_llm.claude_provider');

  ClaudeProvider({
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
      
      // Set headers
      final headers = {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
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
        logger.debug('Claude API response received successfully');

        // Parse response
        return _parseResponse(responseJson);
      } else {
        // Handle error
        final error =
            'Claude API Error: ${httpResponse.statusCode} - ${httpResponse.body}';
        logger.error(error);

        throw Exception(error);
      }
    });
  }

  /// In claude_provider.dart - improve tool handling in streaming response
  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    try {
      logger.debug('Claude stream request with model: $model');

      // Build request body
      final requestBody = _buildRequestBody(request);
      requestBody['stream'] = true;
      logger.debug('Claude API request body structure created');

      // Log the tool definitions being sent to Claude
      if (requestBody.containsKey('tools')) {
        logger.debug('SENDING TOOLS TO CLAUDE: ${jsonEncode(requestBody['tools'])}');
      }

      // Prepare API request
      final uri = Uri.parse(baseUrl ?? 'https://api.anthropic.com/v1/messages');
      
      // Set headers
      final headers = {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
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
        // Variables to collect tool call information
        final Map<String, Map<String, dynamic>> toolCallsMap = {}; // id -> tool call info
        List<LlmToolCall>? toolCalls;
        bool processingToolBlock = false;
        String currentToolBlockId = '';
        String currentToolName = '';
        Map<String, dynamic> currentToolInputs = {};

        // Cache for tool definitions from the request
        final Map<String, Map<String, dynamic>> toolDefinitionCache = {};

        // Cache tool definitions from request
        if (request.parameters.containsKey('tools')) {
          final tools = request.parameters['tools'] as List<dynamic>;
          for (final tool in tools) {
            if (tool is Map<String, dynamic> && tool.containsKey('name')) {
              final toolName = tool['name'] as String;
              toolDefinitionCache[toolName] = Map<String, dynamic>.from(tool);
              logger.debug('Cached tool definition: $toolName');
            }
          }
        }

        // Handle streaming response
        await for (final chunk in utf8.decoder.bind(streamedResponse.stream)) {
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

                // Check for different chunk types
                final chunkType = chunkJson['type'] as String?;

                if (chunkType == 'content_block_start') {
                  final blockType = chunkJson['content_block']?['type'] as String?;
                  logger.debug('Content block start: $blockType');

                  // If this is a tool_use block start, track tool use information
                  if (blockType == 'tool_use') {
                    processingToolBlock = true;
                    final currentToolBlock = chunkJson['content_block'] as Map<String, dynamic>?;

                    if (currentToolBlock != null) {
                      // Log the complete tool block information
                      logger.debug('TOOL CALL START - COMPLETE DATA: ${jsonEncode(currentToolBlock)}');

                      currentToolName = currentToolBlock['name'] as String? ?? 'unknown';
                      currentToolBlockId = currentToolBlock['id'] as String? ?? 'claude_tool_${DateTime.now().millisecondsSinceEpoch}';

                      // Initialize empty inputs
                      currentToolInputs = <String, dynamic>{};

                      // Set initial inputs if available
                      if (currentToolBlock.containsKey('input') &&
                          currentToolBlock['input'] is Map<String, dynamic>) {
                        currentToolInputs = Map<String, dynamic>.from(
                            currentToolBlock['input'] as Map<String, dynamic>);

                        // Log initial inputs
                        logger.debug('TOOL CALL INITIAL INPUTS: ${jsonEncode(currentToolInputs)}');
                      } else {
                        logger.debug('TOOL CALL HAS NO INITIAL INPUTS');
                      }

                      // Add to tool calls map
                      toolCallsMap[currentToolBlockId] = {
                        'name': currentToolName,
                        'arguments': Map<String, dynamic>.from(currentToolInputs),
                      };

                      // If this is the first tool call, initialize the list
                      toolCalls ??= [];

                      // Create a tool call object with known inputs so far
                      toolCalls.add(LlmToolCall(
                        id: currentToolBlockId,
                        name: currentToolName,
                        arguments: Map<String, dynamic>.from(currentToolInputs),
                      ));

                      // Emit a special chunk for tool use start with enhanced metadata
                      yield LlmResponseChunk(
                        textChunk: '',
                        isDone: false,
                        metadata: {
                          'is_tool_call': true,
                          'tool_name': currentToolName,
                          'tool_id': currentToolBlockId,
                          'tool_call_start': true, // Add OpenAI-compatible field
                          'tool_args': Map<String, dynamic>.from(currentToolInputs), // Include any initial args
                        },
                        toolCalls: toolCalls,
                      );
                    }
                  }
                } else if (chunkType == 'content_block_delta') {
                  final delta = chunkJson['delta'] as Map<String, dynamic>?;

                  // Log the delta for debugging
                  logger.debug('CONTENT BLOCK DELTA: ${jsonEncode(delta)}');

                  // Handle tool input updates
                  if (processingToolBlock && delta != null) {
                    if (delta.containsKey('input') && delta['input'] is Map<String, dynamic>) {
                      // Update tool inputs
                      final inputDelta = delta['input'] as Map<String, dynamic>;

                      // Log before and after update
                      logger.debug('TOOL INPUT DELTA: ${jsonEncode(inputDelta)}');
                      logger.debug('TOOL INPUTS BEFORE UPDATE: ${jsonEncode(currentToolInputs)}');

                      // Update current tool inputs
                      currentToolInputs.addAll(inputDelta);

                      logger.debug('TOOL INPUTS AFTER UPDATE: ${jsonEncode(currentToolInputs)}');

                      // Update entry in tool calls map
                      if (toolCallsMap.containsKey(currentToolBlockId)) {
                        toolCallsMap[currentToolBlockId]!['arguments'] =
                        Map<String, dynamic>.from(currentToolInputs);
                      }

                      // Update the latest tool call with new arguments
                      if (toolCalls != null && toolCalls.isNotEmpty) {
                        // Find the tool call by ID
                        final lastToolCallIndex = toolCalls.indexWhere(
                                (tc) => tc.id == currentToolBlockId);

                        if (lastToolCallIndex >= 0) {
                          // Update the tool call with new args
                          toolCalls[lastToolCallIndex] = LlmToolCall(
                            id: currentToolBlockId,
                            name: currentToolName,
                            arguments: Map<String, dynamic>.from(currentToolInputs),
                          );
                        }
                      }

                      // Emit a special chunk for tool argument updates with enhanced metadata
                      yield LlmResponseChunk(
                        textChunk: '',
                        isDone: false,
                        metadata: {
                          'is_tool_call': true,
                          'tool_name': currentToolName,
                          'tool_id': currentToolBlockId,
                          'tool_call_update': true, // Add OpenAI-compatible field
                          'tool_args': Map<String, dynamic>.from(currentToolInputs), // Include updated args
                        },
                        toolCalls: toolCalls,
                      );
                    }
                  }

                  // Handle text delta
                  if (delta != null && delta['type'] == 'text_delta') {
                    final text = delta['text'] as String? ?? '';
                    yield LlmResponseChunk(
                      textChunk: text,
                      isDone: false,
                      metadata: {},
                      toolCalls: toolCalls,
                    );
                  }
                } else if (chunkType == 'content_block_stop') {
                  // Content block ended
                  if (processingToolBlock) {
                    // Log the final state of the tool call
                    logger.debug('TOOL CALL ENDED - FINAL INPUTS: ${jsonEncode(currentToolInputs)}');

                    // When a tool block ends, fill in any missing required arguments
                    if (toolDefinitionCache.containsKey(currentToolName) && currentToolBlockId.isNotEmpty) {
                      final toolDef = toolDefinitionCache[currentToolName]!;
                      final inputSchema = toolDef['parameters'] as Map<String, dynamic>?;

                      // Log the tool definition and schema
                      logger.debug('TOOL DEFINITION: ${jsonEncode(toolDef)}');
                      if (inputSchema != null) {
                        logger.debug('TOOL INPUT SCHEMA: ${jsonEncode(inputSchema)}');
                      }

                      final List<String> requiredArgs = [];
                      Map<String, dynamic> propertyDefs = {};

                      // Get list of required args and property definitions
                      if (inputSchema != null) {
                        if (inputSchema.containsKey('required')) {
                          final required = inputSchema['required'] as List<dynamic>;
                          for (final arg in required) {
                            requiredArgs.add(arg.toString());
                          }
                        }

                        // Get property definitions
                        if (inputSchema.containsKey('properties') &&
                            inputSchema['properties'] is Map<String, dynamic>) {
                          propertyDefs = inputSchema['properties'] as Map<String, dynamic>;
                        }
                      }

                      // Get current arguments
                      final currentArgs = toolCallsMap[currentToolBlockId]?['arguments']
                      as Map<String, dynamic>? ?? {};

                      // Identify missing required arguments
                      final missingArgs = <String>[];
                      for (final arg in requiredArgs) {
                        if (!currentArgs.containsKey(arg) || currentArgs[arg] == null) {
                          missingArgs.add(arg);
                        }
                      }

                      if (missingArgs.isNotEmpty) {
                        logger.warning('Tool call "$currentToolName" is missing required arguments: ${missingArgs.join(", ")}');

                        // Apply default values automatically
                        final updatedArgs = Map<String, dynamic>.from(currentArgs);

                        // For calculator tool specifically, try to parse from the user query
                        if (currentToolName == 'calculator' && missingArgs.contains('operation') &&
                            (missingArgs.contains('a') || missingArgs.contains('b'))) {
                          // Try to extract operation and values from the latest user message
                          final userMessages = request.history.where((msg) => msg.role == 'user').toList();
                          if (userMessages.isNotEmpty) {
                            final lastUserMessage = userMessages.last.content.toString();
                            logger.debug('Trying to extract calculator args from: $lastUserMessage');

                            // Simple pattern matching for common operations
                            if (lastUserMessage.contains('*') || lastUserMessage.toLowerCase().contains('multiply')) {
                              updatedArgs['operation'] = 'multiply';
                            } else if (lastUserMessage.contains('+') || lastUserMessage.toLowerCase().contains('add')) {
                              updatedArgs['operation'] = 'add';
                            } else if (lastUserMessage.contains('-') || lastUserMessage.toLowerCase().contains('subtract')) {
                              updatedArgs['operation'] = 'subtract';
                            } else if (lastUserMessage.contains('/') || lastUserMessage.toLowerCase().contains('divide')) {
                              updatedArgs['operation'] = 'divide';
                            }

                            // Try to extract numbers
                            final numRegex = RegExp(r'(\d+)');
                            final matches = numRegex.allMatches(lastUserMessage).toList();
                            if (matches.length >= 2) {
                              if (missingArgs.contains('a')) {
                                updatedArgs['a'] = double.tryParse(matches[0].group(0) ?? '0') ?? 0;
                              }
                              if (missingArgs.contains('b')) {
                                updatedArgs['b'] = double.tryParse(matches[1].group(0) ?? '0') ?? 0;
                              }
                            }

                            logger.debug('Extracted calculator args: ${jsonEncode(updatedArgs)}');
                          }
                        }

                        // Apply default values for any remaining missing arguments
                        for (final arg in missingArgs) {
                          // Skip if we already filled this arg
                          if (updatedArgs.containsKey(arg) && updatedArgs[arg] != null) {
                            continue;
                          }

                          // Get default value and type from property definition
                          dynamic defaultValue;
                          String? type = 'string';  // Default type is string

                          if (propertyDefs.containsKey(arg)) {
                            final propDef = propertyDefs[arg] as Map<String, dynamic>;

                            // Use explicit default value if specified
                            if (propDef.containsKey('default')) {
                              defaultValue = propDef['default'];
                            }

                            // Get type information
                            if (propDef.containsKey('type')) {
                              type = propDef['type'] as String?;
                            }
                          }

                          // Generate default value if none exists based on type
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
                              // Special handling for string type
                              // Check for enum values
                                if (propertyDefs.containsKey(arg) &&
                                    propertyDefs[arg] is Map<String, dynamic> &&
                                    propertyDefs[arg].containsKey('enum') &&
                                    propertyDefs[arg]['enum'] is List &&
                                    (propertyDefs[arg]['enum'] as List).isNotEmpty) {
                                  // Use first enum value
                                  defaultValue = (propertyDefs[arg]['enum'] as List).first;
                                } else {
                                  defaultValue = '';
                                }
                                break;
                            }
                          }

                          // Apply generated default value
                          updatedArgs[arg] = defaultValue;
                        }

                        // Log the updated arguments
                        logger.debug('TOOL ARGS AFTER AUTO-FILLING: ${jsonEncode(updatedArgs)}');

                        // Update tool call info with fixed arguments
                        toolCallsMap[currentToolBlockId]!['arguments'] = updatedArgs;

                        // Update all tool calls
                        final updatedToolCalls = <LlmToolCall>[];
                        for (final id in toolCallsMap.keys) {
                          final toolInfo = toolCallsMap[id]!;
                          updatedToolCalls.add(LlmToolCall(
                            id: id,
                            name: toolInfo['name'] as String,
                            arguments: Map<String, dynamic>.from(
                                toolInfo['arguments'] as Map<String, dynamic>),
                          ));
                        }

                        toolCalls = updatedToolCalls;

                        // Emit final tool arguments update with filled-in values
                        yield LlmResponseChunk(
                          textChunk: '',
                          isDone: false,
                          metadata: {
                            'is_tool_call': true,
                            'tool_name': currentToolName,
                            'tool_id': currentToolBlockId,
                            'tool_call_update': true,
                            'tool_args': updatedArgs,
                            'auto_filled_args': missingArgs,
                          },
                          toolCalls: toolCalls,
                        );
                      }
                    }

                    // Reset tool processing state
                    processingToolBlock = false;
                    currentToolBlockId = '';
                    currentToolName = '';
                    currentToolInputs = {};
                  }
                } else if (chunkType == 'message_delta') {
                  // Handle stop reason changes
                  final stopReason = chunkJson['delta']?['stop_reason'] as String?;
                  if (stopReason != null && stopReason.isNotEmpty) {
                    logger.debug('MESSAGE STOP REASON: $stopReason');

                    // If stop_reason is tool_use, indicate this in metadata
                    if (stopReason == 'tool_use') {
                      // Log the complete tool calls list
                      if (toolCalls != null) {
                        logger.debug('FINAL TOOL CALLS LIST (${toolCalls.length}): ${jsonEncode(toolCalls.map((tc) => {
                          'id': tc.id,
                          'name': tc.name,
                          'arguments': tc.arguments
                        }).toList())}');

                        // Final verification of all tool calls
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

                                  // Get default value and type from property definition
                                  dynamic defaultValue;
                                  String? type = 'string';  // Default type is string

                                  if (propertyDefs.containsKey(argName)) {
                                    final propDef = propertyDefs[argName] as Map<String, dynamic>;

                                    // Use explicit default value if specified
                                    if (propDef.containsKey('default')) {
                                      defaultValue = propDef['default'];
                                    }

                                    // Get type information
                                    if (propDef.containsKey('type')) {
                                      type = propDef['type'] as String?;
                                    }
                                  }

                                  // Generate default value if none exists based on type
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
                                      // Special handling for string type
                                      // Check for enum values
                                        if (propertyDefs.containsKey(argName) &&
                                            propertyDefs[argName] is Map<String, dynamic> &&
                                            propertyDefs[argName].containsKey('enum') &&
                                            propertyDefs[argName]['enum'] is List &&
                                            (propertyDefs[argName]['enum'] as List).isNotEmpty) {
                                          // Use first enum value
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

                              // Apply updates if needed
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

                      // Emit the final tool call event with all filled-in arguments
                      yield LlmResponseChunk(
                        textChunk: '',
                        isDone: true,
                        metadata: {
                          'stop_reason': stopReason,
                          'expects_tool_result': true,
                          'auto_fixed_tools': true,
                          'finish_reason': 'tool_calls', // Add OpenAI-compatible field
                        },
                        toolCalls: toolCalls,
                      );
                    } else {
                      yield LlmResponseChunk(
                        textChunk: '',
                        isDone: true,
                        metadata: {
                          'stop_reason': stopReason,
                          'finish_reason': stopReason, // Add OpenAI-compatible field
                        },
                        toolCalls: toolCalls,
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
                    toolCalls: toolCalls,
                  );

                  // Check for completion reason
                  final completeReason = chunkJson['stop_reason'] as String?;
                  if (completeReason != null && completeReason.isNotEmpty) {
                    yield LlmResponseChunk(
                      textChunk: '',
                      isDone: true,
                      metadata: {
                        'stop_reason': completeReason,
                        'finish_reason': completeReason, // Add OpenAI-compatible field
                      },
                      toolCalls: toolCalls,
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
        final responseBody = await utf8.decoder.bind(streamedResponse.stream).join();
        final error =
            'Claude API Error: ${streamedResponse.statusCode} - $responseBody';
        logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from Claude.',
          isDone: true,
          metadata: {'error': error, 'status_code': streamedResponse.statusCode},
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
  bool hasToolCallMetadata(Map<String, dynamic> metadata) {
    // Claude style metadata inspection
    if (metadata.containsKey('is_tool_call') && metadata['is_tool_call'] == true) {
      logger.debug('Tool call metadata detected: Claude style (is_tool_call)');
      return true;
    }

    if (metadata.containsKey('stop_reason') && metadata['stop_reason'] == 'tool_use') {
      logger.debug('Tool call metadata detected: Claude style (stop_reason=tool_use)');
      return true;
    }

    // Claude related tool key inspection
    final claudeToolKeys = ['tool_name', 'tool_id', 'expects_tool_result', 'auto_fixed_tools'];
    for (final key in claudeToolKeys) {
      if (metadata.containsKey(key)) {
        logger.debug('Tool call metadata detected: Claude related key ($key)');
        return true;
      }
    }

    return false;
  }

  @override
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) {
    logger.debug('Extracting tool call from Claude metadata');

    // When tool call starts or updates
    if (metadata.containsKey('is_tool_call') && metadata.containsKey('tool_name')) {
      final toolName = metadata['tool_name'] as String;
      final toolId = metadata['tool_id'] as String? ??
          'claude_tool_${DateTime.now().millisecondsSinceEpoch}';

      // Check if arguments exist, found in tool_args field
      Map<String, dynamic> arguments = {};
      if (metadata.containsKey('tool_args') && metadata['tool_args'] is Map<String, dynamic>) {
        arguments = metadata['tool_args'] as Map<String, dynamic>;
      }

      logger.debug('Extracted Claude tool call: name=$toolName, id=$toolId, args=${jsonEncode(arguments)}');

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
    // Convert Claude metadata to standard format
    final standardMetadata = Map<String, dynamic>.from(metadata);

    // Standardize tool call related fields
    if (metadata.containsKey('stop_reason') && metadata['stop_reason'] == 'tool_use') {
      standardMetadata['finish_reason'] = 'tool_calls';
    } else if (metadata.containsKey('stop_reason')) {
      standardMetadata['finish_reason'] = metadata['stop_reason'];
    }

    // Convert is_tool_call to tool_call_start
    if (metadata.containsKey('is_tool_call') && metadata['is_tool_call'] == true) {
      if (!standardMetadata.containsKey('tool_call_start')) {
        standardMetadata['tool_call_start'] = true;
      }
    }

    // Convert tool_id to tool_call_id
    if (metadata.containsKey('tool_id') && !standardMetadata.containsKey('tool_call_id')) {
      standardMetadata['tool_call_id'] = metadata['tool_id'];
    }

    return standardMetadata;
  }

  @override
  Future<void> close() async {
    _client.close();
    logger.debug('Claude provider client closed');
  }

  /// Helper method to build request body
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
        // Regular message handling (user or assistant)
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

      // Enable tool calling
      if (request.parameters.containsKey('tool_choice')) {
        body['tool_choice'] = request.parameters['tool_choice'];
      }
    }

    if (systemContent != null && systemContent.isNotEmpty) {
      body['system'] = systemContent;
      logger.debug('Claude API system: $systemContent');
    }

    logger.debug('Claude API request body prepared: ${body.keys.join(', ')}');
    return body;
  }

  /// In claude_provider.dart, simplified _parseResponse method
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
    // LlmCapability.embeddings, // not supported yet
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
