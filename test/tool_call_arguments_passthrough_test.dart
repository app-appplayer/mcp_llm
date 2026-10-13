// A tool call reaches the tool with the arguments the model gave.
//
// Four providers used to fill a required argument the model left out — 0,
// false, '', the first enum value, and for a tool named `calculator` numbers
// scraped from the user's message — and the tool then ran with values nobody
// chose. The server validates arguments against `inputSchema` and answers a
// missing one as a tool error the model can correct (2025-11-25), so the call
// goes as it was made.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_llm/src/providers/aws_event_stream.dart';
import 'package:test/test.dart';

/// A local endpoint that answers every POST with [events] as an SSE stream.
Future<HttpServer> _sse(List<Object> events) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    await utf8.decoder.bind(request).join();
    request.response.headers.contentType = ContentType('text', 'event-stream');
    for (final e in events) {
      if (e is Map && e.containsKey('_event')) {
        request.response.write('event: ${e['_event']}\n');
        final data = Map.of(e)..remove('_event');
        request.response.write('data: ${jsonEncode(data)}\n\n');
      } else {
        request.response.write('data: ${e is String ? e : jsonEncode(e)}\n\n');
      }
    }
    await request.response.close();
  });
  return server;
}

final _transfer = {
  'name': 'transfer',
  'description': 'moves money',
  'parameters': {
    'type': 'object',
    'properties': {
      'amount': {'type': 'number'},
      'to': {
        'type': 'string',
        'enum': ['savings', 'checking'],
      },
    },
    'required': ['amount', 'to'],
  },
};

LlmRequest _request() => LlmRequest(
      prompt: 'move it',
      parameters: {
        'tools': [_transfer],
      },
    );

/// The OpenAI-shaped stream: one tool call whose arguments name only `to`,
/// split over two chunks.
final _openAiStyle = <Object>[
  {
    'choices': [
      {
        'delta': {
          'tool_calls': [
            {
              'index': 0,
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'transfer', 'arguments': '{"to":'},
            },
          ],
        },
      },
    ],
  },
  // The arguments arrive in fragments, as the API sends them.
  {
    'choices': [
      {
        'delta': {
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': '"savings"}'},
            },
          ],
        },
      },
    ],
  },
  {
    'choices': [
      {'delta': <String, dynamic>{}, 'finish_reason': 'tool_calls'},
    ],
  },
  '[DONE]',
];

Future<Map<String, dynamic>> _lastArguments(Stream<LlmResponseChunk> stream) async {
  Map<String, dynamic>? args;
  await for (final chunk in stream) {
    final calls = chunk.toolCalls;
    if (calls != null && calls.isNotEmpty) args = calls.single.arguments;
  }
  return args!;
}

void main() {
  final config = LlmConfiguration(retryOnFailure: false);

  for (final entry in <String, LlmInterface Function(String)>{
    'OpenAI': (url) => OpenAiProvider(apiKey: 'k', model: 'm', baseUrl: url, config: config),
    'Groq': (url) => GroqProvider(apiKey: 'k', model: 'm', baseUrl: '$url/v1', config: config),
    'Mistral': (url) => MistralProvider(apiKey: 'k', model: 'm', baseUrl: '$url/v1', config: config),
  }.entries) {
    test('${entry.key}: a required argument the model left out stays out', () async {
      final server = await _sse(_openAiStyle);
      addTearDown(() => server.close(force: true));
      final provider = entry.value('http://127.0.0.1:${server.port}');
      final args = await _lastArguments(provider.streamComplete(_request()));
      expect(args, {'to': 'savings'});
    });
  }

  test('Claude: a required argument the model left out stays out', () async {
    final server = await _sse([
      {
        '_event': 'message_start',
        'type': 'message_start',
        'message': {'id': 'msg', 'role': 'assistant', 'content': <Object>[]},
      },
      {
        '_event': 'content_block_start',
        'type': 'content_block_start',
        'index': 0,
        'content_block': {'type': 'tool_use', 'id': 'toolu_1', 'name': 'transfer', 'input': <String, dynamic>{}},
      },
      {
        '_event': 'content_block_delta',
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'input_json_delta', 'partial_json': '{"to":'},
      },
      {
        '_event': 'content_block_delta',
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'input_json_delta', 'partial_json': '"savings"}'},
      },
      {'_event': 'content_block_stop', 'type': 'content_block_stop', 'index': 0},
      {
        '_event': 'message_delta',
        'type': 'message_delta',
        'delta': {'stop_reason': 'tool_use'},
      },
      {'_event': 'message_stop', 'type': 'message_stop'},
    ]);
    addTearDown(() => server.close(force: true));
    final provider = ClaudeProvider(
        apiKey: 'k', model: 'm', baseUrl: 'http://127.0.0.1:${server.port}/v1/messages', config: config);
    final args = await _lastArguments(provider.streamComplete(_request()));
    expect(args, {'to': 'savings'});
  });

  test('Bedrock (Anthropic): a required argument the model left out stays out, '
      'read from the binary event stream', () async {
    final frames = [
      for (final payload in [
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'tool_use', 'id': 'toolu_1', 'name': 'transfer', 'input': <String, dynamic>{}},
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"to":'},
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'input_json_delta', 'partial_json': '"savings"}'},
        },
        {'type': 'content_block_stop', 'index': 0},
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
        },
        {'type': 'message_stop'},
      ])
        _frame({':event-type': 'chunk', ':content-type': 'application/json', ':message-type': 'event'},
            utf8.encode(jsonEncode({'bytes': base64Encode(utf8.encode(jsonEncode(payload)))}))),
    ];
    final bytes = [for (final f in frames) ...f];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType('application', 'vnd.amazon.eventstream');
      // Network pieces that cut through frames and headers.
      for (var i = 0; i < bytes.length; i += 37) {
        request.response.add(bytes.sublist(i, i + 37 > bytes.length ? bytes.length : i + 37));
        await request.response.flush();
      }
      await request.response.close();
    });
    final provider = BedrockProvider(
      accessKeyId: 'AKID',
      secretAccessKey: 'secret',
      region: 'us-east-1',
      model: 'anthropic.claude-3-sonnet-20240229-v1:0',
      config: config,
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    final args = await _lastArguments(provider.streamComplete(_request()));
    expect(args, {'to': 'savings'});
  });

  test('the AWS event stream decoder reads string headers and payload, and '
      'holds a message split across pieces', () {
    final decoder = AwsEventStreamDecoder();
    final frame = _frame({':event-type': 'chunk', ':message-type': 'event'}, utf8.encode('{"a":1}'));
    expect(decoder.add(frame.sublist(0, 5)), isEmpty);
    final messages = decoder.add(frame.sublist(5));
    expect(messages.single.headers, {':event-type': 'chunk', ':message-type': 'event'});
    expect(utf8.decode(messages.single.payload), '{"a":1}');
  });
}

/// One AWS event stream message with string headers (CRCs are not checked
/// by the reader, so they are written as zero).
List<int> _frame(Map<String, String> headers, List<int> payload) {
  final h = BytesBuilder();
  headers.forEach((name, value) {
    final n = utf8.encode(name);
    final v = utf8.encode(value);
    h
      ..addByte(n.length)
      ..add(n)
      ..addByte(7)
      ..add([v.length >> 8, v.length & 0xff])
      ..add(v);
  });
  final headerBytes = h.toBytes();
  final total = 12 + headerBytes.length + payload.length + 4;
  final out = ByteData(total);
  out.setUint32(0, total);
  out.setUint32(4, headerBytes.length);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(12, 12 + headerBytes.length, headerBytes);
  bytes.setRange(12 + headerBytes.length, total - 4, payload);
  return bytes;
}
