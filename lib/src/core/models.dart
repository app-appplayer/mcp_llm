import '../chat/message.dart';
import 'llm_context.dart';

/// Base content type enum for MCP
enum MessageRole {
  user,
  assistant,
  system,
  tool,
}

/// Content type enum
enum MCPContentType {
  text,
  image,
  resource,
  toolCall,
  toolResult,
}

/// Log levels for MCP protocol
enum McpLogLevel {
  debug,    // 0
  info,     // 1
  notice,   // 2
  warning,  // 3
  error,    // 4
  critical, // 5
  alert,    // 6
  emergency // 7
}

/// LLM capabilities enum
enum LlmCapability {
  completion,
  streaming,
  embeddings,
  toolUse,
  imageGeneration,
  imageUnderstanding,
  functionCalling,
}

/// Base class for all MCP content types
abstract class Content {
  final MCPContentType type;

  Content(this.type);

  Map<String, dynamic> toJson();

  @override
  String toString() {
    return toJson().toString();
  }
}

/// Text content representation
class TextContent extends Content {
  final String text;

  TextContent({required this.text}) : super(MCPContentType.text);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'text',
      'text': text,
    };
  }

  @override
  String toString() => text;
}

/// Image content representation
class ImageContent extends Content {
  final String url;
  final String? base64Data;
  final String mimeType;

  ImageContent({
    required this.url,
    this.base64Data,
    required this.mimeType,
  }) : super(MCPContentType.image);

  factory ImageContent.fromBase64({
    required String base64Data,
    required String mimeType,
  }) {
    return ImageContent(
      url: 'data:$mimeType;base64,$base64Data',
      base64Data: base64Data,
      mimeType: mimeType,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'image',
      'url': url,
      'mimeType': mimeType,
    };
  }

  @override
  String toString() => 'Image: $url';
}

/// Resource content representation
class ResourceContent extends Content {
  final String uri;
  final String? text;
  final String? blob;

  ResourceContent({
    required this.uri,
    this.text,
    this.blob,
  }) : super(MCPContentType.resource);

  @override
  Map<String, dynamic> toJson() {
    final json = {
      'type': 'resource',
      'uri': uri,
    };

    if (text != null) {
      json['text'] = text!;
    }

    if (blob != null) {
      json['blob'] = blob!;
    }

    return json;
  }

  @override
  String toString() => text ?? 'Resource: $uri';
}

/// Tool call result content
class ToolCallContent extends Content {
  final String toolName;
  final Map<String, dynamic> arguments;

  ToolCallContent({
    required this.toolName,
    required this.arguments,
  }) : super(MCPContentType.toolCall);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'tool_call',
      'tool': toolName,
      'arguments': arguments,
    };
  }

  @override
  String toString() => 'Tool call: $toolName with arguments: $arguments';
}

/// Tool result content
class ToolResultContent extends Content {
  final String toolName;
  final dynamic result;
  final bool isError;

  ToolResultContent({
    required this.toolName,
    required this.result,
    this.isError = false,
  }) : super(MCPContentType.toolResult);

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'toolResult',
      'tool': toolName,
      'result': result,
      'isError': isError,
    };
  }

  @override
  String toString() {
    if (isError) {
      return 'Tool error: $toolName - $result';
    }
    return 'Tool result: $toolName - $result';
  }
}

/// Tool definition
class Tool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final String? id;

  Tool({
    required this.name,
    required this.description,
    required this.inputSchema,
    this.id,
  });

  Map<String, dynamic> toJson() {
    final result = {
      'name': name,
      'description': description,
      'inputSchema': inputSchema,
    };

    if (id != null) {
      result['id'] = id as String;
    }

    return result;
  }

  factory Tool.fromJson(Map<String, dynamic> json) {
    return Tool(
      name: json['name'] as String,
      description: json['description'] as String,
      inputSchema: json['inputSchema'] as Map<String, dynamic>,
      id: json['id'] as String?,
    );
  }
}

/// Tool call request
class ToolCall {
  final String name;
  final Map<String, dynamic> arguments;
  final String? id;

  ToolCall({
    required this.name,
    required this.arguments,
    this.id,
  });

  Map<String, dynamic> toJson() {
    final result = {
      'name': name,
      'arguments': arguments,
    };

    if (id != null) {
      result['id'] = id as String;
    }

    return result;
  }
}

/// Tool call result
class CallToolResult {
  final List<Content> content;
  final bool isStreaming;
  final bool? isError;

  CallToolResult(
      this.content, {
        this.isStreaming = false,
        this.isError,
      });

  Map<String, dynamic> toJson() {
    return {
      'content': content.map((c) => c.toJson()).toList(),
      'isStreaming': isStreaming,
      if (isError != null) 'isError': isError,
    };
  }
}

/// Resource definition
class Resource {
  final String uri;
  final String name;
  final String description;
  final String? mimeType;
  final String? uriTemplate;

  Resource({
    required this.uri,
    required this.name,
    required this.description,
    required this.mimeType,
    this.uriTemplate,
  });

  Map<String, dynamic> toJson() {
    final result = {
      'uri': uri,
      'name': name,
      'description': description,
      if (mimeType != null) 'mimeType': mimeType,
      if (uriTemplate != null) 'uriTemplate' : uriTemplate
    };

    return result;
  }
}

/// Resource read result
class ReadResourceResult {
  final String content;
  final String mimeType;
  final List<Content> contents;

  ReadResourceResult({
    required this.content,
    required this.mimeType,
    required this.contents,
  });

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'mimeType': mimeType,
      'contents': contents.map((c) => c.toJson()).toList(),
    };
  }
}

/// Prompt argument definition
class PromptArgument {
  final String name;
  final String description;
  final bool required;
  final String? defaultValue;

  PromptArgument({
    required this.name,
    required this.description,
    this.required = false,
    this.defaultValue,
  });

  Map<String, dynamic> toJson() {
    final result = {
      'name': name,
      'description': description,
      'required': required,
    };

    if (defaultValue != null) {
      result['default'] = defaultValue!;
    }

    return result;
  }
}

/// Prompt definition
class Prompt {
  final String name;
  final String description;
  final List<PromptArgument> arguments;

  Prompt({
    required this.name,
    required this.description,
    required this.arguments,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'arguments': arguments.map((arg) => arg.toJson()).toList(),
    };
  }
}

/// Get prompt result
class GetPromptResult {
  final String description;
  final List<Message> messages;

  GetPromptResult({
    required this.description,
    required this.messages,
  });

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'messages': messages.map((m) => m.toJson()).toList(),
    };
  }
}

/// Represents a request to an LLM
class LlmRequest {
  /// The prompt to send to the LLM
  final String prompt;

  /// Conversation history
  final List<Message> history;

  /// Request parameters (temperature, max_tokens, etc.)
  final Map<String, dynamic> parameters;

  /// Optional context for the request
  final LlmContext? context;

  /// Create a new LLM request
  LlmRequest({
    required this.prompt,
    this.history = const [],
    this.parameters = const {},
    this.context,
  });

  /// Create a copy with modified values
  LlmRequest copyWith({
    String? prompt,
    List<Message>? history,
    Map<String, dynamic>? parameters,
    LlmContext? context,
  }) {
    return LlmRequest(
      prompt: prompt ?? this.prompt,
      history: history ?? this.history,
      parameters: parameters ?? Map<String, dynamic>.from(this.parameters),
      context: context ?? this.context,
    );
  }

  /// Add a system instruction to the request
  LlmRequest withSystemInstruction(String instruction) {
    final updatedParams = Map<String, dynamic>.from(parameters);
    updatedParams['system'] = instruction;
    return copyWith(parameters: updatedParams);
  }

  /// Set the maximum number of tokens
  LlmRequest withMaxTokens(int maxTokens) {
    final updatedParams = Map<String, dynamic>.from(parameters);
    updatedParams['max_tokens'] = maxTokens;
    return copyWith(parameters: updatedParams);
  }

  /// Set the temperature
  LlmRequest withTemperature(double temperature) {
    final updatedParams = Map<String, dynamic>.from(parameters);
    updatedParams['temperature'] = temperature;
    return copyWith(parameters: updatedParams);
  }

  /// Add a message to the history
  LlmRequest withMessage(Message message) {
    final updatedHistory = List<Message>.from(history)..add(message);
    return copyWith(history: updatedHistory);
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'prompt': prompt,
      'history': history.map((h) => h.toJson()).toList(),
      'parameters': parameters,
      if (context != null) 'context': context is Map ? context : context?.toJson(),
    };
  }
}

/// LLM response for completions
class LlmResponse {
  final String text;
  final Map<String, dynamic> metadata;
  final List<ToolCall>? toolCalls;

  LlmResponse({
    required this.text,
    this.metadata = const {},
    this.toolCalls,
  });

  Map<String, dynamic> toJson() {
    final result = {
      'text': text,
      'metadata': metadata,
    };

    if (toolCalls != null) {
      result['toolCalls'] = toolCalls!.map((tc) => tc.toJson()).toList();
    }

    return result;
  }
}

/// LLM response chunk for streaming
class LlmResponseChunk {
  final String textChunk;
  final bool isDone;
  final Map<String, dynamic> metadata;

  LlmResponseChunk({
    required this.textChunk,
    this.isDone = false,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'textChunk': textChunk,
      'isDone': isDone,
      'metadata': metadata,
    };
  }
}

/// LLM configuration
class LlmConfiguration {
  final String? apiKey;
  final String? model;
  final String? baseUrl;
  final Map<String, dynamic>? options;

  LlmConfiguration({
    this.apiKey,
    this.model,
    this.baseUrl,
    this.options,
  });

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};

    if (apiKey != null) result['api_key'] = apiKey;
    if (model != null) result['model'] = model;
    if (baseUrl != null) result['base_url'] = baseUrl;
    if (options != null) result['options'] = options;

    return result;
  }
}

/// Abstract base class for server transport implementations
abstract class ServerTransport {
  /// Stream of incoming messages
  Stream<dynamic> get onMessage;

  /// Future that completes when the transport is closed
  Future<void> get onClose;

  /// Send a message through the transport
  void send(dynamic message);

  /// Close the transport
  void close();
}

/// Client session information
class ClientSession {
  final String id;
  final ServerTransport transport;
  Map<String, dynamic> capabilities;
  final DateTime connectedAt;
  String? negotiatedProtocolVersion;
  bool isInitialized = false;
  List<Root> roots = [];

  ClientSession({
    required this.id,
    required this.transport,
    required this.capabilities,
  }) : connectedAt = DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'connected_at': connectedAt.toIso8601String(),
      'protocol_version': negotiatedProtocolVersion,
      'initialized': isInitialized,
      'capabilities': capabilities,
      'roots': roots.map((r) => r.toJson()).toList(),
    };
  }
}

/// Root definition for filesystem access
class Root {
  final String uri;
  final String name;
  final String? description;

  Root({
    required this.uri,
    required this.name,
    this.description,
  });

  Map<String, dynamic> toJson() {
    final result = {
      'uri': uri,
      'name': name,
      if (description != null) 'description' : description!
    };

    return result;
  }
}

/// Server health information
class ServerHealth {
  final bool isRunning;
  final int connectedSessions;
  final int registeredTools;
  final int registeredResources;
  final int registeredPrompts;
  final DateTime startTime;
  final Duration uptime;
  final Map<String, dynamic> metrics;

  ServerHealth({
    required this.isRunning,
    required this.connectedSessions,
    required this.registeredTools,
    required this.registeredResources,
    required this.registeredPrompts,
    required this.startTime,
    required this.uptime,
    required this.metrics,
  });

  Map<String, dynamic> toJson() {
    return {
      'isRunning': isRunning,
      'connectedSessions': connectedSessions,
      'registeredTools': registeredTools,
      'registeredResources': registeredResources,
      'registeredPrompts': registeredPrompts,
      'startTime': startTime.toIso8601String(),
      'uptimeSeconds': uptime.inSeconds,
      'metrics': metrics,
    };
  }
}

/// Cached resource item for performance optimization
class CachedResource {
  final String uri;
  final ReadResourceResult content;
  final DateTime cachedAt;
  final Duration maxAge;

  CachedResource({
    required this.uri,
    required this.content,
    required this.cachedAt,
    required this.maxAge,
  });

  bool get isExpired {
    final now = DateTime.now();
    final expiresAt = cachedAt.add(maxAge);
    return now.isAfter(expiresAt);
  }
}

/// Pending operation for cancellation support
class PendingOperation {
  final String id;
  final String sessionId;
  final String type;
  final DateTime createdAt;
  final String? requestId;
  bool isCancelled = false;

  PendingOperation({
    required this.id,
    required this.sessionId,
    required this.type,
    this.requestId,
  }) : createdAt = DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'type': type,
      'created_at': createdAt.toIso8601String(),
      'is_cancelled': isCancelled,
      if (requestId != null) 'request_id': requestId,
    };
  }
}

/// Error codes for standardized error handling
class ErrorCode {
  // Standard JSON-RPC error codes
  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;

  // MCP protocol error codes
  static const int resourceNotFound = -32100;
  static const int toolNotFound = -32101;
  static const int promptNotFound = -32102;
  static const int incompatibleVersion = -32103;
  static const int unauthorized = -32104;
  static const int operationCancelled = -32105;
}