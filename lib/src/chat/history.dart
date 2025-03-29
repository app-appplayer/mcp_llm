import 'message.dart';

/// Manages the history of messages for a chat session
class ChatHistory {
  /// List of messages in the history
  final List<Message> _messages = [];

  /// Get the list of messages
  List<Message> get messages => List.unmodifiable(_messages);

  /// Get the number of messages in the history
  int get length => _messages.length;

  /// Add a message to the history
  void addMessage(Message message) {
    _messages.add(message);
  }

  /// Get a message by index
  Message? getMessage(int index) {
    if (index >= 0 && index < _messages.length) {
      return _messages[index];
    }
    return null;
  }

  /// Get the last N messages
  List<Message> getLastMessages(int count) {
    if (count >= _messages.length) {
      return List.unmodifiable(_messages);
    }

    return List.unmodifiable(
        _messages.sublist(_messages.length - count, _messages.length));
  }

  /// Remove a message by index
  bool removeMessage(int index) {
    if (index >= 0 && index < _messages.length) {
      _messages.removeAt(index);
      return true;
    }
    return false;
  }

  /// Insert a message at a specific index
  void insertMessage(int index, Message message) {
    if (index >= 0 && index <= _messages.length) {
      _messages.insert(index, message);
    } else {
      throw RangeError('Index out of range: $index');
    }
  }

  /// Clear all messages
  void clear() {
    _messages.clear();
  }

  /// Create from JSON
  void fromJson(Map<String, dynamic> json) {
    clear();

    final messagesList = json['messages'] as List<dynamic>?;
    if (messagesList != null) {
      for (final messageData in messagesList) {
        final message = Message.fromJson(messageData as Map<String, dynamic>);
        addMessage(message);
      }
    }
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'messages': _messages.map((message) => message.toJson()).toList(),
    };
  }

  /// Get filtered messages by role
  List<Message> getMessagesByRole(String role) {
    return _messages.where((message) => message.role == role).toList();
  }

  /// Get system messages
  List<Message> get systemMessages => getMessagesByRole('system');

  /// Get user messages
  List<Message> get userMessages => getMessagesByRole('user');

  /// Get assistant messages
  List<Message> get assistantMessages => getMessagesByRole('assistant');

  /// Get tool messages
  List<Message> get toolMessages => getMessagesByRole('tool');
}