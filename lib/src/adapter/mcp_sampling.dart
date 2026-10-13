/// `sampling/createMessage` answered by an mcp_llm provider (design:
/// docs/MCP-LAYER-DESIGN.md §3.4): the request becomes an [LlmRequest], the
/// provider's [LlmResponse] becomes the result.
library;

import 'dart:convert';

import '../chat/message.dart';
import '../core/llm_interface.dart';
import '../core/models.dart';
import '../schema/schema.g.dart' as mcp;

/// Answers sampling requests with [provider].
class McpSamplingHandler {
  McpSamplingHandler(this.provider, {required this.model});

  final LlmProvider provider;

  /// The model name reported in results (the provider's configured model).
  final String model;

  /// The handler mcp_client takes: request params JSON in, result JSON out.
  Future<Map<String, dynamic>> handle(Map<String, dynamic> params) async {
    final request = toRequest(mcp.CreateMessageRequestParams.fromJson(params));
    return toResult(await provider.complete(request)).toJson();
  }

  /// The request as the provider takes it. The last message is the prompt;
  /// the ones before it are the history.
  LlmRequest toRequest(mcp.CreateMessageRequestParams params) {
    final messages = params.messages;
    if (messages.isEmpty) throw ArgumentError('sampling request has no messages');
    final history = [for (final m in messages.sublist(0, messages.length - 1)) ..._messages(m)];
    final last = messages.last;
    // An image in the last message reaches the model as an image, just
    // before the prompt text.
    history.addAll([for (final b in last.content) if (b is mcp.ImageContent) _image(_role(last), b)]);
    final tools = params.tools;
    final noTools = params.toolChoice?.mode == mcp.ToolChoiceMode.none;
    return LlmRequest(
      prompt: [for (final b in last.content) if (b is! mcp.ImageContent) _text(b)].join('\n'),
      history: history,
      parameters: {
        'max_tokens': params.maxTokens,
        if (params.temperature != null) 'temperature': params.temperature,
        if (params.systemPrompt != null) 'system': params.systemPrompt,
        if (params.stopSequences != null) 'stop_sequences': params.stopSequences,
        if (tools != null && tools.isNotEmpty && !noTools)
          'tools': [
            for (final t in tools)
              {'name': t.name, 'description': t.description ?? t.title ?? '', 'parameters': t.inputSchema},
          ],
      },
    );
  }

  /// The provider's answer as a sampling result.
  mcp.CreateMessageResult toResult(LlmResponse response) {
    final calls = response.toolCalls ?? const <LlmToolCall>[];
    final content = <mcp.SamplingMessageContentBlock>[
      if (response.text.isNotEmpty || calls.isEmpty) mcp.TextContent(text: response.text),
      for (final c in calls) mcp.ToolUseContent(id: c.getOrCreateId(), name: c.name, input: Map<String, Object?>.from(c.arguments)),
    ];
    return mcp.CreateMessageResult(
      role: mcp.Role.assistant,
      content: content,
      model: response.metadata['model'] as String? ?? model,
      stopReason: calls.isNotEmpty ? 'toolUse' : _stopReason(response.metadata),
    );
  }

  /// The provider's stop reason in the protocol's words; null when it gave
  /// none this vocabulary names.
  static String? _stopReason(Map<String, dynamic> metadata) {
    final reason = metadata['stop_reason'] ?? metadata['finish_reason'];
    return switch (reason) {
      'end_turn' || 'stop' => 'endTurn',
      'max_tokens' || 'length' => 'maxTokens',
      'stop_sequence' => 'stopSequence',
      'tool_use' || 'tool_calls' => 'toolUse',
      _ => null,
    };
  }

  static String _role(mcp.SamplingMessage m) => m.role == mcp.Role.assistant ? 'assistant' : 'user';

  static LlmMessage _image(String role, mcp.ImageContent image) =>
      LlmMessage(role: role, content: LlmImageContent.fromBase64(base64Data: image.data, mimeType: image.mimeType));

  /// One message as provider messages: each image its own message, the
  /// other blocks as text, in their order.
  static List<LlmMessage> _messages(mcp.SamplingMessage m) {
    final role = _role(m);
    final out = <LlmMessage>[];
    final text = <String>[];
    void flush() {
      if (text.isNotEmpty) out.add(LlmMessage(role: role, content: text.join('\n')));
      text.clear();
    }

    for (final block in m.content) {
      if (block is mcp.ImageContent) {
        flush();
        out.add(_image(role, block));
      } else {
        text.add(_text(block));
      }
    }
    flush();
    return out;
  }

  static String _text(mcp.SamplingMessageContentBlock block) => switch (block) {
        mcp.TextContent() => block.text,
        mcp.ImageContent() => '[image ${block.mimeType}]',
        mcp.AudioContent() => '[audio ${block.mimeType}]',
        mcp.ToolUseContent() => 'Tool call ${block.id}: ${block.name}(${jsonEncode(block.input)})',
        mcp.ToolResultContent() =>
          'Tool result for ${block.toolUseId}${block.isError == true ? ' (error)' : ''}: '
              '${block.content.map((c) => c is mcp.TextContent ? c.text : jsonEncode(c.toJson())).join('\n')}',
        _ => jsonEncode(block.toJson()),
      };
}
