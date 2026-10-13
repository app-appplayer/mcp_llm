/// What an mcp_llm handler returns, as the MCP result the protocol defines
/// (design: docs/MCP-LAYER-DESIGN.md §4). mcp_server serialises a handler's
/// result with `toJson()`, so returning the generated types puts exactly the
/// protocol's shape on the wire.
library;

import 'dart:convert';

import '../chat/message.dart';
import '../core/models.dart';
import '../schema/schema.g.dart' as mcp;

/// One mcp_llm content value as an MCP content block.
mcp.ContentBlock contentBlockOf(LLmContent content) => switch (content) {
      LlmTextContent() => mcp.TextContent(text: content.text),
      LlmImageContent(base64Data: final data?) => mcp.ImageContent(data: data, mimeType: content.mimeType),
      // An image known only by its address is a link to it.
      LlmImageContent() => mcp.ResourceLink(uri: content.url, name: content.url, mimeType: content.mimeType),
      LlmResourceContent(blob: final blob?) =>
        mcp.EmbeddedResource(resource: mcp.BlobResourceContents(uri: content.uri, blob: blob)),
      LlmResourceContent() =>
        mcp.EmbeddedResource(resource: mcp.TextResourceContents(uri: content.uri, text: content.text ?? '')),
      _ => mcp.TextContent(text: '$content'),
    };

/// A tool handler's return value as a `tools/call` result.
mcp.CallToolResult callToolResultOf(Object? value) {
  if (value is mcp.CallToolResult) return value;
  if (value is LlmCallToolResult) {
    return mcp.CallToolResult(
      content: [for (final c in value.content) contentBlockOf(c)],
      isError: value.isError,
    );
  }
  if (value is String) return mcp.CallToolResult(content: [mcp.TextContent(text: value)]);
  final json = _jsonOf(value);
  if (json != null && json['content'] is List) {
    return mcp.CallToolResult.fromJson({...json}..remove('isStreaming'));
  }
  // Any other value is the tool's output, carried as JSON text.
  return mcp.CallToolResult(content: [mcp.TextContent(text: json != null ? jsonEncode(json) : jsonEncode(value))]);
}

/// A resource handler's return value as a `resources/read` result for [uri].
/// A plain string carries [mimeType] — the type the resource was registered
/// with.
mcp.ReadResourceResult readResourceResultOf(String uri, Object? value, {String? mimeType}) {
  if (value is mcp.ReadResourceResult) return value;
  if (value is LlmReadResourceResult) {
    final contents = <mcp.ResourceContents>[
      for (final c in value.contents)
        switch (c) {
          LlmImageContent(base64Data: final data?) => mcp.BlobResourceContents(uri: uri, blob: data, mimeType: c.mimeType),
          LlmResourceContent(blob: final blob?) => mcp.BlobResourceContents(uri: c.uri, blob: blob),
          LlmResourceContent() => mcp.TextResourceContents(uri: c.uri, text: c.text ?? ''),
          _ => mcp.TextResourceContents(uri: uri, text: '$c', mimeType: value.mimeType),
        },
    ];
    return mcp.ReadResourceResult(
      contents: contents.isNotEmpty
          ? contents
          : [mcp.TextResourceContents(uri: uri, text: value.content, mimeType: value.mimeType)],
    );
  }
  if (value is String) {
    return mcp.ReadResourceResult(contents: [mcp.TextResourceContents(uri: uri, text: value, mimeType: mimeType)]);
  }
  final json = _jsonOf(value);
  if (json != null && json['contents'] is List) return mcp.ReadResourceResult.fromJson(json);
  return mcp.ReadResourceResult(contents: [
    mcp.TextResourceContents(uri: uri, text: jsonEncode(json ?? value), mimeType: 'application/json'),
  ]);
}

/// A prompt handler's return value as a `prompts/get` result. Prompt
/// messages have only `user` and `assistant` roles; a system message is
/// given to the user role, its text unchanged.
mcp.GetPromptResult getPromptResultOf(Object? value) {
  if (value is mcp.GetPromptResult) return value;
  if (value is LlmGetPromptResult) {
    return mcp.GetPromptResult(
      description: value.description.isEmpty ? null : value.description,
      messages: [for (final m in value.messages) _promptMessage(m)],
    );
  }
  final json = _jsonOf(value);
  if (json != null && json['messages'] is List) return mcp.GetPromptResult.fromJson(json);
  if (value is String) {
    return mcp.GetPromptResult(messages: [mcp.PromptMessage(role: mcp.Role.user, content: mcp.TextContent(text: value))]);
  }
  throw ArgumentError.value(value, 'value', 'is not a prompt result');
}

mcp.PromptMessage _promptMessage(LlmMessage m) {
  final role = m.role == 'assistant' ? mcp.Role.assistant : mcp.Role.user;
  final content = m.content;
  final block = switch (content) {
    LLmContent() => contentBlockOf(content),
    String() => mcp.TextContent(text: content),
    Map() when content['type'] is String => mcp.ContentBlock.fromJson(Map<String, Object?>.from(content)),
    _ => mcp.TextContent(text: content is Map || content is List ? jsonEncode(content) : '$content'),
  };
  return mcp.PromptMessage(role: role, content: block);
}

Map<String, Object?>? _jsonOf(Object? value) {
  if (value is Map) return Map<String, Object?>.from(value);
  if (value == null || value is String || value is num || value is bool || value is List) return null;
  try {
    final json = (value as dynamic).toJson();
    return json is Map ? Map<String, Object?>.from(json) : null;
  } on NoSuchMethodError {
    return null;
  }
}
