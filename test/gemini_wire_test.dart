// What GeminiProvider sends, checked against a local endpoint.
//
// - An MCP tool's inputSchema is JSON Schema; Gemini's `parameters` takes an
//   OpenAPI subset and answers 400 to `$schema` / `additionalProperties`, so
//   the schema goes in `parametersJsonSchema`.
// - Gemini 3 answers 400 to a turn whose function call lacks the
//   `thoughtSignature` it came with; the call's `id` pairs the response.
// - The API key travels in `x-goog-api-key`, not the URL an HTTP error
//   message would print.

import 'dart:convert';
import 'dart:io';

import 'package:mcp_llm/mcp_llm.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  final requests = <({Uri uri, Map<String, String> headers, Map<String, dynamic> body})>[];

  setUp(() async {
    requests.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
      final headers = <String, String>{};
      request.headers.forEach((name, values) => headers[name] = values.join(','));
      requests.add((uri: request.uri, headers: headers, body: body));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(requests.length == 1
          ? {
              'candidates': [
                {
                  'content': {
                    'role': 'model',
                    'parts': [
                      {
                        'functionCall': {
                          'id': 'call_9',
                          'name': 'transfer',
                          'args': {'amount': 5, 'to': 'savings'},
                        },
                        'thoughtSignature': 'SIG',
                      },
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
            }
          : {
              'candidates': [
                {
                  'content': {
                    'role': 'model',
                    'parts': [
                      {'text': 'done'},
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
            }));
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('tool schema, signature and id round trip, key in a header', () async {
    final provider = GeminiProvider(
      apiKey: 'SECRET',
      model: 'gemini-3.5-flash-lite',
      baseUrl: 'http://127.0.0.1:${server.port}/v1beta',
      config: LlmConfiguration(retryOnFailure: false),
    );
    final tools = [
      {
        'name': 'transfer',
        'description': 'moves money',
        'parameters': {
          r'$schema': 'http://json-schema.org/draft-07/schema#',
          'type': 'object',
          'properties': {
            'amount': {'type': 'number'},
          },
          'additionalProperties': false,
        },
      },
    ];

    final first = await provider.complete(LlmRequest(prompt: 'move 5', parameters: {'tools': tools}));
    final call = first.toolCalls!.single;
    expect(call.id, 'call_9', reason: 'the id Gemini gave, not a made-up one');
    expect(call.providerData, {'thoughtSignature': 'SIG'});

    final declaration = (requests.first.body['tools'] as List).single['functionDeclarations'][0] as Map;
    expect(declaration.containsKey('parameters'), isFalse);
    expect(declaration['parametersJsonSchema'], tools.single['parameters']);
    expect(requests.first.uri.query, isNot(contains('SECRET')));
    expect(requests.first.headers['x-goog-api-key'], 'SECRET');

    // The next turn, as LlmClient records it.
    await provider.complete(LlmRequest(
      prompt: 'answer',
      parameters: {'tools': tools},
      history: [
        LlmMessage.user('move 5'),
        LlmMessage(
          role: 'assistant',
          content: {
            'tool_calls': [
              {'id': call.id, 'name': call.name, 'arguments': call.arguments, 'providerData': call.providerData},
            ],
          },
          metadata: {'tool_call': true},
        ),
        LlmMessage.tool('transfer', 'moved', toolCallId: call.id),
      ],
    ));
    final contents = requests.last.body['contents'] as List;
    final modelTurn = contents.firstWhere((c) => (c as Map)['role'] == 'model') as Map;
    expect(modelTurn['parts'], [
      {
        'functionCall': {
          'id': 'call_9',
          'name': 'transfer',
          'args': {'amount': 5, 'to': 'savings'},
        },
        'thoughtSignature': 'SIG',
      },
    ]);
    final responseTurn = contents.firstWhere(
        (c) => ((c as Map)['parts'] as List).any((p) => (p as Map).containsKey('functionResponse'))) as Map;
    expect(responseTurn['role'], 'user');
    expect((responseTurn['parts'] as List).single['functionResponse']['id'], 'call_9');
  });
}
