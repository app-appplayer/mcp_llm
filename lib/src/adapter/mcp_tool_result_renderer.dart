/// MCP tool results as an LLM reads them (design: docs/MCP-LAYER-DESIGN.md
/// §3.3): every content kind rendered, `structuredContent` passed as JSON,
/// `isError` kept as a tool error.
library;

import 'dart:convert';

import '../schema/schema.g.dart' as mcp;

/// A tool result ready for the model.
class RenderedToolResult {
  const RenderedToolResult({required this.text, required this.isError, this.media = const []});

  /// Every content block, in order, as text the model reads.
  final String text;

  /// The tool reported a failure (`isError: true`): the model sees the
  /// content as the error, so it can correct itself.
  final bool isError;

  /// Images and audio carried by the result, for providers that accept
  /// them alongside a tool result. [text] names each one either way.
  final List<({String type, String mimeType, String data})> media;
}

/// Renders tool results and resource reads for the model.
class McpToolResultRenderer {
  const McpToolResultRenderer();

  /// [result] as the model reads it.
  RenderedToolResult render(mcp.CallToolResult result) {
    final lines = <String>[];
    final media = <({String type, String mimeType, String data})>[];
    for (final block in result.content) {
      lines.add(renderBlock(block));
      switch (block) {
        case mcp.ImageContent():
          media.add((type: 'image', mimeType: block.mimeType, data: block.data));
        case mcp.AudioContent():
          media.add((type: 'audio', mimeType: block.mimeType, data: block.data));
        default:
          break;
      }
    }
    final structured = result.structuredContent;
    if (structured != null) lines.add('Structured result: ${jsonEncode(structured)}');
    return RenderedToolResult(text: lines.join('\n'), isError: result.isError ?? false, media: media);
  }

  /// One content block as text.
  String renderBlock(mcp.ContentBlock block) => switch (block) {
        mcp.TextContent() => block.text,
        mcp.ImageContent() => '[image ${block.mimeType}, ${_size(block.data)}]',
        mcp.AudioContent() => '[audio ${block.mimeType}, ${_size(block.data)}]',
        mcp.ResourceLink() => '[${[
            'resource link ${block.uri}',
            if (block.title != null) 'title: ${block.title}',
            'name: ${block.name}',
            if (block.mimeType != null) 'type: ${block.mimeType}',
            if (block.description != null) 'description: ${block.description}',
          ].join(', ')}]',
        mcp.EmbeddedResource() => renderContents(block.resource),
        _ => jsonEncode(block.toJson()),
      };

  /// The contents of a resource (embedded or read) as text: text inline,
  /// binary named by URI and type.
  String renderContents(mcp.ResourceContents contents) => switch (contents) {
        mcp.TextResourceContents() => '[resource ${contents.uri}${contents.mimeType == null ? '' : ' (${contents.mimeType})'}]\n${contents.text}',
        mcp.BlobResourceContents() =>
          '[binary resource ${contents.uri}${contents.mimeType == null ? '' : ' (${contents.mimeType})'}, ${_size(contents.blob)}]',
        _ => jsonEncode(contents.toJson()),
      };

  /// A `resources/read` result as text.
  String renderRead(mcp.ReadResourceResult result) => result.contents.map(renderContents).join('\n');

  /// The decoded size of base64 [data].
  static String _size(String data) {
    final padding = data.endsWith('==') ? 2 : data.endsWith('=') ? 1 : 0;
    final bytes = data.length * 3 ~/ 4 - padding;
    return bytes < 1024 ? '$bytes bytes' : '${(bytes / 1024).toStringAsFixed(1)} KiB';
  }
}
