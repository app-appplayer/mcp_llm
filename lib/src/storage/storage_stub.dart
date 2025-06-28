import 'storage_interface.dart';
import '../chat/history.dart';
import '../chat/message.dart';

/// Stub implementation for unsupported platforms
class StorageStub implements StorageInterface {
  @override
  Future<void> initialize() async {
    throw UnsupportedError('Storage is not supported on this platform');
  }

  @override
  Future<void> storeMessage(String sessionId, LlmMessage message) async {
    throw UnsupportedError('Storage is not supported on this platform');
  }

  @override
  Future<ChatHistory?> retrieveHistory(String sessionId, {int? limit}) async {
    throw UnsupportedError('Storage is not supported on this platform');
  }

  @override
  Future<void> updateMessage(String sessionId, String messageId, LlmMessage message) async {
    throw UnsupportedError('Storage is not supported on this platform');
  }

  @override
  Future<void> deleteMessage(String sessionId, String messageId) async {
    throw UnsupportedError('Storage is not supported on this platform');
  }

  @override
  Future<void> clearHistory(String sessionId) async {
    throw UnsupportedError('Storage is not supported on this platform');
  }

  @override
  Future<List<String>> listSessions() async {
    throw UnsupportedError('Storage is not supported on this platform');
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    throw UnsupportedError('Storage is not supported on this platform');
  }

  @override
  Future<bool> sessionExists(String sessionId) async {
    throw UnsupportedError('Storage is not supported on this platform');
  }

  @override
  Future<void> store(String key, dynamic value) async {
    throw UnsupportedError('Storage is not supported on this platform');
  }

  @override
  Future<dynamic> retrieve(String key) async {
    throw UnsupportedError('Storage is not supported on this platform');
  }

  @override
  Future<void> delete(String key) async {
    throw UnsupportedError('Storage is not supported on this platform');
  }

  @override
  Future<bool> exists(String key) async {
    throw UnsupportedError('Storage is not supported on this platform');
  }

  @override
  Future<void> clear() async {
    throw UnsupportedError('Storage is not supported on this platform');
  }
}

/// Factory function to create storage stub
StorageInterface createStorage() => StorageStub();