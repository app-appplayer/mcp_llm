import 'dart:convert';
import 'dart:html' as html;

import 'storage_interface.dart';
import '../chat/history.dart';
import '../chat/message.dart';

/// Web implementation of storage using localStorage
class WebStorage implements StorageInterface {
  static const String _prefix = 'mcp_llm_';
  static const String _sessionsKey = '${_prefix}sessions';
  
  @override
  Future<void> initialize() async {
    // No initialization needed for localStorage
  }

  @override
  Future<void> storeMessage(String sessionId, LlmMessage message) async {
    final history = await retrieveHistory(sessionId) ?? ChatHistory();
    history.addMessage(message);
    
    final key = '${_prefix}session_$sessionId';
    final data = history.toJson();
    html.window.localStorage[key] = jsonEncode(data);
    
    // Update sessions list
    await _addSessionToList(sessionId);
  }

  @override
  Future<ChatHistory?> retrieveHistory(String sessionId, {int? limit}) async {
    final key = '${_prefix}session_$sessionId';
    final data = html.window.localStorage[key];
    
    if (data == null) {
      return null;
    }
    
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final history = ChatHistory.fromJson(json);
      
      if (limit != null && history.messages.length > limit) {
        // Return only the last 'limit' messages
        final limitedHistory = ChatHistory();
        final limitedMessages = history.messages.skip(history.messages.length - limit).toList();
        for (final message in limitedMessages) {
          limitedHistory.addMessage(message);
        }
        return limitedHistory;
      }
      
      return history;
    } catch (e) {
      // Handle corrupted data
      return null;
    }
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
      
      final key = '${_prefix}session_$sessionId';
      final data = history.toJson();
      html.window.localStorage[key] = jsonEncode(data);
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
    
    final key = '${_prefix}session_$sessionId';
    final data = history.toJson();
    html.window.localStorage[key] = jsonEncode(data);
  }

  @override
  Future<void> clearHistory(String sessionId) async {
    final key = '${_prefix}session_$sessionId';
    html.window.localStorage.remove(key);
  }

  @override
  Future<List<String>> listSessions() async {
    final sessionsData = html.window.localStorage[_sessionsKey];
    if (sessionsData == null) {
      return [];
    }
    
    try {
      final sessions = jsonDecode(sessionsData) as List<dynamic>;
      return sessions.cast<String>();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    await clearHistory(sessionId);
    await _removeSessionFromList(sessionId);
  }

  @override
  Future<bool> sessionExists(String sessionId) async {
    final sessions = await listSessions();
    return sessions.contains(sessionId);
  }

  @override
  Future<void> store(String key, dynamic value) async {
    final storageKey = '$_prefix$key';
    html.window.localStorage[storageKey] = jsonEncode(value);
  }

  @override
  Future<dynamic> retrieve(String key) async {
    final storageKey = '$_prefix$key';
    final data = html.window.localStorage[storageKey];
    
    if (data == null) {
      return null;
    }
    
    try {
      return jsonDecode(data);
    } catch (e) {
      return data; // Return as string if not JSON
    }
  }

  @override
  Future<void> delete(String key) async {
    final storageKey = '$_prefix$key';
    html.window.localStorage.remove(storageKey);
  }

  @override
  Future<bool> exists(String key) async {
    final storageKey = '$_prefix$key';
    return html.window.localStorage.containsKey(storageKey);
  }

  @override
  Future<void> clear() async {
    // Remove all keys with our prefix
    final keysToRemove = <String>[];
    
    for (final key in html.window.localStorage.keys) {
      if (key.startsWith(_prefix)) {
        keysToRemove.add(key);
      }
    }
    
    for (final key in keysToRemove) {
      html.window.localStorage.remove(key);
    }
  }

  // Helper methods
  Future<void> _addSessionToList(String sessionId) async {
    final sessions = await listSessions();
    if (!sessions.contains(sessionId)) {
      sessions.add(sessionId);
      html.window.localStorage[_sessionsKey] = jsonEncode(sessions);
    }
  }

  Future<void> _removeSessionFromList(String sessionId) async {
    final sessions = await listSessions();
    sessions.remove(sessionId);
    html.window.localStorage[_sessionsKey] = jsonEncode(sessions);
  }
}

/// Factory function to create web storage
StorageInterface createStorage() => WebStorage();