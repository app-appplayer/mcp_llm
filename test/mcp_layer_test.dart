/// The MCP layer (docs/MCP-LAYER-DESIGN.md): the client bridge, the tool
/// result renderer, handler results on the server side, and sampling.
library;

import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_llm/mcp_types.dart' as mcp;
import 'package:test/test.dart';

/// A client with paged listing, like mcp_client's.
class _PagedClient {
  final calls = <String?>[];
  Future<Map<String, dynamic>> listToolsPage({String? cursor}) async {
    calls.add(cursor);
    return switch (cursor) {
      null => {'tools': [{'name': 'a', 'inputSchema': {'type': 'object'}}], 'nextCursor': 'p2'},
      'p2' => {'tools': [{'name': 'b', 'inputSchema': {'type': 'object'}}], 'nextCursor': 'p3'},
      _ => {'tools': [{'name': 'c', 'inputSchema': {'type': 'object'}}]},
    };
  }

  Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> args) async => {
        'content': [
          {'type': 'text', 'text': 'hello'},
        ],
        'structuredContent': {'n': 1},
      };

  Object? lastMeta;
  Future<Map<String, dynamic>> getPrompt(String name, [Map<String, dynamic>? args, Map<String, dynamic>? meta]) async {
    lastMeta = meta;
    return {
      'messages': [
        {'role': 'user', 'content': {'type': 'text', 'text': 'hi $name'}},
      ],
    };
  }
}

/// A client whose server keeps repeating a cursor.
class _CompletingClient {
  final seen = <Object?>[];
  Future<Map<String, dynamic>> complete(Map<String, dynamic> ref, Map<String, dynamic> argument,
      {Map<String, dynamic>? context}) async {
    seen.addAll([ref, argument, context]);
    return {'completion': {'values': ['dart'], 'total': 1, 'hasMore': false}};
  }
}

class _LoopingClient {
  Future<Map<String, dynamic>> listToolsPage({String? cursor}) async =>
      {'tools': [{'name': 't', 'inputSchema': {'type': 'object'}}], 'nextCursor': 'same'};
}

/// A client without paged listing.
class _PlainClient {
  Future<List<Map<String, dynamic>>> listTools() async => [
        {'name': 'only', 'inputSchema': {'type': 'object'}},
      ];
}

class _Failure implements Exception {
  _Failure(this.code, this.message, this.data);
  final int code;
  final String message;
  final Object? data;
}

class _FailingClient {
  Future<dynamic> readResource(String uri) async => throw _Failure(-32002, 'Resource not found', {'uri': uri});
}

class _Provider implements LlmProvider {
  _Provider(this.response);
  final LlmResponse response;
  LlmRequest? seen;
  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    seen = request;
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('McpClientBridge', () {
    test('follows nextCursor across every page', () async {
      final client = _PagedClient();
      final tools = await McpClientBridge(client).listTools();
      expect(tools.map((t) => t.name), ['a', 'b', 'c']);
      expect(client.calls, [null, 'p2', 'p3']);
    });

    test('completion/complete comes back typed', () async {
      final client = _CompletingClient();
      final result = await McpClientBridge(client)
          .complete({'type': 'ref/prompt', 'name': 'p'}, {'name': 'lang', 'value': 'da'}, context: {'arguments': {}});
      expect(result.completion.values, ['dart']);
      expect(client.seen, [{'type': 'ref/prompt', 'name': 'p'}, {'name': 'lang', 'value': 'da'}, {'arguments': {}}]);
    });

    test('stops when the server repeats a cursor', () async {
      final tools = await McpClientBridge(_LoopingClient()).listTools();
      expect(tools, hasLength(2));
    });

    test('a client without paged listing answers in one call', () async {
      expect((await McpClientBridge(_PlainClient()).listTools()).single.name, 'only');
    });

    test('a failure keeps its JSON-RPC code and data; nothing is made up', () async {
      await expectLater(
        McpClientBridge(_FailingClient()).readResource('x://y'),
        throwsA(isA<McpLayerException>()
            .having((e) => e.code, 'code', -32002)
            .having((e) => e.method, 'method', 'resources/read')
            .having((e) => e.data, 'data', {'uri': 'x://y'})),
      );
      await expectLater(McpClientBridge(_PlainClient()).callTool('t', {}), throwsA(isA<McpLayerException>()));
    });

    test('typed results; prompt meta goes where the client takes it', () async {
      final client = _PagedClient();
      final bridge = McpClientBridge(client);
      final r = await bridge.callTool('t', {});
      expect((r.content.single as mcp.TextContent).text, 'hello');
      expect(r.structuredContent, {'n': 1});
      final p = await bridge.getPrompt('p', {}, meta: {'k': 1});
      expect(client.lastMeta, {'k': 1});
      expect((p.messages.single.content as mcp.TextContent).text, 'hi p');
    });

    test('the adapter map API returns exact protocol JSON', () async {
      final adapter = LlmClientAdapter(_PagedClient());
      expect(await adapter.executeTool('t', {}), {
        'content': [
          {'type': 'text', 'text': 'hello'},
        ],
        'structuredContent': {'n': 1},
      });
    });
  });

  group('McpToolResultRenderer', () {
    const renderer = McpToolResultRenderer();

    test('every content kind, structured content, isError', () {
      final r = renderer.render(mcp.CallToolResult.fromJson({
        'isError': true,
        'structuredContent': {'temp': 21},
        'content': [
          {'type': 'text', 'text': 'line'},
          {'type': 'image', 'data': 'AAAA', 'mimeType': 'image/png'},
          {'type': 'audio', 'data': 'AAAAAA==', 'mimeType': 'audio/wav'},
          {'type': 'resource_link', 'uri': 'file:///a.txt', 'name': 'a.txt', 'mimeType': 'text/plain'},
          {'type': 'resource', 'resource': {'uri': 'file:///b.md', 'text': 'body', 'mimeType': 'text/markdown'}},
          {'type': 'resource', 'resource': {'uri': 'file:///c.bin', 'blob': 'AAAA'}},
          {'type': 'future_kind', 'x': 1},
        ],
      }));
      expect(r.isError, isTrue);
      expect(r.text.split('\n'), [
        'line',
        '[image image/png, 3 bytes]',
        '[audio audio/wav, 4 bytes]',
        '[resource link file:///a.txt, name: a.txt, type: text/plain]',
        '[resource file:///b.md (text/markdown)]',
        'body',
        '[binary resource file:///c.bin, 3 bytes]',
        '{"type":"future_kind","x":1}',
        'Structured result: {"temp":21}',
      ]);
      expect(r.media.map((m) => m.type), ['image', 'audio']);
    });
  });

  group('server handler results', () {
    test('LlmCallToolResult and strings become tools/call results', () {
      final r = callToolResultOf(LlmCallToolResult([
        LlmTextContent(text: 'ok'),
        LlmImageContent.fromBase64(base64Data: 'AAAA', mimeType: 'image/png'),
        LlmImageContent(url: 'https://x/y.png', mimeType: 'image/png'),
      ], isError: false));
      expect(r.toJson(), {
        'content': [
          {'type': 'text', 'text': 'ok'},
          {'type': 'image', 'data': 'AAAA', 'mimeType': 'image/png'},
          {'type': 'resource_link', 'uri': 'https://x/y.png', 'name': 'https://x/y.png', 'mimeType': 'image/png'},
        ],
        'isError': false,
      });
      expect(callToolResultOf('plain').toJson(), {'content': [{'type': 'text', 'text': 'plain'}]});
      expect(callToolResultOf({'content': [], 'isStreaming': false}).toJson(), {'content': []});
    });

    test('LlmReadResourceResult becomes protocol resource contents', () {
      final r = readResourceResultOf(
          'doc://1', LlmReadResourceResult(content: 'text body', mimeType: 'text/plain', contents: const []));
      expect(r.toJson(), {
        'contents': [
          {'uri': 'doc://1', 'text': 'text body', 'mimeType': 'text/plain'},
        ],
      });
      expect(r.check(), isEmpty);
    });

    test('prompt messages: system goes to the user role; content kinds kept', () {
      final r = getPromptResultOf(LlmGetPromptResult(description: 'd', messages: [
        LlmMessage(role: 'system', content: 'be brief'),
        LlmMessage(role: 'assistant', content: LlmTextContent(text: 'ok')),
      ]));
      expect(r.toJson(), {
        'description': 'd',
        'messages': [
          {'role': 'user', 'content': {'type': 'text', 'text': 'be brief'}},
          {'role': 'assistant', 'content': {'type': 'text', 'text': 'ok'}},
        ],
      });
      expect(r.check(), isEmpty);
    });
  });

  group('sampling', () {
    test('the request reaches the provider whole', () async {
      final provider = _Provider(LlmResponse(text: 'answer', metadata: {'stop_reason': 'end_turn'}));
      final result = await McpSamplingHandler(provider, model: 'm1').handle({
        'messages': [
          {'role': 'user', 'content': {'type': 'text', 'text': 'first'}},
          {'role': 'assistant', 'content': {'type': 'text', 'text': 'reply'}},
          {'role': 'user', 'content': {'type': 'text', 'text': 'question'}},
        ],
        'maxTokens': 50,
        'temperature': 0.2,
        'systemPrompt': 'sys',
        'stopSequences': ['END'],
        'tools': [
          {'name': 'lookup', 'description': 'd', 'inputSchema': {'type': 'object'}},
        ],
      });
      final seen = provider.seen!;
      expect(seen.prompt, 'question');
      expect(seen.history.map((m) => '${m.role}:${m.content}'), ['user:first', 'assistant:reply']);
      expect(seen.parameters['max_tokens'], 50);
      expect(seen.parameters['temperature'], 0.2);
      expect(seen.parameters['system'], 'sys');
      expect((seen.parameters['tools'] as List).single['name'], 'lookup');
      expect(result, {
        'role': 'assistant',
        'content': {'type': 'text', 'text': 'answer'},
        'model': 'm1',
        'stopReason': 'endTurn',
      });
    });

    test('tool calls come back as tool_use with stopReason toolUse; toolChoice none drops tools', () async {
      final provider = _Provider(LlmResponse(
          text: '', toolCalls: [LlmToolCall(id: 'c1', name: 'lookup', arguments: {'q': 'x'})], metadata: const {}));
      final result = await McpSamplingHandler(provider, model: 'm1').handle({
        'messages': [
          {'role': 'user', 'content': {'type': 'text', 'text': 'q'}},
        ],
        'maxTokens': 10,
        'tools': [
          {'name': 'lookup', 'inputSchema': {'type': 'object'}},
        ],
        'toolChoice': {'mode': 'none'},
      });
      expect(provider.seen!.parameters.containsKey('tools'), isFalse);
      expect(result['stopReason'], 'toolUse');
      expect(result['content'], {'type': 'tool_use', 'id': 'c1', 'name': 'lookup', 'input': {'q': 'x'}});
    });
  });
}
