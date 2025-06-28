import 'storage_interface.dart';
import 'persistent_storage.dart';
import '../chat/history.dart';
import '../chat/message.dart';

/// IO implementation of storage that wraps PersistentStorage
class IoStorage implements StorageInterface {
  final PersistentStorage _storage;
  
  IoStorage({String? basePath}) 
    : _storage = PersistentStorage(basePath ?? '.mcp_llm_storage');
  
  @override
  Future<void> initialize() async {
    // PersistentStorage doesn't have an initialize method
    // It creates directories as needed
  }

  @override
  Future<void> storeMessage(String sessionId, LlmMessage message) async {
    final history = await retrieveHistory(sessionId) ?? ChatHistory();
    history.addMessage(message);
    
    // Convert to the format expected by PersistentStorage
    final messages = history.messages.map((m) => {
      'role': m.role,
      'content': m.content,
      'timestamp': m.timestamp.toIso8601String(),
      'metadata': m.metadata,
    }).toList();
    
    await _storage.saveObject('chat_$sessionId', {'messages': messages});
  }

  @override
  Future<ChatHistory?> retrieveHistory(String sessionId, {int? limit}) async {
    final data = await _storage.loadObject('chat_$sessionId');
    if (data == null || data['messages'] == null) {
      return null;
    }
    final messages = data['messages'] as List<dynamic>;
    
    final history = ChatHistory();
    for (final msgData in messages) {
      final message = LlmMessage(
        role: msgData['role'] as String,
        content: msgData['content'],
        timestamp: msgData['timestamp'] != null 
          ? DateTime.parse(msgData['timestamp'] as String)
          : DateTime.now(),
        metadata: msgData['metadata'] as Map<String, dynamic>? ?? {},
      );
      history.addMessage(message);
    }
    
    if (limit != null && history.messages.length > limit) {
      // Return only the last 'limit' messages
      final limitedMessages = history.messages.skip(history.messages.length - limit).toList();
      final limitedHistory = ChatHistory();
      limitedHistory.messages.addAll(limitedMessages);
      return limitedHistory;
    }
    
    return history;
  }

  @override
  Future<void> updateMessage(String sessionId, String messageId, LlmMessage message) async {
    final history = await retrieveHistory(sessionId);
    if (history == null) return;
    
    final index = history.messages.indexWhere((m) => 
      m.metadata['id'] == messageId || 
      m.timestamp.toIso8601String() == messageId
    );
    
    if (index != -1) {
      history.messages[index] = message;
      
      // Save updated history
      final messages = history.messages.map((m) => {
        'role': m.role,
        'content': m.content,
        'timestamp': m.timestamp.toIso8601String(),
        'metadata': m.metadata,
      }).toList();
      
      await _storage.saveObject('chat_$sessionId', {'messages': messages});
    }
  }

  @override
  Future<void> deleteMessage(String sessionId, String messageId) async {
    final history = await retrieveHistory(sessionId);
    if (history == null) return;
    
    history.messages.removeWhere((m) => 
      m.metadata['id'] == messageId || 
      m.timestamp.toIso8601String() == messageId
    );
    
    // Save updated history
    final messages = history.messages.map((m) => {
      'role': m.role,
      'content': m.content,
      'timestamp': m.timestamp.toIso8601String(),
      'metadata': m.metadata,
    }).toList();
    
    await _storage.saveObject('chat_$sessionId', {'messages': messages});
  }

  @override
  Future<void> clearHistory(String sessionId) async {
    await _storage.delete('chat_$sessionId');
  }

  @override
  Future<List<String>> listSessions() async {
    final keys = await _storage.listKeys('chat_');
    return keys.map((key) => key.replaceFirst('chat_', '')).toList();
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    await _storage.delete('chat_$sessionId');
  }

  @override
  Future<bool> sessionExists(String sessionId) async {
    final sessions = await listSessions();
    return sessions.contains(sessionId);
  }

  @override
  Future<void> store(String key, dynamic value) async {
    if (value is String) {
      await _storage.saveString(key, value);
    } else if (value is Map<String, dynamic>) {
      await _storage.saveObject(key, value);
    } else if (value is List<int>) {
      await _storage.saveData(key, value);
    } else {
      // Convert to JSON for other types
      await _storage.saveObject(key, {'value': value});
    }
  }

  @override
  Future<dynamic> retrieve(String key) async {
    // Try different storage types
    final stringValue = await _storage.loadString(key);
    if (stringValue != null) return stringValue;
    
    final objectValue = await _storage.loadObject(key);
    if (objectValue != null) {
      // Check if it's a wrapped value
      if (objectValue.containsKey('value')) {
        return objectValue['value'];
      }
      return objectValue;
    }
    
    final dataValue = await _storage.loadData(key);
    return dataValue;
  }

  @override
  Future<void> delete(String key) async {
    await _storage.delete(key);
  }

  @override
  Future<bool> exists(String key) async {
    return await _storage.exists(key);
  }

  @override
  Future<void> clear() async {
    await _storage.clear();
  }
}

/// Factory function to create IO storage
StorageInterface createStorage() => IoStorage();