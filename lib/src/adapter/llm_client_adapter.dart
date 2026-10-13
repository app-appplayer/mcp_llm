import '../utils/logger.dart';
import '../core/llm_interface.dart';
import 'mcp_client_bridge.dart';
import 'mcp_sampling.dart';

/// An MCP client as mcp_llm uses it. Listing and calls go through
/// [McpClientBridge] (typed, every page, failures as [McpLayerException]);
/// the map methods return the protocol JSON of those results.
///
/// Authorization is the client's own (mcp_client's `McpOAuth` on its
/// transport); this adapter holds no credentials.
class LlmClientAdapter {
  final dynamic _mcpClient;
  final McpClientBridge bridge;
  final Logger _logger = Logger('mcp_llm.client_adapter');

  LlmClientAdapter(this._mcpClient) : bridge = McpClientBridge(_mcpClient);

  /// Every tool, as protocol JSON.
  Future<List<Map<String, dynamic>>> getTools() async =>
      [for (final t in await bridge.listTools()) t.toJson()];

  /// Every prompt, as protocol JSON.
  Future<List<Map<String, dynamic>>> getPrompts() async =>
      [for (final p in await bridge.listPrompts()) p.toJson()];

  /// Every resource, as protocol JSON.
  Future<List<Map<String, dynamic>>> getResources() async =>
      [for (final r in await bridge.listResources()) r.toJson()];

  /// Every resource template, as protocol JSON.
  Future<List<Map<String, dynamic>>> getResourceTemplates() async =>
      [for (final r in await bridge.listResourceTemplates()) r.toJson()];

  /// `prompts/get`, as protocol JSON.
  Future<Map<String, dynamic>> executePrompt(String promptName, Map<String, dynamic> args) async =>
      (await bridge.getPrompt(promptName, args)).toJson();

  /// `resources/read`, as protocol JSON.
  Future<Map<String, dynamic>> readResource(String resourceUri) async =>
      (await bridge.readResource(resourceUri)).toJson();

  /// `tools/call`, as protocol JSON (`isError: true` when the tool failed).
  Future<Map<String, dynamic>> executeTool(String toolName, Map<String, dynamic> args) async =>
      (await bridge.callTool(toolName, args)).toJson();

  // === MCP 2.0 surface — server-initiated request handlers ===
  //
  // These thin wrappers surface the spec-correct callbacks on the
  // underlying mcp_client. They use `dynamic` dispatch so this adapter
  // stays compatible with any client implementation that exposes the
  // expected method names (in particular `mcp_client` 2.0+).

  /// Register a handler for server-initiated `sampling/createMessage`
  /// (spec). The handler receives the raw params and must return the
  /// JSON-serialisable result map (`role`, `content`, `model`, optional
  /// `stopReason`).
  ///
  /// The client answers only when it declared `sampling` in its
  /// capabilities (mcp_client: `ClientCapabilities(sampling: true)`);
  /// registering a handler does not declare it.
  void onSamplingRequest(Future<dynamic> Function(dynamic request) handler) {
    // mcp_client's typed `onSamplingRequest` expects
    // `Future<CreateMessageResult> Function(CreateMessageRequest)` —
    // forwarding our `Future<dynamic> Function(dynamic)` would fail the
    // runtime function-subtype check on the return. Use the Map sibling
    // so the registered handler stays Map-typed and the typed wrapper is
    // bypassed entirely.
    Future<Map<String, dynamic>> wrapped(Map<String, dynamic> params) async {
      final raw = await handler(params);
      if (raw is Map<String, dynamic>) return raw;
      return Map<String, dynamic>.from(raw as Map);
    }
    try {
      _mcpClient.onSamplingRequestMap(wrapped);
    } catch (_) {
      try {
        _mcpClient.onSamplingRequest(handler);
      } catch (e) {
        _logger.warning(
            'Underlying client does not support onSamplingRequest: $e');
      }
    }
  }

  /// Bind incoming sampling requests to an [LlmProvider] so the host's
  /// LLM fulfils them. Translates spec `CreateMessageRequest.params` to
  /// `LlmRequest` and back. Falls back to raw [onSamplingRequest] if the
  /// signature differs.
  ///
  /// Use [overrideSystemPrompt] to replace the request's `systemPrompt`
  /// (e.g., to gate which prompts your LLM accepts).
  void bindSamplingToProvider(
    Future<Map<String, dynamic>> Function(Map<String, dynamic> params) llmCall,
  ) {
    onSamplingRequest((req) async {
      // Spec request comes as either a typed object (mcp_client) or a
      // raw params map. Normalise to a Map.
      Map<String, dynamic> params;
      try {
        params = (req is Map)
            ? Map<String, dynamic>.from(req)
            : Map<String, dynamic>.from(req.toJson() as Map);
      } catch (_) {
        params = const {};
      }
      return await llmCall(params);
    });
  }

  /// Answer server-initiated `sampling/createMessage` with [provider]:
  /// every message, the system prompt, limits and tools reach it, and its
  /// answer (text, tool calls, stop reason) comes back as the result.
  void bindSamplingToLlm(LlmProvider provider, {required String model}) =>
      onSamplingRequest((req) => McpSamplingHandler(provider, model: model)
          .handle(req is Map ? Map<String, dynamic>.from(req) : Map<String, dynamic>.from(req.toJson() as Map)));

  /// Register a handler for server-initiated `elicitation/create`
  /// (spec 2025-06-18+). The host must show the requested form and
  /// return `{ action, content? }` per spec. The client answers only when it
  /// declared `elicitation` in its capabilities.
  void onElicitationRequest(
      Future<Map<String, dynamic>> Function(Map<String, dynamic> params)
          handler) {
    try {
      _mcpClient.onElicitationRequest(handler);
    } catch (e) {
      _logger.warning('Underlying client does not support onElicitationRequest: $e');
    }
  }

  /// Register a handler for server-initiated `roots/list`. Default
  /// behaviour returns the locally registered [addRoot] entries; supply
  /// this to override. The client answers only when it declared `roots` in
  /// its capabilities.
  void onListRoots(Future<List<dynamic>> Function() handler) {
    // mcp_client's typed `onListRoots` expects `Future<List<Root>>` —
    // route through the Map sibling so we don't have to import Root.
    Future<List<Map<String, dynamic>>> wrapped() async {
      final list = await handler();
      return list
          .map<Map<String, dynamic>>((r) => r is Map<String, dynamic>
              ? r
              : Map<String, dynamic>.from(r as Map))
          .toList();
    }
    try {
      _mcpClient.onListRootsMap(wrapped);
    } catch (_) {
      try {
        _mcpClient.onListRoots(handler);
      } catch (e) {
        _logger.warning('Underlying client does not support onListRoots: $e');
      }
    }
  }

  /// Add a root to the client's local list. Triggers
  /// `notifications/roots/list_changed` to the server. Accepts either a
  /// raw map (`{'uri': ..., 'name': ...}`) or a typed `Root` instance.
  void addRoot(dynamic root) {
    try {
      if (root is Map) {
        _mcpClient.addRootMap(Map<String, dynamic>.from(root));
      } else {
        _mcpClient.addRoot(root);
      }
    } catch (e) {
      _logger.warning('Underlying client does not support addRoot: $e');
    }
  }

  /// Remove a root from the client's local list.
  void removeRoot(String uri) {
    try {
      _mcpClient.removeRoot(uri);
    } catch (e) {
      _logger.warning('Underlying client does not support removeRoot: $e');
    }
  }

  /// Cancel a request this client has in flight (spec
  /// `notifications/cancelled`; on 2026-07-28 HTTP, closing its stream).
  /// [requestId] is the JSON-RPC id — a string or a number. A request that
  /// is not in flight is the caller's mistake and is reported as such.
  void notifyCancelled(Object requestId, {String? reason}) {
    try {
      _mcpClient.notifyCancelled(requestId, reason: reason);
    } on NoSuchMethodError catch (e) {
      _logger.warning('Underlying client does not support notifyCancelled: $e');
    }
  }

  /// Report progress on an in-flight server-initiated request
  /// (spec `notifications/progress`).
  void notifyProgress(
    dynamic progressToken,
    double progress, {
    double? total,
    String? message,
  }) {
    try {
      _mcpClient.notifyProgress(progressToken, progress,
          total: total, message: message);
    } catch (e) {
      _logger.warning('Underlying client does not support notifyProgress: $e');
    }
  }

  /// The negotiated MCP protocol revision after initialize completes.
  /// Returns `null` before then or when the underlying client doesn't
  /// expose the field.
  String? get negotiatedProtocolVersion => bridge.protocolVersion;
}

