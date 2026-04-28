import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  group('BedrockProvider', () {
    group('BedrockProviderFactory', () {
      late BedrockProviderFactory factory;

      setUp(() {
        factory = BedrockProviderFactory();
      });

      test('has correct name', () {
        expect(factory.name, equals('bedrock'));
      });

      test('has expected capabilities', () {
        expect(factory.capabilities, contains(LlmCapability.completion));
        expect(factory.capabilities, contains(LlmCapability.streaming));
        expect(factory.capabilities, contains(LlmCapability.embeddings));
        expect(factory.capabilities, contains(LlmCapability.toolUse));
        expect(factory.capabilities, contains(LlmCapability.functionCalling));
        expect(factory.capabilities, contains(LlmCapability.imageUnderstanding));
      });

      test('throws error when access_key_id is missing', () {
        final config = LlmConfiguration(
          options: {'secret_access_key': 'test-secret'},
        );
        expect(
          () => factory.createProvider(config),
          throwsA(isA<StateError>()),
        );
      });

      test('throws error when secret_access_key is missing', () {
        final config = LlmConfiguration(
          options: {'access_key_id': 'test-access'},
        );
        expect(
          () => factory.createProvider(config),
          throwsA(isA<StateError>()),
        );
      });

      test('creates provider with valid credentials', () {
        final config = LlmConfiguration(
          options: {
            'access_key_id': 'test-access',
            'secret_access_key': 'test-secret',
          },
        );
        final provider = factory.createProvider(config);
        expect(provider, isA<BedrockProvider>());
      });

      test('uses default region when not specified', () {
        final config = LlmConfiguration(
          options: {
            'access_key_id': 'test-access',
            'secret_access_key': 'test-secret',
          },
        );
        final provider = factory.createProvider(config) as BedrockProvider;
        expect(provider.region, equals(BedrockProvider.defaultRegion));
      });

      test('uses custom region when specified', () {
        final config = LlmConfiguration(
          options: {
            'access_key_id': 'test-access',
            'secret_access_key': 'test-secret',
            'region': 'us-west-2',
          },
        );
        final provider = factory.createProvider(config) as BedrockProvider;
        expect(provider.region, equals('us-west-2'));
      });

      test('uses default model when not specified', () {
        final config = LlmConfiguration(
          options: {
            'access_key_id': 'test-access',
            'secret_access_key': 'test-secret',
          },
        );
        final provider = factory.createProvider(config) as BedrockProvider;
        expect(provider.model, equals(BedrockProvider.defaultModel));
      });

      test('uses custom model when specified', () {
        final config = LlmConfiguration(
          model: 'anthropic.claude-3-haiku-20240307-v1:0',
          options: {
            'access_key_id': 'test-access',
            'secret_access_key': 'test-secret',
          },
        );
        final provider = factory.createProvider(config) as BedrockProvider;
        expect(provider.model, equals('anthropic.claude-3-haiku-20240307-v1:0'));
      });

      test('accepts session_token', () {
        final config = LlmConfiguration(
          options: {
            'access_key_id': 'test-access',
            'secret_access_key': 'test-secret',
            'session_token': 'test-session',
          },
        );
        final provider = factory.createProvider(config) as BedrockProvider;
        expect(provider.sessionToken, equals('test-session'));
      });
    });

    group('BedrockProvider', () {
      late BedrockProvider provider;

      setUp(() {
        provider = BedrockProvider(
          accessKeyId: 'test-access',
          secretAccessKey: 'test-secret',
          region: 'us-east-1',
          model: 'anthropic.claude-3-sonnet-20240229-v1:0',
          config: LlmConfiguration(),
        );
      });

      test('has correct default region', () {
        expect(BedrockProvider.defaultRegion, equals('us-east-1'));
      });

      test('has correct embedding model', () {
        expect(BedrockProvider.embeddingModel, equals('amazon.titan-embed-text-v1'));
      });

      test('has model aliases', () {
        expect(BedrockProvider.modelAliases, isNotEmpty);
        expect(
          BedrockProvider.modelAliases['claude-3-sonnet'],
          equals('anthropic.claude-3-sonnet-20240229-v1:0'),
        );
        expect(
          BedrockProvider.modelAliases['llama-3-70b'],
          equals('meta.llama3-70b-instruct-v1:0'),
        );
        expect(
          BedrockProvider.modelAliases['titan-text'],
          equals('amazon.titan-text-express-v1'),
        );
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
