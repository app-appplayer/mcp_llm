import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  group('CohereProvider', () {
    group('CohereProviderFactory', () {
      late CohereProviderFactory factory;

      setUp(() {
        factory = CohereProviderFactory();
      });

      test('has correct name', () {
        expect(factory.name, equals('cohere'));
      });

      test('has expected capabilities', () {
        expect(factory.capabilities, contains(LlmCapability.completion));
        expect(factory.capabilities, contains(LlmCapability.streaming));
        expect(factory.capabilities, contains(LlmCapability.embeddings));
        expect(factory.capabilities, contains(LlmCapability.toolUse));
        expect(factory.capabilities, contains(LlmCapability.functionCalling));
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
        expect(provider, isA<CohereProvider>());
      });

      test('uses default model when not specified', () {
        final config = LlmConfiguration(apiKey: 'test-api-key');
        final provider = factory.createProvider(config) as CohereProvider;
        expect(provider.model, equals(CohereProvider.defaultModel));
      });

      test('uses custom model when specified', () {
        final config = LlmConfiguration(
          apiKey: 'test-api-key',
          model: 'command-r',
        );
        final provider = factory.createProvider(config) as CohereProvider;
        expect(provider.model, equals('command-r'));
      });
    });

    group('CohereProvider', () {
      late CohereProvider provider;

      setUp(() {
        provider = CohereProvider(
          apiKey: 'test-api-key',
          model: 'command-r-plus',
          config: LlmConfiguration(apiKey: 'test-api-key'),
        );
      });

      test('has correct default base URL', () {
        expect(CohereProvider.defaultBaseUrl, equals('https://api.cohere.ai/v1'));
      });

      test('has correct embedding model', () {
        expect(CohereProvider.embeddingModel, equals('embed-english-v3.0'));
      });

      test('has model aliases', () {
        expect(CohereProvider.modelAliases, isNotEmpty);
        expect(CohereProvider.modelAliases['command'], equals('command'));
        expect(CohereProvider.modelAliases['command-r'], equals('command-r'));
        expect(CohereProvider.modelAliases['command-r-plus'], equals('command-r-plus'));
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
