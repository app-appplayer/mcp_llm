import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  group('GroqProvider', () {
    group('GroqProviderFactory', () {
      late GroqProviderFactory factory;

      setUp(() {
        factory = GroqProviderFactory();
      });

      test('has correct name', () {
        expect(factory.name, equals('groq'));
      });

      test('has expected capabilities', () {
        expect(factory.capabilities, contains(LlmCapability.completion));
        expect(factory.capabilities, contains(LlmCapability.streaming));
        expect(factory.capabilities, contains(LlmCapability.toolUse));
        expect(factory.capabilities, contains(LlmCapability.functionCalling));
        expect(factory.capabilities.contains(LlmCapability.embeddings), isFalse);
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
        expect(provider, isA<GroqProvider>());
      });

      test('uses default model when not specified', () {
        final config = LlmConfiguration(apiKey: 'test-api-key');
        final provider = factory.createProvider(config) as GroqProvider;
        expect(provider.model, equals(GroqProvider.defaultModel));
      });

      test('uses custom model when specified', () {
        final config = LlmConfiguration(
          apiKey: 'test-api-key',
          model: 'mixtral-8x7b-32768',
        );
        final provider = factory.createProvider(config) as GroqProvider;
        expect(provider.model, equals('mixtral-8x7b-32768'));
      });
    });

    group('GroqProvider', () {
      late GroqProvider provider;

      setUp(() {
        provider = GroqProvider(
          apiKey: 'test-api-key',
          model: 'llama-3.1-70b-versatile',
          config: LlmConfiguration(apiKey: 'test-api-key'),
        );
      });

      test('getEmbeddings throws UnimplementedError', () {
        expect(
          () => provider.getEmbeddings('test text'),
          throwsA(isA<UnimplementedError>()),
        );
      });

      test('has correct default base URL', () {
        expect(GroqProvider.defaultBaseUrl, equals('https://api.groq.com/openai/v1'));
      });

      test('has model aliases', () {
        expect(GroqProvider.modelAliases, isNotEmpty);
        expect(GroqProvider.modelAliases['llama-3.1-70b'], equals('llama-3.1-70b-versatile'));
        expect(GroqProvider.modelAliases['mixtral'], equals('mixtral-8x7b-32768'));
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
