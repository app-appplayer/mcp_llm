import 'dart:convert';

import '../core/llm_interface.dart';
import '../storage/storage_manager.dart';
import '../utils/logger.dart';
import '../utils/token_counter.dart';
import 'message.dart';
import 'history.dart';

/// Manages a chat session with an LLM, including history and context
class ChatSession {
  final LlmInterface llmProvider;
  final StorageManager? storageManager;
  final String id;
  final String? title;
  final Logger _logger = Logger('mcp_llm.chat_session');
  final TokenCounter _tokenCounter = TokenCounter();

  /// Chat history management
  final ChatHistory _history;

  /// Max tokens to keep in context (provider dependent)
  final int _maxContextTokens;

  /// Create a new chat session
  ChatSession({
    required this.llmProvider,
    this.storageManager,
    this.id = '',
    this.title,
    int? maxContextTokens,
  }) : _maxContextTokens = maxContextTokens ?? 8192,
        _history = ChatHistory();

  /// Get current chat history
  List<LlmMessage> get messages => _history.messages;

  /// Get all user messages
  List<LlmMessage> get userMessages => _history.userMessages;

  /// Get all assistant messages
  List<LlmMessage> get assistantMessages => _history.assistantMessages;

  /// Get all system messages
  List<LlmMessage> get systemMessages => _history.systemMessages;

  /// Get all tool messages
  List<LlmMessage> get toolMessages => _history.toolMessages;

  /// Get the number of messages in history
  int get messageCount => _history.length;

  /// Add a user message to the chat
  void addUserMessage(String content) {
    final message = LlmMessage(
      role: 'user',
      content: content,
      timestamp: DateTime.now(),
    );

    _history.addMessage(message);
    _persistHistory();

    _logger.debug('Added user message to chat session');
  }

  /// Add an assistant message to the chat
  void addAssistantMessage(String content) {
    final message = LlmMessage(
      role: 'assistant',
      content: content,
      timestamp: DateTime.now(),
    );

    _history.addMessage(message);
    _persistHistory();

    _logger.debug('Added assistant message to chat session');
  }

  /// Add a system message to the chat
  void addSystemMessage(String content) {
    final message = LlmMessage(
      role: 'system',
      content: content,
      timestamp: DateTime.now(),
    );

    _history.addMessage(message);
    _persistHistory();

    _logger.debug('Added system message to chat session');
  }

  /// Add a pre-built tool message to the chat
  void addToolMessage(LlmMessage message) {
    _history.addMessage(message);
    _persistHistory();

    _logger.debug('Added tool message to chat session');
  }

  /// Add tool result with structured messages
  void addToolResult(String toolName, Map<String, dynamic> arguments, List<dynamic> results, {String? toolCallId}) {
    final callId = toolCallId ?? 'call_${DateTime.now().millisecondsSinceEpoch}';

    // Convert tool results to content
    dynamic resultContent;
    if (results.isNotEmpty) {
      if (results.first is Map) {
        resultContent = jsonEncode(results.first);
      } else {
        resultContent = results.first.toString();
      }
    } else {
      resultContent = '';
    }

    // Add structured tool result message
    final toolMessage = LlmMessage.tool(
      toolName,
      resultContent,
      toolCallId: callId,
      arguments: arguments,
    );
    addToolMessage(toolMessage);

    _logger.debug('Added tool result to chat session: $toolName (ID: $callId)');
  }

  /// Add tool error with structured messages
  void addToolError(String toolName, String errorMessage, {String? toolCallId}) {
    final callId = toolCallId ?? 'call_${DateTime.now().millisecondsSinceEpoch}';

    // Add structured tool error message
    final toolMessage = LlmMessage.tool(
      toolName,
      {'error': errorMessage},
      toolCallId: callId,
      metadata: {'is_error': true},
    );
    addToolMessage(toolMessage);

    _logger.debug('Added tool error to chat session: $toolName - $errorMessage (ID: $callId)');
  }

  /// Get messages formatted for LLM context
  List<LlmMessage> getMessagesForContext({int? maxTokens}) {
    final maxTokenCount = maxTokens ?? _maxContextTokens;

    // Get provider model name from llmProvider if possible
    String modelIdentifier = 'gpt';
    if (llmProvider.toString().toLowerCase().contains('claude')) {
      modelIdentifier = 'claude';
    }

    // Start with all messages
    final allMessages = _history.messages;
    int tokenCount = _tokenCounter.countMessageTokens(allMessages, modelIdentifier);

    // If under token limit, return all messages
    if (tokenCount <= maxTokenCount) {
      return allMessages;
    }

    // Need to truncate history
    _logger.debug('Truncating chat history from $tokenCount tokens to $maxTokenCount tokens');

    // Always keep system messages and the most recent exchanges
    final systemMessages = allMessages.where((msg) => msg.role == 'system').toList();
    final nonSystemMessages = allMessages.where((msg) => msg.role != 'system').toList();

    // Start with system messages
    final List<LlmMessage> contextMessages = List.from(systemMessages);
    tokenCount = _tokenCounter.countMessageTokens(contextMessages, modelIdentifier);

    // Add most recent messages first, up to token limit
    for (int i = nonSystemMessages.length - 1; i >= 0; i--) {
      final message = nonSystemMessages[i];
      final messageTokens = _tokenCounter.countMessageTokens([message], modelIdentifier);

      if (tokenCount + messageTokens <= maxTokenCount) {
        contextMessages.insert(systemMessages.length, message);
        tokenCount += messageTokens;
      } else {
        // Token limit reached
        break;
      }
    }

    // Sort messages to ensure chronological order
    contextMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return contextMessages;
  }

  /// Clear the chat history
  void clearHistory() {
    _history.clear();
    _persistHistory();

    _logger.debug('Cleared chat session history');
  }

  /// Save the chat history to storage if available
  void _persistHistory() {
    if (storageManager != null && id.isNotEmpty) {
      try {
        final historyData = _history.toJson();
        storageManager!.saveObject('chat_session_$id', historyData);
        _logger.debug('Saved chat session history to storage');
      } catch (e) {
        _logger.error('Failed to save chat session history: $e');
      }
    }
  }

  /// Load chat history from storage if available
  Future<void> loadHistory() async {
    if (storageManager != null && id.isNotEmpty) {
      try {
        final historyData = await storageManager!.loadObject('chat_session_$id');
        if (historyData != null) {
          _history.fromJson(historyData);
          _logger.debug('Loaded chat session history from storage');
        }
      } catch (e) {
        _logger.error('Failed to load chat session history: $e');
      }
    }
  }
}
