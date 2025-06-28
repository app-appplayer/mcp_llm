import '../chat/history.dart';
import '../chat/message.dart';

/// Abstract interface for storage implementations
abstract class StorageInterface {
  /// Initialize the storage
  Future<void> initialize();

  /// Store a chat message
  Future<void> storeMessage(String sessionId, LlmMessage message);

  /// Retrieve chat history
  Future<ChatHistory?> retrieveHistory(String sessionId, {int? limit});

  /// Update a chat message
  Future<void> updateMessage(String sessionId, String messageId, LlmMessage message);

  /// Delete a chat message
  Future<void> deleteMessage(String sessionId, String messageId);

  /// Clear chat history
  Future<void> clearHistory(String sessionId);

  /// List all session IDs
  Future<List<String>> listSessions();

  /// Delete a session
  Future<void> deleteSession(String sessionId);

  /// Check if session exists
  Future<bool> sessionExists(String sessionId);

  /// Store arbitrary data
  Future<void> store(String key, dynamic value);

  /// Retrieve arbitrary data
  Future<dynamic> retrieve(String key);

  /// Delete arbitrary data
  Future<void> delete(String key);

  /// Check if key exists
  Future<bool> exists(String key);

  /// Clear all data
  Future<void> clear();
}

/// Factory function type for creating storage instances
typedef StorageFactory = StorageInterface Function();