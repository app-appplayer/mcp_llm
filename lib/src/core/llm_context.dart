
/// Manages the execution context for LLM requests
class LlmContext {
  /// Additional context information to guide LLM responses
  final Map<String, dynamic> contextInfo;

  /// System instructions to shape LLM behavior
  final String? systemInstructions;

  /// Context window sizing parameters
  final int? maxInputTokens;
  final int? maxOutputTokens;

  /// Execution constraints
  final Duration? timeout;
  final bool allowToolUse;
  final List<String>? allowedTools;

  /// Execution preferences
  final double temperature;
  final double? topP;
  final int? topK;

  const LlmContext({
    this.contextInfo = const {},
    this.systemInstructions,
    this.maxInputTokens,
    this.maxOutputTokens,
    this.timeout,
    this.allowToolUse = true,
    this.allowedTools,
    this.temperature = 0.7,
    this.topP,
    this.topK,
  });

  /// Create a new context with updated parameters
  LlmContext copyWith({
    Map<String, dynamic>? contextInfo,
    String? systemInstructions,
    int? maxInputTokens,
    int? maxOutputTokens,
    Duration? timeout,
    bool? allowToolUse,
    List<String>? allowedTools,
    double? temperature,
    double? topP,
    int? topK,
  }) {
    return LlmContext(
      contextInfo: contextInfo ?? this.contextInfo,
      systemInstructions: systemInstructions ?? this.systemInstructions,
      maxInputTokens: maxInputTokens ?? this.maxInputTokens,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      timeout: timeout ?? this.timeout,
      allowToolUse: allowToolUse ?? this.allowToolUse,
      allowedTools: allowedTools ?? this.allowedTools,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
    );
  }

  /// Convert the LLM context to a JSON representation
  Map<String, dynamic> toJson() {
    return {
      'contextInfo': contextInfo,
      'systemInstructions': systemInstructions,
      'maxInputTokens': maxInputTokens,
      'maxOutputTokens': maxOutputTokens,
      'timeout': timeout?.inMilliseconds,
      'allowToolUse': allowToolUse,
      'allowedTools': allowedTools,
      'temperature': temperature,
      'topP': topP,
      'topK': topK,
    };
  }

  /// Create a context optimized for creative generation
  static LlmContext creative() {
    return LlmContext(
      temperature: 0.9,
      systemInstructions: 'You are a creative assistant that provides imaginative and original responses.',
    );
  }

  /// Create a context optimized for factual responses
  static LlmContext factual() {
    return LlmContext(
      temperature: 0.2,
      systemInstructions: 'You are a precise assistant that provides factual and accurate information. Avoid speculation.',
    );
  }

  /// Create a context optimized for code generation
  static LlmContext code() {
    return LlmContext(
      temperature: 0.3,
      systemInstructions: 'You are a programming assistant. Provide working, well-commented code that follows best practices.',
    );
  }

  /// Create a context optimized for concise responses
  static LlmContext concise() {
    return LlmContext(
      temperature: 0.4,
      systemInstructions: 'You are a concise assistant. Provide brief, accurate responses without unnecessary details.',
      maxOutputTokens: 300,
    );
  }

  /// Merge two contexts, with the second context taking precedence
  static LlmContext merge(LlmContext base, LlmContext overlay) {
    // Merge context info
    final mergedInfo = Map<String, dynamic>.from(base.contextInfo);
    mergedInfo.addAll(overlay.contextInfo);

    return LlmContext(
      contextInfo: mergedInfo,
      systemInstructions: overlay.systemInstructions ?? base.systemInstructions,
      maxInputTokens: overlay.maxInputTokens ?? base.maxInputTokens,
      maxOutputTokens: overlay.maxOutputTokens ?? base.maxOutputTokens,
      timeout: overlay.timeout ?? base.timeout,
      allowToolUse: overlay.allowToolUse,
      allowedTools: overlay.allowedTools ?? base.allowedTools,
      temperature: overlay.temperature,
      topP: overlay.topP ?? base.topP,
      topK: overlay.topK ?? base.topK,
    );
  }

  /// Convert to parameter map for LLM provider
  Map<String, dynamic> toProviderParams(String provider) {
    final params = <String, dynamic>{
      'temperature': temperature,
    };

    // Add optional parameters if present
    if (systemInstructions != null) {
      params['system'] = systemInstructions;
    }

    if (maxOutputTokens != null) {
      params['max_tokens'] = maxOutputTokens;
    }

    if (topP != null) {
      params['top_p'] = topP;
    }

    if (topK != null) {
      params['top_k'] = topK;
    }

    // Provider-specific parameter formatting
    switch (provider.toLowerCase()) {
      case 'openai':
      case 'gpt':
      // OpenAI specific adjustments
        if (systemInstructions != null) {
          params.remove('system');
          params['system_instructions'] = systemInstructions;
        }
        break;

      case 'claude':
      case 'anthropic':
      // Claude specific adjustments
        break;

      default:
      // Default format
        break;
    }

    return params;
  }
}