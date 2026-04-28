import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  group('GeminiProvider', () {
    group('GeminiProviderFactory', () {
      late GeminiProviderFactory factory;

      setUp(() {
        factory = GeminiProviderFactory();
      });

      test('has correct name', () {
        expect(factory.name, equals('gemini'));
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
        expect(provider, isA<GeminiProvider>());
      });

      test('uses default model when not specified', () {
        final config = LlmConfiguration(apiKey: 'test-api-key');
        final provider = factory.createProvider(config) as GeminiProvider;
        expect(provider.model, equals(GeminiProvider.defaultModel));
      });

      test('uses custom model when specified', () {
        final config = LlmConfiguration(
          apiKey: 'test-api-key',
          model: 'gemini-1.5-flash-latest',
        );
        final provider = factory.createProvider(config) as GeminiProvider;
        expect(provider.model, equals('gemini-1.5-flash-latest'));
      });
    });

    group('GeminiProvider', () {
      late GeminiProvider provider;

      setUp(() {
        provider = GeminiProvider(
          apiKey: 'test-api-key',
          model: 'gemini-1.5-pro-latest',
          config: LlmConfiguration(apiKey: 'test-api-key'),
        );
      });

      test('has correct default base URL', () {
        expect(GeminiProvider.defaultBaseUrl, equals('https://generativelanguage.googleapis.com/v1beta'));
      });

      test('has correct embedding model', () {
        expect(GeminiProvider.embeddingModel, equals('text-embedding-004'));
      });

      test('has model aliases', () {
        expect(GeminiProvider.modelAliases, isNotEmpty);
        expect(GeminiProvider.modelAliases['gemini-pro'], equals('gemini-1.0-pro'));
        expect(GeminiProvider.modelAliases['gemini-1.5-pro'], equals('gemini-1.5-pro-latest'));
      });

      test('hasToolCallMetadata detects tool call start', () {
        final metadata = {'tool_call_start': true, 'tool_name': 'test'};
        expect(provider.hasToolCallMetadata(metadata), isTrue);
      });

      test('hasToolCallMetadata detects finish reason tool_calls', () {
        final metadata = {'finish_reason': 'tool_calls'};
        expect(provider.hasToolCallMetadata(metadata), isTrue);
      });

      test('hasToolCallMetadata detects functionCall', () {
        final metadata = {'functionCall': {'name': 'test', 'args': {}}};
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

      test('extractToolCallFromMetadata extracts from functionCall', () {
        final metadata = {
          'functionCall': {'name': 'test_func', 'args': {'param': 'value'}},
        };
        final toolCall = provider.extractToolCallFromMetadata(metadata);
        expect(toolCall, isNotNull);
        expect(toolCall!.name, equals('test_func'));
        expect(toolCall.arguments['param'], equals('value'));
      });

      test('standardizeMetadata adds expects_tool_result', () {
        final metadata = {'finish_reason': 'tool_calls'};
        final standardized = provider.standardizeMetadata(metadata);
        expect(standardized['expects_tool_result'], isTrue);
      });
    });
  });
}
