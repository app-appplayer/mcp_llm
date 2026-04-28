/// LLM Port Adapter - Bridges mcp_llm with mcp_bundle Contract Layer.
///
/// This adapter implements mcp_bundle.LlmPort and converts between
/// the Contract Layer types and mcp_llm's internal types.
library;

import 'package:mcp_bundle/ports.dart' as bundle;
import 'package:uuid/uuid.dart';

import '../core/llm_interface.dart';
import '../core/llm_client.dart';
import '../core/models.dart' as models;
import '../chat/message.dart' as chat;

const _uuid = Uuid();

/// Adapter that implements mcp_bundle's LlmPort using mcp_llm's LlmProvider.
///
/// Converts between Contract Layer types (mcp_bundle) and mcp_llm internal types.
///
/// Usage:
/// ```dart
/// import 'package:mcp_llm/mcp_llm.dart';
/// import 'package:mcp_bundle/ports.dart' as bundle;
///
/// // Create LLM provider
/// final provider = ClaudeProvider(...);
/// await provider.initialize(config);
///
/// // Create adapter implementing bundle.LlmPort
/// final llmPort = LlmPortAdapter(provider);
///
/// // Use with knowledge packages
/// final runtime = SkillRuntime(llm: llmPort, ...);
/// ```
class LlmPortAdapter implements bundle.LlmPort {
  /// The underlying mcp_llm provider.
  final LlmProvider _provider;

  /// Optional capability override.
  final bundle.LlmCapabilities? _capabilitiesOverride;

  /// Create an adapter wrapping a LlmProvider.
  ///
  /// [provider] - The mcp_llm provider to wrap.
  /// [capabilities] - Optional capability override. If not provided,
  ///   infers capabilities from provider methods.
  LlmPortAdapter(
    this._provider, {
    bundle.LlmCapabilities? capabilities,
  }) : _capabilitiesOverride = capabilities;

  /// Create an adapter from an LlmClient.
  ///
  /// This extracts the underlying LlmProvider from the client.
  factory LlmPortAdapter.fromClient(
    LlmClient client, {
    bundle.LlmCapabilities? capabilities,
  }) {
    return LlmPortAdapter(
      client.llmProvider,
      capabilities: capabilities,
    );
  }

  @override
  bundle.LlmCapabilities get capabilities =>
      _capabilitiesOverride ?? const bundle.LlmCapabilities.full();

  @override
  Future<bool> isAvailable() async => true;

  @override
  bool hasCapability(String capability) {
    switch (capability) {
      case 'completion':
        return capabilities.completion;
      case 'streaming':
        return capabilities.streaming;
      case 'embedding':
        return capabilities.embedding;
      case 'toolCalling':
        return capabilities.toolCalling;
      case 'vision':
        return capabilities.vision;
      case 'audio':
        return capabilities.audio;
      case 'rag':
        return capabilities.rag;
      default:
        return false;
    }
  }

  @override
  Future<bundle.LlmResponse> complete(bundle.LlmRequest request) async {
    // Convert bundle request to mcp_llm internal request
    final internalRequest = _convertToInternalRequest(request);

    // Call provider with internal types
    final internalResponse = await _provider.complete(internalRequest);

    // Convert internal response to bundle response
    return _convertToBundleResponse(internalResponse);
  }

  @override
  Stream<bundle.LlmChunk> completeStream(bundle.LlmRequest request) async* {
    // Check streaming capability
    if (!capabilities.streaming) {
      throw UnsupportedError('Streaming is not supported by this adapter');
    }

    // Convert bundle request to mcp_llm internal request
    final internalRequest = _convertToInternalRequest(request);

    // Stream from provider with internal types
    await for (final chunk in _provider.streamComplete(internalRequest)) {
      // Convert each chunk to bundle chunk
      yield _convertToBundleChunk(chunk);
    }
  }

  @override
  Future<List<double>> embed(String text) {
    // Check embedding capability
    if (!capabilities.embedding) {
      throw UnsupportedError('Embedding is not supported by this adapter');
    }
    return _provider.getEmbeddings(text);
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    return Future.wait(texts.map(embed));
  }

  @override
  Future<double> similarity(String text1, String text2) async {
    final emb1 = await embed(text1);
    final emb2 = await embed(text2);
    return bundle.cosineSimilarity(emb1, emb2);
  }

  @override
  Future<bundle.LlmResponse> completeWithContext(
    bundle.LlmRequest request,
    bundle.ContextBundle context,
  ) async {
    if (!capabilities.rag) {
      throw UnsupportedError('RAG is not supported by this adapter');
    }

    // Build context-augmented prompt from the ContextBundle (capability
    // ports redesign: `entities`/`views` replace legacy `facts`/`summaries`).
    final contextText = StringBuffer();
    for (final entity in context.entities) {
      contextText.writeln('- ${entity.name}: ${entity.attributes}');
    }
    for (final view in context.views) {
      contextText.writeln(view.content);
    }

    // Prepend context to the request prompt
    final augmentedPrompt =
        'Context:\n$contextText\n---\n${request.effectivePrompt}';

    final augmentedRequest = bundle.LlmRequest(
      prompt: augmentedPrompt,
      systemPrompt: request.systemPrompt,
      model: request.model,
      temperature: request.temperature,
      maxTokens: request.maxTokens,
      responseFormat: request.responseFormat,
      tools: request.tools,
      options: request.options,
    );

    return complete(augmentedRequest);
  }

  @override
  Future<bundle.LlmResponse> completeWithTools(
    bundle.LlmRequest request,
    List<bundle.LlmTool> tools,
  ) async {
    // Convert tools to internal format and add to request parameters
    final internalTools = tools.map(_convertToInternalTool).toList();

    // Create request with tools in parameters
    final internalRequest = _convertToInternalRequest(request);
    final requestWithTools = internalRequest.copyWith(
      parameters: {
        ...internalRequest.parameters,
        'tools': internalTools.map((t) => t.toJson()).toList(),
      },
    );

    // Call provider
    final internalResponse = await _provider.complete(requestWithTools);

    // Convert response
    return _convertToBundleResponse(internalResponse);
  }

  // ============================================
  // Type Conversion: bundle → mcp_llm internal
  // ============================================

  /// Convert bundle.LlmRequest to mcp_llm internal LlmRequest.
  models.LlmRequest _convertToInternalRequest(bundle.LlmRequest request) {
    // Build history from messages
    final history = <chat.LlmMessage>[];

    if (request.messages != null) {
      for (final msg in request.messages!) {
        history.add(_convertToInternalMessage(msg));
      }
    }

    // Build parameters map
    final parameters = <String, dynamic>{
      if (request.temperature != null) 'temperature': request.temperature,
      if (request.maxTokens != null) 'max_tokens': request.maxTokens,
      if (request.model != null) 'model': request.model,
      if (request.systemPrompt != null) 'system': request.systemPrompt,
      if (request.responseFormat != null) 'response_format': request.responseFormat,
      if (request.tools != null)
        'tools': request.tools!.map(_convertToInternalTool).map((t) => t.toJson()).toList(),
      ...?request.options,
    };

    return models.LlmRequest(
      prompt: request.effectivePrompt,
      history: history,
      parameters: parameters,
    );
  }

  /// Convert bundle.LlmMessage to mcp_llm internal LlmMessage.
  chat.LlmMessage _convertToInternalMessage(bundle.LlmMessage msg) {
    return chat.LlmMessage(
      role: msg.role,
      content: msg.content,
    );
  }

  /// Convert bundle.LlmTool to mcp_llm internal LlmTool.
  models.LlmTool _convertToInternalTool(bundle.LlmTool tool) {
    return models.LlmTool(
      name: tool.name,
      description: tool.description,
      inputSchema: tool.parameters,
    );
  }

  // ============================================
  // Type Conversion: mcp_llm internal → bundle
  // ============================================

  /// Convert mcp_llm internal LlmResponse to bundle.LlmResponse.
  bundle.LlmResponse _convertToBundleResponse(models.LlmResponse response) {
    // Convert tool calls if present
    List<bundle.LlmToolCall>? bundleToolCalls;
    if (response.toolCalls != null && response.toolCalls!.isNotEmpty) {
      bundleToolCalls = response.toolCalls!
          .map(_convertToBundleToolCall)
          .toList();
    }

    // Extract usage from metadata if present
    bundle.LlmUsage? usage;
    if (response.metadata.containsKey('usage')) {
      final usageData = response.metadata['usage'] as Map<String, dynamic>?;
      if (usageData != null) {
        usage = bundle.LlmUsage(
          inputTokens: usageData['inputTokens'] as int? ??
              usageData['prompt_tokens'] as int? ?? 0,
          outputTokens: usageData['outputTokens'] as int? ??
              usageData['completion_tokens'] as int? ?? 0,
        );
      }
    }

    return bundle.LlmResponse(
      content: response.text,
      usage: usage,
      model: response.metadata['model'] as String?,
      finishReason: response.metadata['finish_reason'] as String? ??
          response.metadata['stop_reason'] as String?,
      toolCalls: bundleToolCalls,
      metadata: response.metadata,
    );
  }

  /// Convert mcp_llm internal LlmToolCall to bundle.LlmToolCall.
  bundle.LlmToolCall _convertToBundleToolCall(models.LlmToolCall toolCall) {
    return bundle.LlmToolCall(
      id: toolCall.id ?? 'call_${_uuid.v4()}',
      name: toolCall.name,
      arguments: toolCall.arguments,
    );
  }

  /// Convert mcp_llm internal LlmResponseChunk to bundle.LlmChunk.
  bundle.LlmChunk _convertToBundleChunk(models.LlmResponseChunk chunk) {
    // Convert first tool call if present
    bundle.LlmToolCall? toolCall;
    if (chunk.toolCalls != null && chunk.toolCalls!.isNotEmpty) {
      toolCall = _convertToBundleToolCall(chunk.toolCalls!.first);
    }

    return bundle.LlmChunk(
      content: chunk.textChunk,
      isDone: chunk.isDone,
      toolCall: toolCall,
    );
  }
}

/// Factory for creating LlmPortAdapter instances.
///
/// Provides convenient methods to create adapters with common configurations.
class LlmPortAdapterFactory {
  /// Create an adapter with minimal capabilities (completion only).
  static LlmPortAdapter minimal(LlmProvider provider) {
    return LlmPortAdapter(
      provider,
      capabilities: const bundle.LlmCapabilities.minimal(),
    );
  }

  /// Create an adapter with full capabilities.
  static LlmPortAdapter full(LlmProvider provider) {
    return LlmPortAdapter(
      provider,
      capabilities: const bundle.LlmCapabilities.full(),
    );
  }

  /// Create an adapter with custom capabilities.
  static LlmPortAdapter withCapabilities(
    LlmProvider provider, {
    bool streaming = true,
    bool embedding = true,
    bool toolCalling = true,
    bool vision = false,
    bool audio = false,
    bool rag = false,
    int? maxContextTokens,
    int? maxOutputTokens,
  }) {
    return LlmPortAdapter(
      provider,
      capabilities: bundle.LlmCapabilities(
        streaming: streaming,
        embedding: embedding,
        toolCalling: toolCalling,
        vision: vision,
        audio: audio,
        rag: rag,
        maxContextTokens: maxContextTokens,
        maxOutputTokens: maxOutputTokens,
      ),
    );
  }
}
