// A sampling request reaches the provider's API whole: an image in the
// message as an image (it used to become the text "[image image/png]", or
// "Instance of 'LlmImageContent'"), and stopSequences (no provider sent
// them).

import 'dart:convert';
import 'dart:io';

import 'package:mcp_llm/mcp_llm.dart';
import 'package:test/test.dart';

const _png = 'iVBORw0KGgo=';

final _params = <String, dynamic>{
  'messages': [
    {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': 'What is in this picture?'},
        {'type': 'image', 'data': _png, 'mimeType': 'image/png'},
      ],
    },
  ],
  'maxTokens': 50,
  'stopSequences': ['END'],
};

/// A local endpoint that records the request body and answers [reply].
Future<(HttpServer, List<Map<String, dynamic>>)> _endpoint(Map<String, dynamic> reply) async {
  final bodies = <Map<String, dynamic>>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    bodies.add(jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>);
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(reply));
    await request.response.close();
  });
  return (server, bodies);
}

void main() {
  final config = LlmConfiguration(retryOnFailure: false);

  test('OpenAI: the image is an image_url part, stopSequences is stop', () async {
    final (server, bodies) = await _endpoint({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'a pixel'},
          'finish_reason': 'stop',
        },
      ],
    });
    addTearDown(() => server.close(force: true));
    final provider = OpenAiProvider(apiKey: 'k', model: 'm', baseUrl: 'http://127.0.0.1:${server.port}', config: config);
    final result = await McpSamplingHandler(provider, model: 'm').handle(_params);

    expect(result['content'], {'type': 'text', 'text': 'a pixel'});
    final body = bodies.single;
    expect(body['stop'], ['END']);
    final messages = body['messages'] as List;
    expect(messages, contains(equals({
      'role': 'user',
      'content': [
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,$_png'},
        },
      ],
    })));
    expect(messages.last, {'role': 'user', 'content': 'What is in this picture?'});
  });

  test('Claude: the image is a base64 image block, stopSequences is stop_sequences', () async {
    final (server, bodies) = await _endpoint({
      'content': [
        {'type': 'text', 'text': 'a pixel'},
      ],
      'stop_reason': 'end_turn',
    });
    addTearDown(() => server.close(force: true));
    final provider = ClaudeProvider(
        apiKey: 'k', model: 'm', baseUrl: 'http://127.0.0.1:${server.port}/v1/messages', config: config);
    await McpSamplingHandler(provider, model: 'm').handle(_params);

    final body = bodies.single;
    expect(body['stop_sequences'], ['END']);
    final blocks = [
      for (final m in body['messages'] as List)
        if ((m as Map)['content'] is List) ...(m['content'] as List),
    ];
    final image = blocks.firstWhere((b) => (b as Map)['type'] == 'image') as Map;
    expect(image['source'], {'type': 'base64', 'media_type': 'image/png', 'data': _png});
  });

  test('Gemini: the image is inlineData, stopSequences is generationConfig.stopSequences', () async {
    final (server, bodies) = await _endpoint({
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {'text': 'a pixel'},
            ],
          },
          'finishReason': 'STOP',
        },
      ],
    });
    addTearDown(() => server.close(force: true));
    final provider = GeminiProvider(
        apiKey: 'k', model: 'gemini-3.5-flash-lite', baseUrl: 'http://127.0.0.1:${server.port}/v1beta', config: config);
    await McpSamplingHandler(provider, model: 'm').handle(_params);

    final body = bodies.single;
    expect((body['generationConfig'] as Map)['stopSequences'], ['END']);
    final parts = [for (final c in body['contents'] as List) ...((c as Map)['parts'] as List)];
    expect(parts, contains(equals({
      'inlineData': {'mimeType': 'image/png', 'data': _png},
    })));
  });
}
