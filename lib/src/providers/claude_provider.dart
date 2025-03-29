import 'dart:convert';
import 'dart:io';

import '../core/llm_interface.dart';
import '../core/models.dart';
import '../utils/logger.dart';
import '../utils/performance_monitor.dart';
import 'provider.dart';

/// LLM 제공자 팩토리 구현
class ClaudeProviderFactory implements LlmProviderFactory {
  @override
  String get name => 'claude';

  @override
  Set<LlmCapability> get capabilities => {
    LlmCapability.completion,
    LlmCapability.streaming,
    LlmCapability.embeddings,
    LlmCapability.toolUse,
    LlmCapability.imageUnderstanding,
  };

  @override
  LlmInterface createProvider(LlmConfiguration config) {
    final apiKey = config.apiKey ?? Platform.environment['ANTHROPIC_API_KEY'];
    if (apiKey == null) {
      throw StateError('API key is required for Claude provider');
    }

    return ClaudeProvider(
      apiKey: apiKey,
      model: config.model ?? 'claude-3-5-sonnet-20241022',
      baseUrl: config.baseUrl,
      options: config.options,
    );
  }
}

/// LLM 제공자 구현 (Claude)
class ClaudeProvider implements LlmInterface {
  final String apiKey;
  final String model;
  final String? baseUrl;
  final Map<String, dynamic>? options;
  final HttpClient _client = HttpClient();
  final Logger _logger = Logger.getLogger('mcp_llm.claude_provider');

  ClaudeProvider({
    required this.apiKey,
    this.model = 'claude-3-5-sonnet-20241022',
    this.baseUrl,
    this.options,
  });

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    try {
      // 요청 데이터 구성
      final requestBody = _buildRequestBody(request);

      // API 요청
      final uri = Uri.parse(baseUrl ?? 'https://api.anthropic.com/v1/messages');
      final httpRequest = await _client.postUrl(uri);

      // 헤더 설정
      httpRequest.headers.set('Content-Type', 'application/json');
      httpRequest.headers.set('x-api-key', apiKey);
      httpRequest.headers.set('anthropic-version', '2023-06-01');

      // 요청 본문 추가
      httpRequest.write(jsonEncode(requestBody));

      // 응답 받기
      final httpResponse = await httpRequest.close();
      final responseBody = await utf8.decoder.bind(httpResponse).join();

      // 응답 파싱
      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        final responseJson = jsonDecode(responseBody) as Map<String, dynamic>;

        // 결과 생성
        final response = _parseResponse(responseJson);

        return response;
      } else {
        // 에러 처리
        final error = 'API Error: ${httpResponse.statusCode} - $responseBody';
        _logger.error(error);

        return LlmResponse(
          text: 'Error: Unable to get a response from Claude.',
          metadata: {'error': error, 'status_code': httpResponse.statusCode},
        );
      }
    } catch (e) {
      _logger.error('Error calling Claude API: $e');

      return LlmResponse(
        text: 'Error: Unable to get a response from Claude.',
        metadata: {'error': e.toString()},
      );
    }
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    try {
      // 요청 데이터 구성
      final requestBody = _buildRequestBody(request);
      requestBody['stream'] = true;

      // API 요청
      final uri = Uri.parse(baseUrl ?? 'https://api.anthropic.com/v1/messages');
      final httpRequest = await _client.postUrl(uri);

      // 헤더 설정
      httpRequest.headers.set('Content-Type', 'application/json');
      httpRequest.headers.set('x-api-key', apiKey);
      httpRequest.headers.set('anthropic-version', '2023-06-01');

      // 요청 본문 추가
      httpRequest.write(jsonEncode(requestBody));

      // 응답 받기
      final httpResponse = await httpRequest.close();

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        // 스트리밍 응답 처리
        await for (final chunk in utf8.decoder.bind(httpResponse)) {
          // SSE 형식 파싱
          for (final line in chunk.split('\n')) {
            if (line.startsWith('data: ') && line.length > 6) {
              final data = line.substring(6);
              if (data == '[DONE]') {
                // 스트리밍 완료
                break;
              }

              try {
                final chunkJson = jsonDecode(data) as Map<String, dynamic>;
                final type = chunkJson['type'] as String?;

                if (type == 'content_block_delta') {
                  final delta = chunkJson['delta'] as Map<String, dynamic>?;
                  if (delta != null && delta.containsKey('text')) {
                    final text = delta['text'] as String? ?? '';

                    yield LlmResponseChunk(
                      textChunk: text,
                      isDone: false,
                      metadata: {},
                    );
                  }
                } else if (type == 'tool_use') {
                  // 도구 사용 응답
                  final toolUse = chunkJson['tool_use'] as Map<String, dynamic>?;
                  if (toolUse != null) {
                    yield LlmResponseChunk(
                      textChunk: '',
                      isDone: false,
                      metadata: {
                        'tool_call_start': true,
                        'tool_name': toolUse['name'],
                        'tool_call_id': toolUse['id'],
                      },
                    );
                  }
                } else if (type == 'tool_use_input_delta') {
                  // 도구 입력 데이터
                  final delta = chunkJson['delta'] as Map<String, dynamic>?;
                  final inputDelta = delta?['input'] as Map<String, dynamic>?;
                  if (inputDelta != null) {
                    yield LlmResponseChunk(
                      textChunk: '',
                      isDone: false,
                      metadata: {
                        'tool_call_args': inputDelta,
                      },
                    );
                  }
                } else if (type == 'message_stop') {
                  // 메시지 종료
                  yield LlmResponseChunk(
                    textChunk: '',
                    isDone: true,
                    metadata: {'complete': true},
                  );
                }
              } catch (e) {
                _logger.error('Error parsing chunk: $e');
              }
            }
          }
        }
      } else {
        // 에러 처리
        final responseBody = await utf8.decoder.bind(httpResponse).join();
        final error = 'API Error: ${httpResponse.statusCode} - $responseBody';
        _logger.error(error);

        yield LlmResponseChunk(
          textChunk: 'Error: Unable to get a streaming response from Claude.',
          isDone: true,
          metadata: {'error': error, 'status_code': httpResponse.statusCode},
        );
      }
    } catch (e) {
      _logger.error('Error streaming from Claude API: $e');

      yield LlmResponseChunk(
        textChunk: 'Error: Unable to get a streaming response from Claude.',
        isDone: true,
        metadata: {'error': e.toString()},
      );
    } finally {
      // 클라이언트 닫기
      _client.close();
    }
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    // Claude 임베딩 API 구현 (생략)
    throw UnimplementedError('Embeddings are not yet implemented for Claude');
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    // 초기화 로직
    _logger.info('Claude provider initialized with model: $model');
  }

  @override
  Future<void> close() async {
    _client.close();
  }

  // 요청 본문 구성 헬퍼 메서드
  Map<String, dynamic> _buildRequestBody(LlmRequest request) {
    // 메시지 구성
    final List<Map<String, dynamic>> messages = [];

    // 이력 추가
    for (final message in request.history) {
      messages.add({
        'role': message.role,
        'content': _convertContentToClaudeFormat(message.content),
      });
    }

    // 현재 메시지 추가
    messages.add({
      'role': 'user',
      'content': request.prompt,
    });

    // 요청 본문 구성
    final Map<String, dynamic> body = {
      'model': model,
      'messages': messages,
      'max_tokens': request.parameters['max_tokens'] ?? 1024,
    };

    // 시스템 프롬프트가 있으면 추가
    if (request.parameters.containsKey('system')) {
      body['system'] = request.parameters['system'];
    }

    // 도구 정보가 있으면 추가
    if (request.parameters.containsKey('tools')) {
      body['tools'] = request.parameters['tools'];
    }

    // 추가 파라미터 적용
    if (request.parameters.containsKey('temperature')) {
      body['temperature'] = request.parameters['temperature'];
    }

    return body;
  }

  // Claude 형식에 맞게 내용 변환
  dynamic _convertContentToClaudeFormat(dynamic content) {
    // 단순 텍스트면 그대로 반환
    if (content is String) {
      return content;
    }

    // 메시지 구조체면 변환
    if (content is Map) {
      // 이미지 내용 변환
      if (content['type'] == 'image') {
        return {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': content['mimeType'] ?? 'image/jpeg',
            'data': content['data'] ?? content['base64'],
          }
        };
      }

      // 텍스트 내용 변환
      if (content['type'] == 'text') {
        return content['text'];
      }
    }

    // 기본적으로 문자열 변환
    return content.toString();
  }

  // 응답 파싱 헬퍼 메서드
  LlmResponse _parseResponse(Map<String, dynamic> response) {
    // 응답 내용 추출
    final content = response['content'] as List<dynamic>;
    final text = content
        .where((item) => item['type'] == 'text')
        .map<String>((item) => item['text'] as String)
        .join('\n');

    // 도구 호출 추출
    List<ToolCall>? toolCalls;
    final toolUses = response['tool_uses'] as List<dynamic>?;
    if (toolUses != null && toolUses.isNotEmpty) {
      toolCalls = toolUses.map((tool) {
        return ToolCall(
          name: tool['name'] as String,
          arguments: tool['input'] as Map<String, dynamic>,
        );
      }).toList();
    }

    // 메타데이터 구성
    final metadata = <String, dynamic>{
      'model': response['model'],
      'stop_reason': response['stop_reason'],
      'usage': response['usage'],
    };

    return LlmResponse(
      text: text,
      metadata: metadata,
      toolCalls: toolCalls,
    );
  }
}
