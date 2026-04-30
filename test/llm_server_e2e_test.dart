// LlmServer / McpServerManager / LlmServerExtensions end-to-end smoke
// (D-7 / D-8 / D-9 of the release-grade test cycle).
//
// Builds a deterministic in-process LLM provider stub plus a real
// `mcp_server.Server` instance, wires both through `LlmServer`, and
// exercises:
//   - askLlm (delegates to provider.complete)
//   - registerLocalTool / executeLocalTool
//   - addMcpServer / removeMcpServer / getMcpServerIds
//   - getAllServerTools (multi-server aggregation)
//   - executeToolOnAllServers
//   - findServersWithTool
//   - getServerInfo (LlmServerHelperExtensions)
//   - isToolAvailable / isPromptAvailable
//
// Until now these classes were 0% covered; cross-impl tests don't
// reach them because they sit above the protocol layer. This file
// exercises the public API surface end-to-end without spinning up an
// LLM provider or transport.

import 'dart:async';

import 'package:mcp_llm/mcp_llm.dart' as llm;
import 'package:test/test.dart';

/// Deterministic LLM provider stub. Returns a canned text response
/// echoing the prompt; lets us assert that LlmServer's prompt routing
/// reaches the provider without a real API.
class _StubLlm implements llm.LlmProvider {
  final List<llm.LlmRequest> calls = [];

  @override
  Future<void> initialize(llm.LlmConfiguration config) async {}

  @override
  Future<void> close() async {}

  @override
  Future<llm.LlmResponse> complete(llm.LlmRequest request) async {
    calls.add(request);
    return llm.LlmResponse(
      text: 'echo: ${request.prompt}',
      metadata: const {'model': 'stub-1'},
    );
  }

  @override
  Stream<llm.LlmResponseChunk> streamComplete(llm.LlmRequest request) async* {
    calls.add(request);
    yield llm.LlmResponseChunk(
      textChunk: 'echo: ${request.prompt}',
      isDone: true,
    );
  }

  @override
  Future<List<double>> getEmbeddings(String text) async => List.filled(8, 0.0);

  @override
  bool hasToolCallMetadata(Map<String, dynamic> metadata) => false;

  @override
  llm.LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) =>
      null;

  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) =>
      Map.from(metadata);
}

/// Mock MCP server that mirrors the surface `LlmServerAdapter` calls
/// into. Mirrors mcp_server.Server's typed signatures so dynamic
/// dispatch from the adapter accepts these.
class _MockMcpServer {
  final List<String> events = [];
  final Map<String, Function> _tools = {};

  Future<void> addTool({
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema,
    required dynamic handler,
    Map<String, dynamic>? outputSchema,
    String? title,
    List<Map<String, dynamic>>? icons,
    Map<String, dynamic>? meta,
  }) async {
    _tools[name] = handler as Function;
    events.add('addTool:$name');
  }

  Future<void> addPromptMap({
    required String name,
    required String description,
    required List<Map<String, dynamic>> arguments,
    required dynamic handler,
    String? title,
    List<Map<String, dynamic>>? icons,
    Map<String, dynamic>? meta,
  }) async {
    events.add('addPromptMap:$name');
  }

  Future<void> addResource({
    required String uri,
    required String name,
    required String description,
    required String mimeType,
    required dynamic handler,
  }) async {
    events.add('addResource:$uri');
  }

  Future<List<Map<String, dynamic>>> getTools() async {
    return _tools.keys
        .map((n) => <String, dynamic>{
              'name': n,
              'description': 'mock $n',
              'inputSchema': const {'type': 'object'},
            })
        .toList();
  }

  Future<dynamic> executeTool({
    required String name,
    required Map<String, dynamic> args,
  }) async {
    events.add('executeTool:$name');
    final h = _tools[name];
    if (h == null) {
      throw StateError('tool $name not registered');
    }
    return await h(args);
  }
}

void main() {
  group('LlmServer end-to-end (D-7)', () {
    late _StubLlm stub;
    late llm.LlmServer server;

    setUp(() {
      stub = _StubLlm();
      server = llm.LlmServer(
        llmProvider: stub,
        pluginManager: llm.PluginManager(),
      );
    });

    tearDown(() async {
      await server.close();
    });

    test('askLlm routes the prompt to the provider', () async {
      final response = await server.askLlm('hello world');
      expect(response.text, equals('echo: hello world'));
      expect(stub.calls, hasLength(1));
      expect(stub.calls.first.prompt, equals('hello world'));
    });

    test('registerLocalTool / executeLocalTool roundtrip', () async {
      final ok = await server.registerLocalTool(
        name: 'add',
        description: 'add two numbers',
        inputSchema: const {'type': 'object'},
        handler: (args) async => (args['a'] as int) + (args['b'] as int),
      );
      expect(ok, isTrue);
      expect(server.localTools.containsKey('add'), isTrue);
      final result = await server.executeLocalTool('add', {'a': 2, 'b': 3});
      expect(result, equals(5));
    });

    test('hasMcpServer reflects whether a backing server is wired', () {
      // The default constructor wires no MCP server.
      expect(server.hasMcpServer, isFalse);

      // Mounting one through the manager makes it visible.
      final mock = _MockMcpServer();
      server.addMcpServer('s1', mock);
      expect(server.hasMcpServer, isTrue);
      expect(server.getMcpServerIds(), contains('s1'));

      server.removeMcpServer('s1');
      expect(server.hasMcpServer, isFalse);
    });
  });

  group('McpServerManager (D-8)', () {
    late _MockMcpServer s1;
    late _MockMcpServer s2;
    late llm.McpServerManager manager;

    setUp(() {
      s1 = _MockMcpServer();
      s2 = _MockMcpServer();
      manager = llm.McpServerManager();
      manager.addServer('s1', s1);
      manager.addServer('s2', s2);
    });

    test('addServer / removeServer / serverCount', () {
      expect(manager.serverCount, equals(2));
      expect(manager.serverIds, containsAll(['s1', 's2']));

      manager.removeServer('s1');
      expect(manager.serverCount, equals(1));
      expect(manager.serverIds, equals(['s2']));
    });

    test('per-server tool registration + getTools per server', () async {
      await manager.registerTool(
        serverId: 's1',
        name: 'only_on_s1',
        description: 'unique to s1',
        inputSchema: const {'type': 'object'},
        handler: (_) async => 's1-result',
      );
      await manager.registerTool(
        serverId: 's2',
        name: 'only_on_s2',
        description: 'unique to s2',
        inputSchema: const {'type': 'object'},
        handler: (_) async => 's2-result',
      );

      final s1Tools = await manager.getTools('s1');
      final s2Tools = await manager.getTools('s2');
      expect(s1Tools.map((t) => t['name']), contains('only_on_s1'));
      expect(s1Tools.map((t) => t['name']), isNot(contains('only_on_s2')));
      expect(s2Tools.map((t) => t['name']), contains('only_on_s2'));
    });

    test('findServersWithTool resolves to the owning server only', () async {
      await manager.registerTool(
        serverId: 's1',
        name: 'shared_name',
        description: 'lives on s1 only',
        inputSchema: const {'type': 'object'},
        handler: (_) async => 'from-s1',
      );

      final owners = await manager.findServersWithTool('shared_name');
      expect(owners, equals(['s1']));

      final missing = await manager.findServersWithTool('nonexistent_tool');
      expect(missing, isEmpty);
    });

    test('executeToolOnAllServers fans out across registered servers',
        () async {
      // Register the same tool on both servers; manager should call both.
      await manager.registerTool(
        serverId: 's1',
        name: 'fanout',
        description: 'fanout from s1',
        inputSchema: const {'type': 'object'},
        handler: (_) async => 'r1',
      );
      await manager.registerTool(
        serverId: 's2',
        name: 'fanout',
        description: 'fanout from s2',
        inputSchema: const {'type': 'object'},
        handler: (_) async => 'r2',
      );

      final out = await manager.executeToolOnAllServers('fanout', {});
      expect(out.keys, containsAll(['s1', 's2']));
      expect(out['s1'], equals('r1'));
      expect(out['s2'], equals('r2'));
    });
  });

  group('LlmServerExtensions (D-9)', () {
    late _StubLlm stub;
    late _MockMcpServer mockServer;
    late llm.LlmServer server;

    setUp(() async {
      stub = _StubLlm();
      mockServer = _MockMcpServer();
      server = llm.LlmServer(
        llmProvider: stub,
        mcpServer: mockServer,
        pluginManager: llm.PluginManager(),
      );
      // Register a server-side tool so isToolAvailable can find it.
      await server.serverAdapter!.registerTool(
        name: 'remote_echo',
        description: 'remote echo on the mock MCP server',
        inputSchema: const {'type': 'object'},
        handler: (args) async => 'remote: ${args['msg']}',
      );
    });

    tearDown(() async => server.close());

    test('getServerInfo aggregates local + plugin + server stats', () async {
      final info = await server.getServerInfo();
      expect(info['hasServer'], isTrue);
      expect(info['hasRetrieval'], isFalse);
      expect(info['localToolCount'], equals(0));
      expect(info['serverIds'], isA<List>());
    });

    test('isToolAvailable resolves local + plugin + server tools',
        () async {
      // Local tool
      await server.registerLocalTool(
        name: 'local_only',
        description: 'local',
        inputSchema: const {'type': 'object'},
        handler: (_) async => 'ok',
      );

      expect(await server.isToolAvailable('local_only'), isTrue);
      expect(await server.isToolAvailable('remote_echo'), isTrue,
          reason: 'should resolve via the MCP server');
      expect(await server.isToolAvailable('does_not_exist'), isFalse);
    });

    test('isPromptAvailable returns false when nothing registered',
        () async {
      expect(await server.isPromptAvailable('greet'), isFalse);
    });
  });
}
