import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  group('MistralProvider', () {
    group('MistralProviderFactory', () {
      late MistralProviderFactory factory;

      setUp(() {
        factory = MistralProviderFactory();
      });

      test('has correct name', () {
        expect(factory.name, equals('mistral'));
      });

      test('has expected capabilities', () {
        expect(factory.capabilities, contains(LlmCapability.completion));
        expect(factory.capabilities, contains(LlmCapability.streaming));
        expect(factory.capabilities, contains(LlmCapability.embeddings));
        expect(factory.capabilities, contains(LlmCapability.toolUse));
        expect(factory.capabilities, contains(LlmCapability.functionCalling));
        expect(factory.capabilities, contains(LlmCapability.imageUnderstanding));
      });

      test('throws error when API key is missing', () {
        final config = LlmConfiguration(apiKey: null);
        expect(
          () => factory.createProvider(config),
          throwsA(isA<StateError>()),
        );
      });

      test('throws error when API key is empty', () {
        final config = LlmConfiguration(apiKey: '');
        expect(
          () => factory.createProvider(config),
          throwsA(isA<StateError>()),
        );
      });

      test('creates provider with valid API key', () {
        final config = LlmConfiguration(apiKey: 'test-api-key');
        final provider = factory.createProvider(config);
        expect(provider, isA<MistralProvider>());
      });

      test('uses default model when not specified', () {
        final config = LlmConfiguration(apiKey: 'test-api-key');
        final provider = factory.createProvider(config) as MistralProvider;
        expect(provider.model, equals(MistralProvider.defaultModel));
      });

      test('uses custom model when specified', () {
        final config = LlmConfiguration(
          apiKey: 'test-api-key',
          model: 'mistral-small-latest',
        );
        final provider = factory.createProvider(config) as MistralProvider;
        expect(provider.model, equals('mistral-small-latest'));
      });
    });

    group('MistralProvider', () {
      late MistralProvider provider;

      setUp(() {
        provider = MistralProvider(
          apiKey: 'test-api-key',
          model: 'mistral-large-latest',
          config: LlmConfiguration(apiKey: 'test-api-key'),
        );
      });

      test('has correct default base URL', () {
        expect(MistralProvider.defaultBaseUrl, equals('https://api.mistral.ai/v1'));
      });

      test('has correct embedding model', () {
        expect(MistralProvider.embeddingModel, equals('mistral-embed'));
      });

      test('has model aliases', () {
        expect(MistralProvider.modelAliases, isNotEmpty);
        expect(MistralProvider.modelAliases['mistral-large'], equals('mistral-large-latest'));
        expect(MistralProvider.modelAliases['codestral'], equals('codestral-latest'));
      });

      test('hasToolCallMetadata detects tool call start', () {
        final metadata = {'tool_call_start': true, 'tool_name': 'test'};
        expect(provider.hasToolCallMetadata(metadata), isTrue);
      });

      test('hasToolCallMetadata detects finish reason tool_calls', () {
        final metadata = {'finish_reason': 'tool_calls'};
        expect(provider.hasToolCallMetadata(metadata), isTrue);
      });

      test('hasToolCallMetadata returns false for empty metadata', () {
        final metadata = <String, dynamic>{};
        expect(provider.hasToolCallMetadata(metadata), isFalse);
      });

      test('extractToolCallFromMetadata extracts tool call', () {
        final metadata = {
          'tool_call_start': true,
          'tool_name': 'test_tool',
          'tool_call_id': 'call_123',
        };
        final toolCall = provider.extractToolCallFromMetadata(metadata);
        expect(toolCall, isNotNull);
        expect(toolCall!.name, equals('test_tool'));
        expect(toolCall.id, equals('call_123'));
      });

      test('standardizeMetadata adds expects_tool_result', () {
        final metadata = {'finish_reason': 'tool_calls'};
        final standardized = provider.standardizeMetadata(metadata);
        expect(standardized['expects_tool_result'], isTrue);
      });
    });
  });
}
