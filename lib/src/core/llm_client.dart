import '../../mcp_llm.dart';
import '../interface/mcp_client_interface.dart';

class LlmClient {
  final LlmInterface llmProvider;
  final IMcpClientInstance? mcpClient;
  final StorageManager? storageManager;
  final PluginManager pluginManager;
  late final ChatSession chatSession;

  final PerformanceMonitor _performanceMonitor;

  // 생성자
  LlmClient({
    required this.llmProvider,
    this.mcpClient,
    this.storageManager,
    required this.pluginManager,
    required PerformanceMonitor performanceMonitor,
  }) : _performanceMonitor = performanceMonitor {
    chatSession = ChatSession(
      llmProvider: llmProvider,
      storageManager: storageManager,
    );
  }

  // MCP 클라이언트 연결
  Future<void> connectMcpClient(McpClient client) async {
    // 기존 구현
  }

  // 채팅 실행 (플러그인 지원 추가)
  Future<LlmResponse> chat(String userInput, {
    bool enableTools = true,
    bool enablePlugins = true,
    Map<String, dynamic> parameters = const {},
    LlmContext? context,
  }) async {
    // 사용자 입력을 채팅 세션에 추가
    chatSession.addUserMessage(userInput);

    // 사용 가능한 모든 도구 목록 준비
    List<Tool> availableTools = [];

    // 1. MCP 클라이언트에서 도구 가져오기
    if (enableTools && mcpClient != null) {
      try {
        final toolsResult = await mcpClient!.listTools();
        availableTools.addAll(toolsResult.tools);
      } catch (e) {
        log.warning('Failed to get tools from MCP client: $e');
      }
    }

    // 2. 플러그인에서 도구 가져오기
    if (enablePlugins) {
      try {
        final plugins = pluginManager.getAllToolPlugins();
        for (final plugin in plugins) {
          availableTools.add(plugin.getToolDefinition());
        }
      } catch (e) {
        log.warning('Failed to get tools from plugins: $e');
      }
    }

    // LLM 요청 생성
    final LlmRequest request = LlmRequest(
      prompt: userInput,
      history: chatSession.getMessagesForContext(),
      parameters: parameters,
      context: context,
    );

    // 도구 정보를 LLM에 전달
    if (availableTools.isNotEmpty) {
      final toolDescriptions = availableTools.map((tool) {
        return {
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.inputSchema,
        };
      }).toList();

      request.parameters['tools'] = toolDescriptions;
    }

    // LLM 요청 보내기
    LlmResponse response = await llmProvider.complete(request);

    // 도구 호출 처리
    if (response.toolCalls != null && response.toolCalls!.isNotEmpty) {
      for (final toolCall in response.toolCalls!) {
        CallToolResult? toolResult;

        // 1. MCP 도구 확인
        if (mcpClient != null && enableTools) {
          try {
            toolResult = await _tryMcpTool(toolCall);
          } catch (e) {
            log.warning('MCP tool execution failed: $e');
          }
        }

        // 2. 플러그인 도구 확인
        if (toolResult == null && enablePlugins) {
          try {
            toolResult = await _tryPluginTool(toolCall);
          } catch (e) {
            log.warning('Plugin tool execution failed: $e');
          }
        }

        // 도구 실행 결과 처리
        if (toolResult != null) {
          chatSession.addToolResult(
            toolCall.name,
            toolCall.arguments,
            toolResult.content,
          );

          // 후속 LLM 요청
          final followUpRequest = LlmRequest(
            prompt: "Based on the tool result, answer the original question: \"$userInput\"",
            history: chatSession.getMessagesForContext(),
            parameters: parameters,
            context: context,
          );

          response = await llmProvider.complete(followUpRequest);
        } else {
          // 도구 실행 실패
          chatSession.addToolError(toolCall.name, "Tool not found or execution failed");
          response = LlmResponse(
            text: "I tried to use a tool called '${toolCall.name}', but it wasn't available or failed.",
            metadata: {'error': 'Tool not found or execution failed'},
          );
        }
      }
    }

    // 최종 응답 처리
    chatSession.addAssistantMessage(response.text);
    return response;
  }

  // MCP 도구 실행 시도
  Future<CallToolResult?> _tryMcpTool(ToolCall toolCall) async {
    if (mcpClient == null) return null;

    try {
      return await mcpClient!.callTool(
        name: toolCall.name,
        arguments: toolCall.arguments,
      );
    } catch (e) {
      log.error('MCP tool execution error: $e');
      return null;
    }
  }

  // 플러그인 도구 실행 시도
  Future<CallToolResult?> _tryPluginTool(ToolCall toolCall) async {
    final plugin = pluginManager.getToolPlugin(toolCall.name);
    if (plugin == null) return null;

    try {
      return await plugin.execute(toolCall.arguments);
    } catch (e) {
      log.error('Plugin tool execution error: $e');
      return null;
    }
  }

// 스트리밍 채팅 구현 (플러그인 지원 추가)
  Stream<LlmResponseChunk> streamChat(String userInput, {
    bool enableTools = true,
    bool enablePlugins = true,
    Map<String, dynamic> parameters = const {},
    LlmContext? context,
  }) async* {
    // 사용자 입력을 채팅 세션에 추가
    chatSession.addUserMessage(userInput);

    // 사용 가능한 모든 도구 목록 준비
    List<Tool> availableTools = [];

    // 1. MCP 클라이언트에서 도구 가져오기
    if (enableTools && mcpClient != null) {
      try {
        final toolsResult = await mcpClient!.listTools();
        availableTools.addAll(toolsResult.tools);
      } catch (e) {
        log.warning('Failed to get tools from MCP client: $e');
      }
    }

    // 2. 플러그인에서 도구 가져오기
    if (enablePlugins) {
      try {
        final plugins = pluginManager.getAllToolPlugins();
        for (final plugin in plugins) {
          availableTools.add(plugin.getToolDefinition());
        }
      } catch (e) {
        log.warning('Failed to get tools from plugins: $e');
      }
    }

    // LLM 요청 생성
    final LlmRequest request = LlmRequest(
      prompt: userInput,
      history: chatSession.getMessagesForContext(),
      parameters: parameters,
      context: context,
    );

    // 도구 정보를 LLM에 전달
    if (availableTools.isNotEmpty) {
      final toolDescriptions = availableTools.map((tool) {
        return {
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.inputSchema,
        };
      }).toList();

      request.parameters['tools'] = toolDescriptions;
    }

    // 응답 내용을 담을 버퍼
    final StringBuffer responseBuffer = StringBuffer();
    ToolCall? pendingToolCall;

    // LLM에서 스트리밍 응답 받기
    await for (final chunk in llmProvider.streamComplete(request)) {
      // 응답 조각 처리
      responseBuffer.write(chunk.textChunk);

      // 도구 호출 감지
      if (chunk.metadata.containsKey('tool_call_start') && pendingToolCall == null) {
        final toolName = chunk.metadata['tool_name'] as String?;
        if (toolName != null) {
          pendingToolCall = ToolCall(name: toolName, arguments: {});
          yield LlmResponseChunk(
            textChunk: "\n[Starting tool call: $toolName]",
            metadata: {'tool_call_start': true, 'tool_name': toolName},
          );
        }
      } else if (chunk.metadata.containsKey('tool_call_args') && pendingToolCall != null) {
        // 도구 인수 업데이트
        final args = chunk.metadata['tool_call_args'] as Map<String, dynamic>?;
        if (args != null) {
          pendingToolCall.arguments.addAll(args);
        }
      } else if (chunk.metadata.containsKey('tool_call_end') && pendingToolCall != null) {
        // 도구 호출 완료
        yield LlmResponseChunk(
          textChunk: "\n[Executing tool: ${pendingToolCall.name}]",
          metadata: {'tool_execution_start': true, 'tool_name': pendingToolCall.name},
        );

        // 도구 실행
        CallToolResult? toolResult;

        // 1. MCP 도구 확인
        if (mcpClient != null && enableTools) {
          try {
            toolResult = await _tryMcpTool(pendingToolCall);
          } catch (e) {
            log.warning('MCP tool execution failed: $e');
          }
        }

        // 2. 플러그인 도구 확인
        if (toolResult == null && enablePlugins) {
          try {
            toolResult = await _tryPluginTool(pendingToolCall);
          } catch (e) {
            log.warning('Plugin tool execution failed: $e');
          }
        }

        // 도구 실행 결과 처리
        if (toolResult != null) {
          // 도구 결과를 채팅 세션에 추가
          chatSession.addToolResult(
            pendingToolCall.name,
            pendingToolCall.arguments,
            toolResult.content,
          );

          // 도구 실행 결과 스트리밍으로 반환
          yield LlmResponseChunk(
            textChunk: "\n[Tool result: ${toolResult.content.map((c) => c.toString()).join('\n')}]",
            metadata: {'tool_result': true, 'tool_name': pendingToolCall!.name},
          );

          // 후속 LLM 요청
          final followUpRequest = LlmRequest(
            prompt: "Based on the tool result, continue answering the original question",
            history: chatSession.getMessagesForContext(),
            parameters: parameters,
            context: context,
          );

          // 후속 응답 스트리밍
          yield LlmResponseChunk(
            textChunk: "\n[Continuing based on tool result]",
            metadata: {'continue_after_tool': true},
          );

          await for (final followUpChunk in llmProvider.streamComplete(followUpRequest)) {
            yield followUpChunk;
            responseBuffer.write(followUpChunk.textChunk);
          }
        } else {
          // 도구 실행 실패
          chatSession.addToolError(pendingToolCall!.name, "Tool not found or execution failed");
          yield LlmResponseChunk(
            textChunk: "\n[Tool execution failed: ${pendingToolCall.name}]",
            metadata: {'tool_error': true, 'tool_name': pendingToolCall.name},
          );
        }

        pendingToolCall = null;
      } else {
        // 일반 텍스트 조각
        yield chunk;
      }
    }

    // 최종 응답을 채팅 세션에 추가
    chatSession.addAssistantMessage(responseBuffer.toString());

    // 완료 알림
    yield LlmResponseChunk(
      textChunk: "",
      isDone: true,
      metadata: {'complete': true},
    );
  }

  // 성능 모니터링 활성화
  void enablePerformanceMonitoring({Duration interval = const Duration(seconds: 10)}) {
    _performanceMonitor.startMonitoring(interval);
  }

  // 성능 모니터링 비활성화
  void disablePerformanceMonitoring() {
    _performanceMonitor.stopMonitoring();
  }

  // 리소스 정리
  Future<void> close() async {
    await llmProvider.close();
    _performanceMonitor.stopMonitoring();
  }
}