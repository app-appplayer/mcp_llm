import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  group('VertexAiProvider', () {
    group('VertexAiProviderFactory', () {
      late VertexAiProviderFactory factory;

      setUp(() {
        factory = VertexAiProviderFactory();
      });

      test('has correct name', () {
        expect(factory.name, equals('vertex_ai'));
      });

      test('has expected capabilities', () {
        expect(factory.capabilities, contains(LlmCapability.completion));
        expect(factory.capabilities, contains(LlmCapability.streaming));
        expect(factory.capabilities, contains(LlmCapability.embeddings));
        expect(factory.capabilities, contains(LlmCapability.toolUse));
        expect(factory.capabilities, contains(LlmCapability.functionCalling));
        expect(factory.capabilities, contains(LlmCapability.imageUnderstanding));
      });

      test('throws error when project_id is missing', () {
        final config = LlmConfiguration(
          apiKey: 'test-token',
          options: {},
        );
        expect(
          () => factory.createProvider(config),
          throwsA(isA<StateError>()),
        );
      });

      test('creates provider with valid config', () {
        final config = LlmConfiguration(
          apiKey: 'test-token',
          options: {'project_id': 'test-project'},
        );
        final provider = factory.createProvider(config);
        expect(provider, isA<VertexAiProvider>());
      });

      test('uses default location when not specified', () {
        final config = LlmConfiguration(
          apiKey: 'test-token',
          options: {'project_id': 'test-project'},
        );
        final provider = factory.createProvider(config) as VertexAiProvider;
        expect(provider.location, equals(VertexAiProvider.defaultLocation));
      });

      test('uses custom location when specified', () {
        final config = LlmConfiguration(
          apiKey: 'test-token',
          options: {
            'project_id': 'test-project',
            'location': 'europe-west1',
          },
        );
        final provider = factory.createProvider(config) as VertexAiProvider;
        expect(provider.location, equals('europe-west1'));
      });

      test('uses default model when not specified', () {
        final config = LlmConfiguration(
          apiKey: 'test-token',
          options: {'project_id': 'test-project'},
        );
        final provider = factory.createProvider(config) as VertexAiProvider;
        expect(provider.model, equals(VertexAiProvider.defaultModel));
      });
    });

    group('VertexAiProvider', () {
      late VertexAiProvider provider;

      setUp(() {
        provider = VertexAiProvider(
          accessToken: 'test-token',
          projectId: 'test-project',
          location: 'us-central1',
          model: 'gemini-1.5-pro-001',
          config: LlmConfiguration(apiKey: 'test-token'),
        );
      });

      test('has correct default location', () {
        expect(VertexAiProvider.defaultLocation, equals('us-central1'));
      });

      test('has correct embedding model', () {
        expect(VertexAiProvider.embeddingModel, equals('textembedding-gecko@003'));
      });

      test('has model aliases', () {
        expect(VertexAiProvider.modelAliases, isNotEmpty);
        expect(VertexAiProvider.modelAliases['gemini-pro'], equals('gemini-1.0-pro-001'));
        expect(VertexAiProvider.modelAliases['gemini-1.5-pro'], equals('gemini-1.5-pro-001'));
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
