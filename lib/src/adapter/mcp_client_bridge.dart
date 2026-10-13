/// Typed MCP operations over a client held as `dynamic` (design:
/// docs/MCP-LAYER-DESIGN.md §3.1).
///
/// mcp_llm does not depend on mcp_client. It takes a client as `dynamic`
/// and crosses the boundary through JSON: the client's values are turned
/// into the generated MCP types that mcp_llm carries (`lib/src/schema/`),
/// which are the same shapes mcp_client and mcp_server use. Nothing is made
/// up on the way: a failure is an [McpLayerException], never a stand-in
/// result.
library;

import 'dart:async';

import '../schema/schema.g.dart' as mcp;
import '../utils/logger.dart';

/// A failed MCP operation: which method, and what the server or client said.
class McpLayerException implements Exception {
  McpLayerException(this.method, this.message, {this.code, this.data});

  /// The MCP method (`tools/call`, `resources/read`, …).
  final String method;
  final String message;

  /// The JSON-RPC error code, when the failure carried one.
  final int? code;

  /// The JSON-RPC error data, when the failure carried one.
  final Object? data;

  @override
  String toString() => 'McpLayerException($method${code == null ? '' : ', $code'}): $message';
}

/// Typed operations on one MCP client.
class McpClientBridge {
  McpClientBridge(this.client);

  /// The client, as given (mcp_client's `Client`, or anything with the same
  /// method names).
  final dynamic client;

  final Logger _logger = Logger('mcp_llm.client_bridge');

  /// Every tool, following `nextCursor` across pages.
  Future<List<mcp.Tool>> listTools() => _allPages(
        'tools/list',
        (cursor) => client.listToolsPage(cursor: cursor),
        () => client.listTools(),
        'tools',
        mcp.Tool.fromJson,
      );

  /// Every prompt, following `nextCursor` across pages.
  Future<List<mcp.Prompt>> listPrompts() => _allPages(
        'prompts/list',
        (cursor) => client.listPromptsPage(cursor: cursor),
        () => client.listPrompts(),
        'prompts',
        mcp.Prompt.fromJson,
      );

  /// Every resource, following `nextCursor` across pages.
  Future<List<mcp.Resource>> listResources() => _allPages(
        'resources/list',
        (cursor) => client.listResourcesPage(cursor: cursor),
        () => client.listResources(),
        'resources',
        mcp.Resource.fromJson,
      );

  /// Every resource template, following `nextCursor` across pages.
  Future<List<mcp.ResourceTemplate>> listResourceTemplates() => _allPages(
        'resources/templates/list',
        (cursor) => client.listResourceTemplatesPage(cursor: cursor),
        () => client.listResourceTemplates(),
        'resourceTemplates',
        mcp.ResourceTemplate.fromJson,
      );

  /// `tools/call`. A tool that failed answers with `isError: true` in the
  /// result; a protocol failure is an [McpLayerException].
  Future<mcp.CallToolResult> callTool(String name, Map<String, dynamic> arguments, {Map<String, dynamic>? meta}) =>
      _call('tools/call', () => meta == null ? client.callTool(name, arguments) : client.callTool(name, arguments, meta: meta),
          mcp.CallToolResult.fromJson);

  /// `prompts/get`.
  Future<mcp.GetPromptResult> getPrompt(String name, Map<String, dynamic> arguments, {Map<String, dynamic>? meta}) =>
      _call(
          'prompts/get',
          // mcp_client takes the prompt's meta positionally.
          () => meta == null ? client.getPrompt(name, arguments) : client.getPrompt(name, arguments, meta),
          mcp.GetPromptResult.fromJson);

  /// `resources/read`.
  Future<mcp.ReadResourceResult> readResource(String uri, {Map<String, dynamic>? meta}) =>
      _call('resources/read', () => meta == null ? client.readResource(uri) : client.readResource(uri, meta: meta),
          mcp.ReadResourceResult.fromJson);

  /// `completion/complete`: suggestions for [argument] (`name`, `value`) of
  /// the prompt or resource template [ref].
  Future<mcp.CompleteResult> complete(
    Map<String, dynamic> ref,
    Map<String, dynamic> argument, {
    Map<String, dynamic>? context,
  }) =>
      _call('completion/complete', () => client.complete(ref, argument, context: context),
          mcp.CompleteResult.fromJson);

  /// The negotiated protocol revision, when the client reports one.
  String? get protocolVersion {
    try {
      return client.negotiatedProtocolVersion as String?;
    } on NoSuchMethodError {
      return null;
    }
  }

  Future<T> _call<T>(String method, Future<dynamic> Function() send, T Function(Map<String, Object?>) read) async {
    final Object? value;
    try {
      value = await send();
    } on NoSuchMethodError {
      throw McpLayerException(method, 'the client has no method for $method');
    } catch (e) {
      throw _failure(method, e);
    }
    return read(_json(method, value));
  }

  Future<List<T>> _allPages<T>(
    String method,
    Future<dynamic> Function(String? cursor) page,
    Future<dynamic> Function() whole,
    String key,
    T Function(Map<String, Object?>) read,
  ) async {
    final items = <T>[];
    final seen = <String>{};
    String? cursor;
    var paged = true;
    do {
      final Object? value;
      try {
        value = paged ? await page(cursor) : await whole();
      } on NoSuchMethodError {
        if (!paged) throw McpLayerException(method, 'the client has no method for $method');
        // A client without paged listing: one call returns what it has.
        paged = false;
        continue;
      } catch (e) {
        throw _failure(method, e);
      }
      if (!paged) {
        if (value is! List) throw McpLayerException(method, 'the client returned ${value.runtimeType}, not a list');
        return [for (final item in value) read(_json(method, item))];
      }
      final result = _json(method, value);
      final list = result[key];
      if (list is! List) throw McpLayerException(method, 'the result has no "$key" list');
      for (final item in list) {
        items.add(read(_json(method, item)));
      }
      final next = result['nextCursor'];
      cursor = next is String && next.isNotEmpty ? next : null;
      if (cursor != null && !seen.add(cursor)) {
        _logger.warning('$method: the server repeated cursor $cursor; stopping');
        cursor = null;
      }
    } while (!paged || cursor != null);
    return items;
  }

  /// [value] as protocol JSON: a map, or an object with `toJson()`.
  static Map<String, Object?> _json(String method, Object? value) {
    if (value is Map) return Map<String, Object?>.from(value);
    try {
      final json = (value as dynamic).toJson();
      if (json is Map) return Map<String, Object?>.from(json);
    } on NoSuchMethodError {
      // Falls through to the error below.
    }
    throw McpLayerException(method, 'the client returned ${value.runtimeType}, which has no JSON form');
  }

  /// The client's error as an [McpLayerException], keeping its JSON-RPC
  /// code and data when it has them (mcp_client's `McpError` does).
  static McpLayerException _failure(String method, Object error) {
    if (error is McpLayerException) return error;
    int? code;
    Object? data;
    String message = '$error';
    try {
      final e = error as dynamic;
      code = e.code as int?;
      data = e.data;
      message = e.message as String;
    } on NoSuchMethodError {
      // Not an McpError-shaped value; the description stands.
    } on TypeError {
      // Same.
    }
    return McpLayerException(method, message, code: code, data: data);
  }
}
