import 'dart:math';

import 'package:mcp_llm/mcp_llm.dart';

/// Test Provider Factory that doesn't require API keys
class MockProviderFactory implements LlmProviderFactory {
  @override
  String get name => 'mock';

  @override
  Set<LlmCapability> get capabilities => {
    LlmCapability.completion,
    LlmCapability.streaming,
    LlmCapability.embeddings,
    LlmCapability.toolUse,
  };

  @override
  LlmInterface createProvider(LlmConfiguration config) {
    return MockLlmProvider(config: config);
  }
}

/// Mock LLM implementation for testing
class MockLlmProvider implements LlmInterface {
  final LlmConfiguration config;

  /// Create a new mock provider
  MockLlmProvider({required this.config});

  @override
  Future<void> close() async {
    // No resources to clean up
  }

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    // Simulate network delay
    await Future.delayed(Duration(milliseconds: 100));

    // Generate predictable response based on prompt
    final prompt = request.prompt.toLowerCase();
    String response;

    if (prompt.contains('capital') && prompt.contains('france')) {
      response = 'The capital of France is Paris.';
    } else if (prompt.contains('count') && prompt.contains('1 to 5')) {
      response = 'Here I count: 1, 2, 3, 4, 5.';
    } else {
      response = 'I am a mock LLM provider responding to: "${request.prompt}"';
    }

    return LlmResponse(
      text: response,
      metadata: {
        'model': config.model ?? 'mock-model',
        'provider': 'mock',
      },
    );
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    // Simulate network delay
    await Future.delayed(Duration(milliseconds: 50));

    // Generate predictable embedding
    final hash = text.hashCode;
    final random = Random(hash);

    // Generate 128-dimension vector
    return List.generate(128, (i) => random.nextDouble() * 2 - 1);
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    // Nothing to initialize
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    // Simulate network delay
    await Future.delayed(Duration(milliseconds: 50));

    final prompt = request.prompt.toLowerCase();

    if (prompt.contains('count') && prompt.contains('1 to 5')) {
      yield LlmResponseChunk(textChunk: 'Here I count: ', isDone: false);
      await Future.delayed(Duration(milliseconds: 50));
      yield LlmResponseChunk(textChunk: '1, ', isDone: false);
      await Future.delayed(Duration(milliseconds: 50));
      yield LlmResponseChunk(textChunk: '2, ', isDone: false);
      await Future.delayed(Duration(milliseconds: 50));
      yield LlmResponseChunk(textChunk: '3, ', isDone: false);
      await Future.delayed(Duration(milliseconds: 50));
      yield LlmResponseChunk(textChunk: '4, ', isDone: false);
      await Future.delayed(Duration(milliseconds: 50));
      yield LlmResponseChunk(textChunk: '5.', isDone: true);
    } else {
      final response = 'I am a mock LLM provider responding to: "${request.prompt}"';

      // Split response into chunks
      final words = response.split(' ');
      for (int i = 0; i < words.length; i++) {
        final isDone = i == words.length - 1;
        yield LlmResponseChunk(
          textChunk: words[i] + (isDone ? '' : ' '),
          isDone: isDone,
        );
        await Future.delayed(Duration(milliseconds: 20));
      }
    }
  }

  @override
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) {
    // TODO: implement extractToolCallFromMetadata
    throw UnimplementedError();
  }

  @override
  bool hasToolCallMetadata(Map<String, dynamic> metadata) {
    // TODO: implement hasToolCallMetadata
    throw UnimplementedError();
  }

  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) {
    // TODO: implement standardizeMetadata
    throw UnimplementedError();
  }
}