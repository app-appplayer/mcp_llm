// Per-version compliance unit tests for the mcp_llm 2.0 adapters.
//
// Validates that the new adapter surface delegates correctly to the
// underlying mcp_client / mcp_server. The mock receivers below mirror
// the **real** typed signatures of those packages — accepting an
// adapter call here means the same call will compile and pass dynamic
// dispatch against the production classes. This is intentional: a
// previous version of the mock used `Function`-typed parameters that
// silently swallowed the adapter's old (broken) `Future<dynamic>
// Function(dynamic)` signatures, and we only caught the type-mismatch
// bugs during cross-impl testing. Don't loosen the signatures below
// without first verifying that the real packages accept the same.

import 'package:mcp_llm/mcp_llm.dart';
import 'package:test/test.dart';

// ─────────────────────── Client-side mocks ───────────────────────

/// Mirrors the typed surface of `Client` in `package:mcp_client`. Each
/// signature MUST match the production class so a compatible adapter
/// call here proves binary compatibility.
class _RecordingClient {
  final List<String> calls = [];
  String? negotiatedProtocolVersion = '2025-06-18';

  /// Mirror of `Client.onSamplingRequestMap` (Map sibling — adapter's
  /// preferred path). The `Future<Map<String, dynamic>> Function(...)`
  /// shape is invariant in Dart, so any forwarder with a different
  /// return type would fail this signature check.
  void onSamplingRequestMap(
    Future<Map<String, dynamic>> Function(Map<String, dynamic> params)
        handler,
  ) {
    calls.add('onSamplingRequestMap');
  }

  /// Mirror of `Client.onElicitationRequest`.
  void onElicitationRequest(
    Future<Map<String, dynamic>> Function(Map<String, dynamic> params)
        handler,
  ) {
    calls.add('onElicitationRequest');
  }

  /// Mirror of `Client.onListRootsMap`.
  void onListRootsMap(
    Future<List<Map<String, dynamic>>> Function() handler,
  ) {
    calls.add('onListRootsMap');
  }

  /// Mirror of `Client.addRootMap` — accepts a raw spec map.
  void addRootMap(Map<String, dynamic> root) {
    calls.add('addRootMap');
  }

  /// Mirror of `Client.removeRoot`.
  void removeRoot(String uri) {
    calls.add('removeRoot');
  }

  /// Mirror of `Client.notifyCancelled`.
  void notifyCancelled(String requestId, {String? reason}) {
    calls.add('notifyCancelled');
  }

  /// Mirror of `Client.notifyProgress`.
  void notifyProgress(
    dynamic token,
    double progress, {
    double? total,
    String? message,
  }) {
    calls.add('notifyProgress');
  }

  // The legacy adapter surface is unused by these tests — this stub
  // keeps `_isValidClient` happy.
  Future<List<dynamic>> listTools() async => const [];
}

// ─────────────────────── Server-side mocks ───────────────────────

/// Mirrors the typed surface of `Server` in `package:mcp_server`. Each
/// signature MUST match the production class.
class _RecordingServer {
  final List<String> calls = [];

  Future<Map<String, dynamic>> requestClientSampling(
    String sessionId,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    calls.add('requestClientSampling');
    return {
      'role': 'assistant',
      'content': {'type': 'text', 'text': 'ok'},
      'model': 'm',
    };
  }

  Future<Map<String, dynamic>> requestClientElicitation(
    String sessionId,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    calls.add('requestClientElicitation');
    return {
      'action': 'accept',
      'content': {'name': 'x'},
    };
  }

  Future<List<Map<String, dynamic>>> requestClientRoots(
    String sessionId, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    calls.add('requestClientRoots');
    return const [];
  }

  /// Mirror of `Server.addCompletion` — handler is fully typed.
  void addCompletion({
    required String refType,
    required String refKey,
    required Future<Map<String, dynamic>> Function(
      Map<String, dynamic> ref,
      Map<String, dynamic> argument,
      Map<String, dynamic>? context,
    ) handler,
  }) {
    calls.add('addCompletion');
  }

  /// Mirror of `Server.addTool` (used for both legacy tools and the
  /// structured tool registration). The handler signature deliberately
  /// uses `dynamic` since `ToolHandler` is a typedef in mcp_server we
  /// don't import here, but it's covariant-compatible.
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
    calls.add('addTool');
  }

  /// Mirror of `Server.addPromptMap` — required by the adapter's
  /// `registerPrompt` path. Accepts argument list as raw spec maps.
  Future<void> addPromptMap({
    required String name,
    required String description,
    required List<Map<String, dynamic>> arguments,
    required dynamic handler,
    String? title,
    List<Map<String, dynamic>>? icons,
    Map<String, dynamic>? meta,
  }) async {
    calls.add('addPromptMap');
  }

  /// Mirror of `Server.addResource`.
  Future<void> addResource({
    required String uri,
    required String name,
    required String description,
    required String mimeType,
    required dynamic handler,
  }) async {
    calls.add('addResource');
  }

  void configureProtectedResource({
    required String resource,
    required List<String> authorizationServers,
    List<String>? scopesSupported,
    List<String>? bearerMethodsSupported,
    String? resourceDocumentation,
  }) {
    calls.add('configureProtectedResource');
  }
}

void main() {
  group('LlmClientAdapter — MCP 2.0 surface delegates to underlying client',
      () {
    late _RecordingClient client;
    late LlmClientAdapter adapter;

    setUp(() {
      client = _RecordingClient();
      adapter = LlmClientAdapter(client);
    });

    test('onSamplingRequest routes through onSamplingRequestMap', () {
      adapter.onSamplingRequest((_) async => <String, dynamic>{});
      // Assert the adapter chose the Map sibling — that's the path that
      // works against the real Client. If a future change reverts to the
      // typed `onSamplingRequest`, this test fails.
      expect(client.calls, contains('onSamplingRequestMap'));
      expect(client.calls, isNot(contains('onSamplingRequest')));
    });

    test('bindSamplingToProvider routes through onSamplingRequestMap', () {
      adapter.bindSamplingToProvider(
        (params) async => <String, dynamic>{},
      );
      expect(client.calls, contains('onSamplingRequestMap'));
    });

    test('onElicitationRequest', () {
      adapter.onElicitationRequest(
        (params) async => <String, dynamic>{},
      );
      expect(client.calls, contains('onElicitationRequest'));
    });

    test('onListRoots routes through onListRootsMap', () {
      adapter.onListRoots(() async => const []);
      expect(client.calls, contains('onListRootsMap'));
      expect(client.calls, isNot(contains('onListRoots')));
    });

    test('addRoot routes through addRootMap when given a Map', () {
      adapter.addRoot({'uri': 'file:///x', 'name': 'x'});
      expect(client.calls, contains('addRootMap'));
    });

    test('removeRoot delegates directly', () {
      adapter.removeRoot('file:///x');
      expect(client.calls, contains('removeRoot'));
    });

    test('notifyCancelled / notifyProgress', () {
      adapter.notifyCancelled('req-1', reason: 'user');
      adapter.notifyProgress('tok', 0.5, total: 1.0, message: 'half');
      expect(client.calls, containsAll(['notifyCancelled', 'notifyProgress']));
    });

    test('negotiatedProtocolVersion exposed', () {
      expect(adapter.negotiatedProtocolVersion, equals('2025-06-18'));
    });
  });

  group('LlmServerAdapter — MCP 2.0 surface delegates to underlying server',
      () {
    late _RecordingServer server;
    late LlmServerAdapter adapter;

    setUp(() {
      server = _RecordingServer();
      adapter = LlmServerAdapter(server);
    });

    test('requestSampling outbound', () async {
      final result = await adapter.requestSampling('s1', {'maxTokens': 10});
      expect(server.calls, contains('requestClientSampling'));
      expect(result['role'], equals('assistant'));
    });

    test('requestElicitation outbound', () async {
      final result = await adapter.requestElicitation('s1', {'message': 'q'});
      expect(server.calls, contains('requestClientElicitation'));
      expect(result['action'], equals('accept'));
    });

    test('requestRoots outbound', () async {
      await adapter.requestRoots('s1');
      expect(server.calls, contains('requestClientRoots'));
    });

    test('registerCompletion accepts the spec-typed handler', () async {
      final ok = await adapter.registerCompletion(
        refType: 'prompt',
        refKey: 'greet',
        handler: (ref, argument, context) async => {
          'completion': {
            'values': <String>[],
            'total': 0,
            'hasMore': false,
          },
        },
      );
      expect(ok, isTrue);
      expect(server.calls, contains('addCompletion'));
    });

    test('registerStructuredTool with outputSchema + title + icons', () async {
      final ok = await adapter.registerStructuredTool(
        name: 'get_weather',
        title: 'Weather',
        description: 'Get weather',
        inputSchema: const {'type': 'object'},
        outputSchema: const {'type': 'object'},
        icons: const [
          {'src': 'data:image/png;base64,...', 'mimeType': 'image/png'},
        ],
        meta: const {'category': 'demo'},
        handler: (_) async => null,
      );
      expect(ok, isTrue);
      expect(server.calls, contains('addTool'));
    });

    test('registerPrompt routes through addPromptMap with normalised args',
        () async {
      // Adapter must convert PromptArgument-typed entries (anything with
      // `.toJson()`) and raw maps both into spec-shape `Map<String,
      // dynamic>` for `addPromptMap`. Passing the raw-map form directly
      // exercises the simpler branch.
      final ok = await adapter.registerPrompt(
        name: 'greet',
        description: 'Friendly',
        arguments: const [
          {'name': 'name', 'description': 'Person to greet', 'required': true},
        ],
        handler: (_) async => null,
      );
      expect(ok, isTrue);
      expect(server.calls, contains('addPromptMap'));
    });

    test('configureProtectedResource', () {
      adapter.configureProtectedResource(
        resource: 'https://api.example.com/mcp',
        authorizationServers: const ['https://auth.example.com'],
      );
      expect(server.calls, contains('configureProtectedResource'));
    });
  });
}
