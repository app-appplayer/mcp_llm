import 'package:uuid/uuid.dart';

enum MessageRole {
  user,
  assistant,
  system,
  tool,
  error,
}

class ChatMessage {
  final String id;
  final MessageRole role;
  late final String content;
  final DateTime timestamp;
  final bool isStreaming;
  final Map<String, dynamic>? metadata;
  final List<ToolCall>? toolCalls;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isStreaming = false,
    this.metadata,
    this.toolCalls,
  }) :
        id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  // Copy with method
  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    bool? isStreaming,
    Map<String, dynamic>? metadata,
    List<ToolCall>? toolCalls,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      metadata: metadata ?? this.metadata,
      toolCalls: toolCalls ?? this.toolCalls,
    );
  }

  // Append content (for streaming)
  ChatMessage appendContent(String additionalContent) {
    return copyWith(
      content: content + additionalContent,
    );
  }

  // Set streaming state
  ChatMessage setStreamingState(bool streaming) {
    return copyWith(
      isStreaming: streaming,
    );
  }

  // To JSON method
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.toString().split('.').last,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'isStreaming': isStreaming,
      'metadata': metadata,
      'toolCalls': toolCalls?.map((t) => t.toJson()).toList(),
    };
  }

  // From JSON factory
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      role: _roleFromString(json['role'] as String),
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isStreaming: json['isStreaming'] as bool? ?? false,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
      toolCalls: json['toolCalls'] != null
          ? (json['toolCalls'] as List)
          .map((t) => ToolCall.fromJson(t as Map<String, dynamic>))
          .toList()
          : null,
    );
  }

  // Helper to parse role from string
  static MessageRole _roleFromString(String role) {
    switch (role.toLowerCase()) {
      case 'user':
        return MessageRole.user;
      case 'assistant':
        return MessageRole.assistant;
      case 'system':
        return MessageRole.system;
      case 'tool':
        return MessageRole.tool;
      case 'error':
        return MessageRole.error;
      default:
        return MessageRole.user;
    }
  }

  // Create system message
  factory ChatMessage.system(String content) {
    return ChatMessage(
      role: MessageRole.system,
      content: content,
    );
  }

  // Create user message
  factory ChatMessage.user(String content) {
    return ChatMessage(
      role: MessageRole.user,
      content: content,
    );
  }

  // Create assistant message
  factory ChatMessage.assistant(String content, {
    bool isStreaming = false,
    List<ToolCall>? toolCalls,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      role: MessageRole.assistant,
      content: content,
      isStreaming: isStreaming,
      toolCalls: toolCalls,
      metadata: metadata,
    );
  }

  // Create error message
  factory ChatMessage.error(String content) {
    return ChatMessage(
      role: MessageRole.error,
      content: content,
    );
  }

  // Create tool message
  factory ChatMessage.tool(String content, {
    required String toolName,
    required String toolId,
  }) {
    return ChatMessage(
      role: MessageRole.tool,
      content: content,
      metadata: {
        'toolName': toolName,
        'toolId': toolId,
      },
    );
  }
}

class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String? result;

  ToolCall({
    String? id,
    required this.name,
    required this.arguments,
    this.result,
  }) : id = id ?? const Uuid().v4();

  // To JSON method
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'arguments': arguments,
      'result': result,
    };
  }

  // From JSON factory
  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      id: json['id'] as String,
      name: json['name'] as String,
      arguments: Map<String, dynamic>.from(json['arguments'] as Map),
      result: json['result'] as String?,
    );
  }

  // Copy with method
  ToolCall copyWith({
    String? id,
    String? name,
    Map<String, dynamic>? arguments,
    String? result,
  }) {
    return ToolCall(
      id: id ?? this.id,
      name: name ?? this.name,
      arguments: arguments ?? this.arguments,
      result: result,
    );
  }

  // Add result
  ToolCall withResult(String toolResult) {
    return copyWith(
      result: toolResult,
    );
  }
}