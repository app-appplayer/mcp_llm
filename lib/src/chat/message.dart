/// Represents a chat message in a conversation
class LlmMessage {
  /// The role of the message sender (e.g., 'user', 'assistant', 'system', 'tool')
  final String role;

  /// The content of the message (can be a String or structured content)
  final dynamic content;

  /// When the message was created
  final DateTime timestamp;

  /// Optional metadata about the message
  final Map<String, dynamic> metadata;

  /// Create a new message
  LlmMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.metadata = const {},
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create a message from JSON
  factory LlmMessage.fromJson(Map<String, dynamic> json) {
    return LlmMessage(
      role: json['role'] as String,
      content: json['content'],
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : {},
    );
  }

  /// Convert message to JSON
  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  /// Create a user message
  static LlmMessage user(String content, {Map<String, dynamic>? metadata}) {
    return LlmMessage(
      role: 'user',
      content: content,
      metadata: metadata ?? {},
    );
  }

  /// Create an assistant message
  static LlmMessage assistant(String content, {Map<String, dynamic>? metadata}) {
    return LlmMessage(
      role: 'assistant',
      content: content,
      metadata: metadata ?? {},
    );
  }

  /// Create a system message
  static LlmMessage system(String content, {Map<String, dynamic>? metadata}) {
    return LlmMessage(
      role: 'system',
      content: content,
      metadata: metadata ?? {},
    );
  }


  /// Create a tool message
  static LlmMessage tool(String toolName, dynamic result, {Map<String, dynamic>? metadata}) {
    return LlmMessage(
      role: 'function',
      content: {
        'type': 'tool_result',
        'tool': toolName,
        'content': result,
      },
      metadata: metadata ?? {'tool_name': toolName},
    );
  }

  /// Get text representation of the message
  String getTextContent() {
    if (content is String) {
      return content as String;
    } else if (content is Map) {
      if (content['type'] == 'text') {
        return content['text'] as String? ?? '';
      } else if (content['type'] == 'tool_result') {
        final toolContent = content['content'];
        if (toolContent is String) {
          return toolContent;
        } else {
          return toolContent.toString();
        }
      }
    }

    return content.toString();
  }
}