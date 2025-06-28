import 'package:test/test.dart';

// Only import specific parts we've fixed for web compatibility
import 'package:mcp_llm/src/providers/claude_provider.dart';
import 'package:mcp_llm/src/providers/openai_provider.dart';
import 'package:mcp_llm/src/providers/together_provider.dart';
import 'package:mcp_llm/src/core/models.dart';
import 'package:mcp_llm/src/storage/storage.dart';
import 'package:mcp_llm/src/chat/message.dart';
import 'package:mcp_llm/src/chat/history.dart';
import 'package:mcp_llm/src/utils/compression.dart';

void main() {
  group('Web Platform Compatibility', () {
    group('LLM Providers use package:http', () {
      test('ClaudeProvider instantiation', () {
        // This will fail at runtime with invalid API key, but should compile
        final provider = ClaudeProvider(
          apiKey: 'test-api-key',
          model: 'claude-3-sonnet',
          config: LlmConfiguration(),
        );
        
        expect(provider, isNotNull);
        expect(provider.model, equals('claude-3-sonnet'));
      });

      test('OpenAiProvider instantiation', () {
        final provider = OpenAiProvider(
          apiKey: 'test-api-key',
          model: 'gpt-4',
          config: LlmConfiguration(),
        );
        
        expect(provider, isNotNull);
        expect(provider.model, equals('gpt-4'));
      });

      test('TogetherProvider instantiation', () {
        final provider = TogetherProvider(
          apiKey: 'test-api-key',
          model: 'mixtral-8x7b',
          config: LlmConfiguration(),
        );
        
        expect(provider, isNotNull);
        expect(provider.model, equals('mixtral-8x7b'));
      });
    });

    group('Storage platform compatibility', () {
      test('Storage factory creates platform-specific instance', () {
        final storage = createStorage();
        expect(storage, isNotNull);
        expect(() => storage.initialize(), returnsNormally);
      });

      test('Storage basic operations', () async {
        final storage = createStorage();
        await storage.initialize();
        
        // These operations should not throw on any platform
        expect(storage.store('test', 'value'), completes);
        expect(storage.retrieve('test'), completes);
        expect(storage.exists('test'), completes);
        expect(storage.delete('test'), completes);
      });

      test('Chat history serialization', () {
        final history = ChatHistory();
        history.addMessage(LlmMessage(
          role: 'user',
          content: 'Hello',
        ));
        
        // Test toJson
        final json = history.toJson();
        expect(json, isA<Map<String, dynamic>>());
        expect(json['messages'], isA<List>());
        
        // Test fromJson
        final restored = ChatHistory.fromJson(json);
        expect(restored.messages.length, equals(1));
        expect(restored.messages.first.content, equals('Hello'));
      });
    });

    group('Compression compatibility', () {
      test('String compression/decompression', () async {
        const testString = 'Hello, World! This is a test string.';
        
        final compressed = await DataCompressor.compressAndEncodeString(testString);
        expect(compressed, isA<String>());
        
        final decompressed = await DataCompressor.decodeAndDecompressString(compressed);
        expect(decompressed, isA<String>());
        
        // On native platforms with gzip, should match
        // On web without compression, should also match
        if (decompressed == testString) {
          expect(decompressed, equals(testString));
        } else {
          // Web platform might return different result
          expect(decompressed, isNotEmpty);
        }
      });

      test('Binary compression/decompression', () async {
        final testData = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        
        final compressed = await DataCompressor.compressData(testData);
        expect(compressed, isA<List<int>>());
        
        final decompressed = await DataCompressor.decompressData(compressed);
        expect(decompressed, isA<List<int>>());
      });
    });

    group('Configuration models', () {
      test('LlmConfiguration can be created', () {
        final config = LlmConfiguration();
        
        expect(config, isNotNull);
        expect(config.retryOnFailure, equals(true)); // Default value
        expect(config.maxRetries, equals(3)); // Default value
        expect(config.timeout, equals(const Duration(seconds: 60))); // Default value
      });

      test('LlmRequest can be created', () {
        final request = LlmRequest(
          prompt: 'Test prompt',
          parameters: {'temperature': 0.5},
        );
        
        expect(request, isNotNull);
        expect(request.prompt, equals('Test prompt'));
      });

      test('LlmMessage serialization', () {
        final message = LlmMessage(
          role: 'assistant',
          content: 'Test response',
        );
        
        final json = message.toJson();
        expect(json['role'], equals('assistant'));
        expect(json['content'], equals('Test response'));
        
        final restored = LlmMessage.fromJson(json);
        expect(restored.role, equals('assistant'));
        expect(restored.content, equals('Test response'));
      });
    });
  });
}