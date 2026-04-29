// Per-version compliance smoke for mcp_llm 2.0 adapters.
//
// Validates that the new adapter surface delegates correctly to the
// underlying mcp_client / mcp_server (using a tiny mock to avoid
// pulling those packages into the test target).

import 'package:mcp_llm/mcp_llm.dart';
import 'package:test/test.dart';

/// Tiny mock that records the names of methods the adapter calls.
class _RecordingClient {
  final List<String> calls = [];
  String? negotiatedProtocolVersion = '2025-06-18';

  void onSamplingRequest(Function handler) => calls.add('onSamplingRequest');
  void onElicitationRequest(Function handler) =>
      calls.add('onElicitationRequest');
  void onListRoots(Function handler) => calls.add('onListRoots');
  void addRoot(dynamic root) => calls.add('addRoot');
  void removeRoot(String uri) => calls.add('removeRoot');
  void notifyCancelled(String requestId, {String? reason}) =>
      calls.add('notifyCancelled');
  void notifyProgress(dynamic token, double progress,
          {double? total, String? message}) =>
      calls.add('notifyProgress');

  // The legacy adapter surface is unused here — these stubs just keep
  // the constructor's `_isValidClient` happy.
  Future<List<dynamic>> listTools() async => const [];
}

class _RecordingServer {
  final List<String> calls = [];

  Future<Map<String, dynamic>> requestClientSampling(
    String sessionId,
    Map<String, dynamic> params, {
    Duration? timeout,
  }) async {
    calls.add('requestClientSampling');
    return {'role': 'assistant', 'content': {'type': 'text', 'text': 'ok'}, 'model': 'm'};
  }

  Future<Map<String, dynamic>> requestClientElicitation(
    String sessionId,
    Map<String, dynamic> params, {
    Duration? timeout,
  }) async {
    calls.add('requestClientElicitation');
    return {'action': 'accept', 'content': {'name': 'x'}};
  }

  Future<List<dynamic>> requestClientRoots(
    String sessionId, {
    Duration? timeout,
  }) async {
    calls.add('requestClientRoots');
    return const [];
  }

  void addCompletion({
    required String refType,
    required String refKey,
    required Function handler,
  }) {
    calls.add('addCompletion');
  }

  Future<void> addTool({
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema,
    Function? handler,
    Map<String, dynamic>? outputSchema,
    String? title,
    List<Map<String, dynamic>>? icons,
    Map<String, dynamic>? meta,
  }) async {
    calls.add('addTool');
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

    test('onSamplingRequest', () {
      adapter.onSamplingRequest((_) async => {});
      expect(client.calls, contains('onSamplingRequest'));
    });

    test('bindSamplingToProvider wraps onSamplingRequest', () {
      adapter.bindSamplingToProvider((_) async => {});
      expect(client.calls, contains('onSamplingRequest'));
    });

    test('onElicitationRequest', () {
      adapter.onElicitationRequest((_) async => {});
      expect(client.calls, contains('onElicitationRequest'));
    });

    test('onListRoots', () {
      adapter.onListRoots(() async => const []);
      expect(client.calls, contains('onListRoots'));
    });

    test('addRoot / removeRoot', () {
      adapter.addRoot(const _Stub());
      adapter.removeRoot('file:///x');
      expect(client.calls, containsAll(['addRoot', 'removeRoot']));
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

    test('registerCompletion', () async {
      final ok = await adapter.registerCompletion(
        refType: 'prompt',
        refKey: 'greet',
        handler: (_, __, ___) async => {'completion': {'values': []}},
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

    test('configureProtectedResource', () {
      adapter.configureProtectedResource(
        resource: 'https://api.example.com/mcp',
        authorizationServers: const ['https://auth.example.com'],
      );
      expect(server.calls, contains('configureProtectedResource'));
    });
  });
}

class _Stub {
  const _Stub();
  Map<String, dynamic> toJson() => {'uri': 'file:///x'};
}
