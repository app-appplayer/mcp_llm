import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_bundle/ports.dart' as bundle;

import 'test_utils/mock_provider.dart';

void main() {
  group('LlmPortAdapter', () {
    late MockLlmProvider mockProvider;
    late LlmPortAdapter adapter;

    setUp(() {
      mockProvider = MockLlmProvider(
        config: LlmConfiguration(model: 'test-model'),
      );
      adapter = LlmPortAdapter(mockProvider);
    });

    group('constructor', () {
      test('creates adapter with default full capabilities', () {
        final adapter = LlmPortAdapter(mockProvider);

        expect(adapter.capabilities.completion, isTrue);
        expect(adapter.capabilities.streaming, isTrue);
        expect(adapter.capabilities.embedding, isTrue);
        expect(adapter.capabilities.toolCalling, isTrue);
      });

      test('creates adapter with custom capabilities', () {
        final adapter = LlmPortAdapter(
          mockProvider,
          capabilities: const bundle.LlmCapabilities(
            streaming: false,
            embedding: false,
            toolCalling: false,
          ),
        );

        expect(adapter.capabilities.completion, isTrue);
        expect(adapter.capabilities.streaming, isFalse);
        expect(adapter.capabilities.embedding, isFalse);
        expect(adapter.capabilities.toolCalling, isFalse);
      });

      test('creates adapter from LlmClient', () {
        final client = LlmClient(llmProvider: mockProvider);
        final adapter = LlmPortAdapter.fromClient(client);

        expect(adapter.capabilities.completion, isTrue);
      });
    });

    group('isAvailable', () {
      test('returns true when provider exists', () async {
        final result = await adapter.isAvailable();
        expect(result, isTrue);
      });
    });

    group('hasCapability', () {
      test('returns true for supported capabilities', () {
        // Default adapter uses .full() — all capabilities enabled
        expect(adapter.hasCapability('completion'), isTrue);
        expect(adapter.hasCapability('streaming'), isTrue);
        expect(adapter.hasCapability('embedding'), isTrue);
        expect(adapter.hasCapability('toolCalling'), isTrue);
        expect(adapter.hasCapability('vision'), isTrue);
        expect(adapter.hasCapability('audio'), isTrue);
        expect(adapter.hasCapability('rag'), isTrue);
      });

      test('returns false for unsupported capabilities', () {
        expect(adapter.hasCapability('unknown'), isFalse);
      });

      test('respects custom capability configuration', () {
        final limitedAdapter = LlmPortAdapter(
          mockProvider,
          capabilities: const bundle.LlmCapabilities.minimal(),
        );

        expect(limitedAdapter.hasCapability('completion'), isTrue);
        expect(limitedAdapter.hasCapability('streaming'), isFalse);
        expect(limitedAdapter.hasCapability('embedding'), isFalse);
      });
    });

    group('complete', () {
      test('converts request and response correctly', () async {
        final request = bundle.LlmRequest.simple(
          'What is the capital of France?',
        );

        final response = await adapter.complete(request);

        expect(response.content, contains('Paris'));
        expect(response.content, isA<String>());
      });

      test('handles request with messages', () async {
        final request = bundle.LlmRequest.conversation([
          bundle.LlmMessage.user('Hello'),
          bundle.LlmMessage.assistant('Hi there!'),
          bundle.LlmMessage.user('What is 2+2?'),
        ]);

        final response = await adapter.complete(request);

        expect(response.content, isNotEmpty);
      });

      test('includes metadata in response', () async {
        final request = bundle.LlmRequest.simple('Test prompt');

        final response = await adapter.complete(request);

        expect(response.metadata, isNotNull);
        expect(response.metadata?['provider'], equals('mock'));
      });
    });

    group('completeStream', () {
      test('streams response chunks correctly', () async {
        final request = bundle.LlmRequest.simple(
          'Count from 1 to 5',
        );

        final chunks = <bundle.LlmChunk>[];
        await for (final chunk in adapter.completeStream(request)) {
          chunks.add(chunk);
        }

        expect(chunks, isNotEmpty);
        expect(chunks.last.isDone, isTrue);

        final fullContent = chunks.map((c) => c.content ?? '').join();
        expect(fullContent, contains('1'));
        expect(fullContent, contains('5'));
      });

      test('throws when streaming not supported', () async {
        final limitedAdapter = LlmPortAdapter(
          mockProvider,
          capabilities: const bundle.LlmCapabilities.minimal(),
        );

        final request = bundle.LlmRequest.simple('Test');

        expect(
          () => limitedAdapter.completeStream(request).first,
          throwsA(isA<UnsupportedError>()),
        );
      });
    });

    group('embed', () {
      test('generates embeddings', () async {
        final embeddings = await adapter.embed('test text');

        expect(embeddings, isNotEmpty);
        expect(embeddings.length, equals(128));
        expect(embeddings, everyElement(isA<double>()));
      });

      test('generates consistent embeddings for same text', () async {
        final emb1 = await adapter.embed('hello world');
        final emb2 = await adapter.embed('hello world');

        expect(emb1, equals(emb2));
      });

      test('generates different embeddings for different text', () async {
        final emb1 = await adapter.embed('hello');
        final emb2 = await adapter.embed('world');

        expect(emb1, isNot(equals(emb2)));
      });

      test('throws when embedding not supported', () async {
        final limitedAdapter = LlmPortAdapter(
          mockProvider,
          capabilities: const bundle.LlmCapabilities.minimal(),
        );

        expect(
          () => limitedAdapter.embed('test'),
          throwsA(isA<UnsupportedError>()),
        );
      });
    });

    group('embedBatch', () {
      test('generates batch embeddings', () async {
        final texts = ['hello', 'world', 'test'];
        final embeddings = await adapter.embedBatch(texts);

        expect(embeddings.length, equals(3));
        expect(embeddings[0], isNot(equals(embeddings[1])));
      });
    });

    group('similarity', () {
      test('computes similarity between texts', () async {
        final score = await adapter.similarity('hello world', 'hello world');

        expect(score, closeTo(1.0, 0.001));
      });

      test('returns lower similarity for different texts', () async {
        final sameScore =
            await adapter.similarity('hello world', 'hello world');
        final diffScore =
            await adapter.similarity('hello', 'completely different text');

        // Same text should have high similarity
        expect(sameScore, greaterThanOrEqualTo(0.9));
      });
    });

    group('type conversion', () {
      test('converts LlmResponse.text to LlmResponse.content', () async {
        final request = bundle.LlmRequest.simple('Test');
        final response = await adapter.complete(request);

        expect(response.content, isA<String>());
        expect(response.content, isNotEmpty);
      });

      test('converts LlmResponseChunk.textChunk to LlmChunk.content', () async {
        final request = bundle.LlmRequest.simple('Count from 1 to 5');

        await for (final chunk in adapter.completeStream(request)) {
          if (chunk.content != null) {
            expect(chunk.content, isA<String>());
          }
        }
      });
    });
  });

  group('LlmPortAdapterFactory', () {
    late MockLlmProvider mockProvider;

    setUp(() {
      mockProvider = MockLlmProvider(
        config: LlmConfiguration(model: 'test-model'),
      );
    });

    test('minimal() creates adapter with minimal capabilities', () {
      final adapter = LlmPortAdapterFactory.minimal(mockProvider);

      expect(adapter.capabilities.completion, isTrue);
      expect(adapter.capabilities.streaming, isFalse);
      expect(adapter.capabilities.embedding, isFalse);
      expect(adapter.capabilities.toolCalling, isFalse);
    });

    test('full() creates adapter with full capabilities', () {
      final adapter = LlmPortAdapterFactory.full(mockProvider);

      expect(adapter.capabilities.completion, isTrue);
      expect(adapter.capabilities.streaming, isTrue);
      expect(adapter.capabilities.embedding, isTrue);
      expect(adapter.capabilities.toolCalling, isTrue);
    });

    test('withCapabilities() creates adapter with custom capabilities', () {
      final adapter = LlmPortAdapterFactory.withCapabilities(
        mockProvider,
        streaming: true,
        embedding: false,
        toolCalling: true,
        vision: true,
        maxContextTokens: 100000,
      );

      expect(adapter.capabilities.streaming, isTrue);
      expect(adapter.capabilities.embedding, isFalse);
      expect(adapter.capabilities.toolCalling, isTrue);
      expect(adapter.capabilities.vision, isTrue);
      expect(adapter.capabilities.maxContextTokens, equals(100000));
    });
  });

  group('Contract Layer Integration', () {
    test('adapter implements bundle.LlmPort interface', () {
      final mockProvider = MockLlmProvider(
        config: LlmConfiguration(model: 'test-model'),
      );
      final adapter = LlmPortAdapter(mockProvider);

      expect(adapter, isA<bundle.LlmPort>());
    });

    test('can be used where bundle.LlmPort is expected', () async {
      final mockProvider = MockLlmProvider(
        config: LlmConfiguration(model: 'test-model'),
      );
      final adapter = LlmPortAdapter(mockProvider);

      Future<String> useLlmPort(bundle.LlmPort llm) async {
        final response = await llm.complete(
          bundle.LlmRequest.simple('Test'),
        );
        return response.content;
      }

      final result = await useLlmPort(adapter);
      expect(result, isNotEmpty);
    });
  });
}
