import 'chat_session.dart';
import 'message.dart';
import '../core/llm_interface.dart';
import '../storage/storage_manager.dart';
import '../utils/logger.dart';

/// Manages a conversation with optional topics and multi-session support
class Conversation {
  /// Unique identifier for the conversation
  final String id;

  /// Title of the conversation
  String title;

  /// Optional topic tags for the conversation
  final List<String> topics;

  /// When the conversation was created
  final DateTime createdAt;

  /// When the conversation was last updated
  DateTime lastUpdatedAt;

  /// Chat sessions in this conversation
  final Map<String, ChatSession> _sessions = {};

  /// The LLM provider to use for this conversation
  final LlmInterface llmProvider;

  /// Storage manager for persisting conversations
  final StorageManager? storageManager;

  /// Logger instance
  final Logger _logger = Logger('mcp_llm.conversation');

  /// Current active session ID
  String? _activeSessionId;

  /// Create a new conversation
  Conversation({
    required this.id,
    required this.title,
    required this.llmProvider,
    this.topics = const [],
    this.storageManager,
    DateTime? createdAt,
    DateTime? lastUpdatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
        lastUpdatedAt = lastUpdatedAt ?? DateTime.now();

  /// Get the active chat session
  ChatSession? get activeSession {
    if (_activeSessionId != null && _sessions.containsKey(_activeSessionId)) {
      return _sessions[_activeSessionId!];
    }
    return null;
  }

  /// Get all session IDs
  List<String> get sessionIds => _sessions.keys.toList();

  /// Create a new chat session in this conversation
  ChatSession createSession({String? sessionId, String? title}) {
    final id = sessionId ?? 'session_${DateTime.now().millisecondsSinceEpoch}';

    if (_sessions.containsKey(id)) {
      throw StateError('Session with ID $id already exists');
    }

    final session = ChatSession(
      id: id,
      title: title,
      llmProvider: llmProvider,
      storageManager: storageManager,
    );

    _sessions[id] = session;
    _activeSessionId = id;
    _updateLastModified();

    _logger.debug('Created new chat session: $id');
    return session;
  }

  /// Get a chat session by ID
  ChatSession? getSession(String sessionId) {
    return _sessions[sessionId];
  }

  /// Set the active session
  void setActiveSession(String sessionId) {
    if (!_sessions.containsKey(sessionId)) {
      throw StateError('Session with ID $sessionId does not exist');
    }

    _activeSessionId = sessionId;
    _logger.debug('Set active session to: $sessionId');
  }

  /// Remove a chat session
  bool removeSession(String sessionId) {
    final removed = _sessions.remove(sessionId) != null;

    if (removed) {
      _updateLastModified();

      // Update active session ID if needed
      if (_activeSessionId == sessionId) {
        _activeSessionId = _sessions.isNotEmpty ? _sessions.keys.first : null;
      }

      _logger.debug('Removed chat session: $sessionId');
    }

    return removed;
  }

  /// Add a topic tag to the conversation
  void addTopic(String topic) {
    if (!topics.contains(topic)) {
      topics.add(topic);
      _updateLastModified();
      _logger.debug('Added topic to conversation: $topic');
    }
  }

  /// Remove a topic tag from the conversation
  bool removeTopic(String topic) {
    final removed = topics.remove(topic);
    if (removed) {
      _updateLastModified();
      _logger.debug('Removed topic from conversation: $topic');
    }
    return removed;
  }

  /// Get all messages across all sessions
  List<LlmMessage> getAllMessages() {
    final allMessages = <LlmMessage>[];

    for (final session in _sessions.values) {
      allMessages.addAll(session.messages);
    }

    // Sort by timestamp
    allMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return allMessages;
  }

  /// Save the conversation to storage
  Future<void> save() async {
    if (storageManager == null) return;

    try {
      final conversationData = toJson();
      await storageManager!.saveObject('conversation_$id', conversationData);
      _logger.debug('Saved conversation to storage: $id');
    } catch (e) {
      _logger.error('Failed to save conversation: $e');
      throw Exception('Failed to save conversation: $e');
    }
  }

  /// Load the conversation from storage
  Future<void> load() async {
    if (storageManager == null) return;

    try {
      final conversationData = await storageManager!.loadObject('conversation_$id');
      if (conversationData != null) {
        fromJson(conversationData);
        _logger.debug('Loaded conversation from storage: $id');
      }
    } catch (e) {
      _logger.error('Failed to load conversation: $e');
      throw Exception('Failed to load conversation: $e');
    }
  }

  /// Update the last modified timestamp
  void _updateLastModified() {
    lastUpdatedAt = DateTime.now();
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'topics': topics,
      'created_at': createdAt.toIso8601String(),
      'last_updated_at': lastUpdatedAt.toIso8601String(),
      'active_session_id': _activeSessionId,
      'sessions': _sessions.map((sessionId, session) =>
          MapEntry(sessionId, {
            'id': session.id,
            'title': session.title,
          })),
    };
  }

  /// Load from JSON
  void fromJson(Map<String, dynamic> json) {
    title = json['title'] as String;

    if (json['topics'] != null) {
      topics.clear();
      topics.addAll((json['topics'] as List<dynamic>).cast<String>());
    }

    _activeSessionId = json['active_session_id'] as String?;

    // Note: Actual session content is loaded separately
    // This just loads the session metadata
  }
}