// test/provider_test.dart
import 'package:mcp_llm/mcp_llm.dart';
import 'package:test/test.dart';
import 'dart:io';

void main() {
  group('OpenAI Provider Factory', () {
    late OpenAiProviderFactory factory;

    setUp(() {
      factory = OpenAiProviderFactory();
    });

    test('provides correct name', () {
      expect(factory.name, equals('openai'));
    });

    test('provides correct capabilities', () {
      expect(factory.capabilities, contains(LlmCapability.completion));
      expect(factory.capabilities, contains(LlmCapability.streaming));
      expect(factory.capabilities, contains(LlmCapability.embeddings));
      expect(factory.capabilities, contains(LlmCapability.toolUse));
      expect(factory.capabilities, contains(LlmCapability.imageUnderstanding));
    });

    // OpenAI Provider Factory
    test('throws error when API key is missing', () {
      final config = LlmConfiguration(apiKey: null);

      expect(() => factory.createProvider(config), throwsStateError);
    });

    test('creates provider with correct configuration', () {
      final config = LlmConfiguration(
        apiKey: 'test_api_key',
        model: 'gpt-4',
        baseUrl: 'https://custom-api.example.com',
        options: {'temperature': 0.7},
      );

      final provider = factory.createProvider(config) as OpenAiProvider;

      expect(provider.apiKey, equals('test_api_key'));
      expect(provider.model, equals('gpt-4'));
      expect(provider.baseUrl, equals('https://custom-api.example.com'));
    });
  });

  group('Claude Provider Factory', () {
    late ClaudeProviderFactory factory;

    setUp(() {
      factory = ClaudeProviderFactory();
    });

    test('provides correct name', () {
      expect(factory.name, equals('claude'));
    });

    test('provides correct capabilities', () {
      expect(factory.capabilities, contains(LlmCapability.completion));
      expect(factory.capabilities, contains(LlmCapability.streaming));
      expect(factory.capabilities, contains(LlmCapability.embeddings));
      expect(factory.capabilities, contains(LlmCapability.imageUnderstanding));
    });

    // Claude Provider Factory
    test('throws error when API key is missing', () {
      final config = LlmConfiguration(apiKey: null);

      expect(() => factory.createProvider(config), throwsStateError);
    });


    test('creates provider with correct configuration', () {
      final config = LlmConfiguration(
        apiKey: 'test_api_key',
        model: 'claude-3-opus',
        baseUrl: 'https://custom-api.example.com',
      );

      final provider = factory.createProvider(config) as ClaudeProvider;

      expect(provider.apiKey, equals('test_api_key'));
      expect(provider.model, equals('claude-3-opus'));
      expect(provider.baseUrl, equals('https://custom-api.example.com'));
    });
  });

  group('Together Provider Factory', () {
    late TogetherProviderFactory factory;

    setUp(() {
      factory = TogetherProviderFactory();
    });

    test('provides correct name', () {
      expect(factory.name, equals('together'));
    });

    test('provides correct capabilities', () {
      expect(factory.capabilities, contains(LlmCapability.completion));
      expect(factory.capabilities, contains(LlmCapability.streaming));
      expect(factory.capabilities, contains(LlmCapability.embeddings));
    });

  // Together Provider Factory
    test('throws error when API key is missing', () {
      final config = LlmConfiguration(apiKey: null);

      expect(() => factory.createProvider(config), throwsStateError);
    });


    test('creates provider with correct configuration', () {
      final config = LlmConfiguration(
        apiKey: 'test_api_key',
        model: 'mistralai/Mixtral-8x7B-Instruct-v0.1',
      );

      final provider = factory.createProvider(config) as TogetherProvider;

      expect(provider.apiKey, equals('test_api_key'));
      expect(provider.model, equals('mistralai/Mixtral-8x7B-Instruct-v0.1'));
    });
  });

  group('Custom Provider', () {
    test('can be extended for custom implementations', () {
      final customProvider = TestCustomProvider(name: 'test_custom');

      expect(customProvider.name, equals('test_custom'));

      // 메서드 구현 테스트
      expect(customProvider.getCompletionEndpoint(), equals('https://api.custom.provider/completion'));
      expect(customProvider.getEmbeddingEndpoint(), equals('https://api.custom.provider/embeddings'));
    });
  });
}

/// Test Custom Provider Implementation
class TestCustomProvider extends CustomLlmProvider {
  TestCustomProvider({required String name}) : super(name: name);

  @override
  Future<Map<String, dynamic>> executeRequest(
      Map<String, dynamic> requestData,
      String endpoint,
      Map<String, String> headers,
      ) async {
    return {
      'text': 'Custom provider response',
      'metadata': {'custom': true},
    };
  }

  @override
  Stream<dynamic> executeStreamingRequest(
      Map<String, dynamic> requestData,
      String endpoint,
      Map<String, String> headers,
      ) async* {
    yield {'text': 'Streaming 1', 'done': false};
    yield {'text': 'Streaming 2', 'done': false};
    yield {'text': 'Streaming 3', 'done': true};
  }

  @override
  String getCompletionEndpoint() {
    return 'https://api.custom.provider/completion';
  }

  @override
  String getEmbeddingEndpoint() {
    return 'https://api.custom.provider/embeddings';
  }

  @override
  Future<void> close() async {

  }

  @override
  Future<List<double>> getEmbeddings(String text) async {

    return List.generate(10, (i) => i / 10.0);
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {

  }
}