import '../adapter/llm_server_adapter.dart';
import '../chat/message.dart';
import 'llm_context.dart';

/// Content type enum
enum LlmContentType {
  text,
  image,
  resource,
  toolCall,
  toolResult,
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
abstract class LLmContent {
  final LlmContentType type;

  LLmContent(this.type);

  Map<String, dynamic> toJson();

  @override
  String toString() {
    return toJson().toString();
  }
}

/// Text content representation
class LlmTextContent extends LLmContent {
  final String text;

  LlmTextContent({required this.text}) : super(LlmContentType.text);

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
class LlmImageContent extends LLmContent {
  final String url;
  final String? base64Data;
  final String mimeType;

  LlmImageContent({
    required this.url,
    this.base64Data,
    required this.mimeType,
  }) : super(LlmContentType.image);

  factory LlmImageContent.fromBase64({
    required String base64Data,
    required String mimeType,
  }) {
    return LlmImageContent(
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
class LlmResourceContent extends LLmContent {
  final String uri;
  final String? text;
  final String? blob;

  LlmResourceContent({
    required this.uri,
    this.text,
    this.blob,
  }) : super(LlmContentType.resource);

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
class LlmToolCallContent extends LLmContent {
  final String toolName;
  final Map<String, dynamic> arguments;

  LlmToolCallContent({
    required this.toolName,
    required this.arguments,
  }) : super(LlmContentType.toolCall);

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
class LlmToolResultContent extends LLmContent {
  final String toolName;
  final dynamic result;
  final bool isError;

  LlmToolResultContent({
    required this.toolName,
    required this.result,
    this.isError = false,
  }) : super(LlmContentType.toolResult);

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
class LlmTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final String? id;

  LlmTool({
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

  factory LlmTool.fromJson(Map<String, dynamic> json) {
    return LlmTool(
      name: json['name'] as String,
      description: json['description'] as String,
      inputSchema: json['inputSchema'] as Map<String, dynamic>,
      id: json['id'] as String?,
    );
  }
}

/// Tool call request
class LlmToolCall {
  final String name;
  final Map<String, dynamic> arguments;
  final String? id;

  LlmToolCall({
    required this.name,
    required this.arguments,
    this.id,
  });

  // Method to create ID if it doesn't exist
  String getOrCreateId() {
    return id ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'name': name,
      'arguments': arguments,
    };

    if (id != null) {
      result['id'] = id as String;
    }

    return result;
  }

  // Create new instance with added ID
  LlmToolCall withId(String newId) {
    return LlmToolCall(
      name: name,
      arguments: arguments,
      id: newId,
    );
  }
}

/// Tool call result
class LlmCallToolResult implements CallToolResult {
  @override
  final List<LLmContent> content;
  @override
  final bool isStreaming;
  @override
  final bool? isError;

  LlmCallToolResult(
      this.content, {
        this.isStreaming = false,
        this.isError,
      });

  @override
  Map<String, dynamic> toJson() {
    return {
      'content': content.map((c) => c.toJson()).toList(),
      'isStreaming': isStreaming,
      if (isError != null) 'isError': isError,
    };
  }
}

/// Resource definition
class LlmResource {
  final String uri;
  final String name;
  final String description;
  final String mimeType;
  final String? uriTemplate;

  LlmResource({
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
      'mimeType': mimeType,
      if (uriTemplate != null) 'uriTemplate' : uriTemplate
    };

    return result;
  }
}

/// Resource read result
class LlmReadResourceResult {
  final String content;
  final String mimeType;
  final List<LLmContent> contents;

  LlmReadResourceResult({
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
class LlmPromptArgument {
  final String name;
  final String description;
  final bool required;
  final String? defaultValue;

  LlmPromptArgument({
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
class LlmPrompt {
  final String name;
  final String description;
  final List<LlmPromptArgument> arguments;

  LlmPrompt({
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
class LlmGetPromptResult {
  final String description;
  final List<LlmMessage> messages;

  LlmGetPromptResult({
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
  final List<LlmMessage> history;

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
    List<LlmMessage>? history,
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
  LlmRequest withMessage(LlmMessage message) {
    final updatedHistory = List<LlmMessage>.from(history)..add(message);
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
  final List<LlmToolCall>? toolCalls;

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

/// LLM configuration with enhanced retry capabilities
class LlmConfiguration {
  final String? apiKey;
  final String? model;
  final String? baseUrl;
  final Map<String, dynamic>? options;

  // Retry configuration
  final bool retryOnFailure;
  final int maxRetries;
  final Duration retryDelay;
  final bool useExponentialBackoff;
  final Duration maxRetryDelay;

  // Request timeout
  final Duration timeout;

  LlmConfiguration({
    this.apiKey,
    this.model,
    this.baseUrl,
    this.options,
    this.retryOnFailure = true,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
    this.useExponentialBackoff = true,
    this.maxRetryDelay = const Duration(seconds: 30),
    this.timeout = const Duration(seconds: 60),
  });

  /// Create a copy with modified values
  LlmConfiguration copyWith({
    String? apiKey,
    String? model,
    String? baseUrl,
    Map<String, dynamic>? options,
    bool? retryOnFailure,
    int? maxRetries,
    Duration? retryDelay,
    bool? useExponentialBackoff,
    Duration? maxRetryDelay,
    Duration? timeout,
  }) {
    return LlmConfiguration(
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
      options: options ?? this.options,
      retryOnFailure: retryOnFailure ?? this.retryOnFailure,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      useExponentialBackoff: useExponentialBackoff ?? this.useExponentialBackoff,
      maxRetryDelay: maxRetryDelay ?? this.maxRetryDelay,
      timeout: timeout ?? this.timeout,
    );
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};

    if (apiKey != null) result['api_key'] = apiKey;
    if (model != null) result['model'] = model;
    if (baseUrl != null) result['base_url'] = baseUrl;
    if (options != null) result['options'] = options;

    result['retry_on_failure'] = retryOnFailure;
    result['max_retries'] = maxRetries;
    result['retry_delay_ms'] = retryDelay.inMilliseconds;
    result['use_exponential_backoff'] = useExponentialBackoff;
    result['max_retry_delay_ms'] = maxRetryDelay.inMilliseconds;
    result['timeout_ms'] = timeout.inMilliseconds;

    return result;
  }
}

