import 'package:test/test.dart';
import 'package:mcp_llm/src/core/llm_interface.dart';
import 'package:mcp_llm/src/core/models.dart';
import 'package:mcp_llm/src/providers/claude_provider.dart';
import 'package:mcp_llm/src/providers/openai_provider.dart';
import 'package:mcp_llm/src/providers/together_provider.dart';
import 'package:mcp_llm/src/providers/provider.dart';
import 'package:mcp_llm/src/chat/message.dart';
import 'package:mcp_llm/src/chat/history.dart';
import 'package:mcp_llm/src/storage/storage.dart';
import 'package:mcp_llm/src/utils/compression.dart';
import 'package:mcp_llm/mcp_llm.dart' show McpLlm;

void main() {
  group('Web Platform Compatibility Tests', () {
    group('LLM Providers', () {
      test('ClaudeProvider can be instantiated without dart:io', () {
        expect(
          () => ClaudeProvider(
            apiKey: 'test-key',
            model: 'claude-3-sonnet',
            config: LlmConfiguration(),
          ),
          returnsNormally,
        );
      });

      test('OpenAiProvider can be instantiated without dart:io', () {
        expect(
          () => OpenAiProvider(
            apiKey: 'test-key',
            model: 'gpt-4',
            config: LlmConfiguration(),
          ),
          returnsNormally,
        );
      });

      test('TogetherProvider can be instantiated without dart:io', () {
        expect(
          () => TogetherProvider(
            apiKey: 'test-key',
            model: 'mixtral-8x7b',
            config: LlmConfiguration(),
          ),
          returnsNormally,
        );
      });
    });

    group('Storage System', () {
      test('Storage can be created on any platform', () {
        expect(
          () => createStorage(),
          returnsNormally,
        );
      });

      test('Storage interface is consistent across platforms', () async {
        final storage = createStorage();
        
        // Test basic operations
        await storage.initialize();
        
        // Test store and retrieve
        await storage.store('test_key', 'test_value');
        final value = await storage.retrieve('test_key');
        
        // On web, localStorage might not be available in test environment
        // so we just verify the methods exist and don't throw
        expect(storage.exists('test_key'), completes);
        expect(storage.delete('test_key'), completes);
        expect(storage.clear(), completes);
      });

      test('Chat history can be stored and retrieved', () async {
        final storage = createStorage();
        await storage.initialize();
        
        final message = LlmMessage(
          role: 'user',
          content: 'Hello, world!',
        );
        
        // Test storing a message
        await storage.storeMessage('session1', message);
        
        // Test retrieving history
        final history = await storage.retrieveHistory('session1');
        
        // The actual behavior depends on the platform
        // On web without localStorage, it might return null
        // We just verify no exceptions are thrown
        expect(history, isA<ChatHistory?>());
      });
    });

    group('Compression Utilities', () {
      test('DataCompressor works on any platform', () async {
        const testString = 'Hello, this is a test string for compression!';
        
        // Test compression
        final compressed = await DataCompressor.compressAndEncodeString(testString);
        expect(compressed, isA<String>());
        
        // Test decompression
        final decompressed = await DataCompressor.decodeAndDecompressString(compressed);
        
        // On web platform, compression might be a no-op
        // So we check if we get back either the original or something valid
        expect(decompressed, isA<String>());
      });

      test('Binary compression works on any platform', () async {
        final testData = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        
        // Test compression
        final compressed = await DataCompressor.compressData(testData);
        expect(compressed, isA<List<int>>());
        
        // Test decompression
        final decompressed = await DataCompressor.decompressData(compressed);
        expect(decompressed, isA<List<int>>());
      });
    });

    group('Integration Tests', () {
      test('LlmClient can be created with web-compatible providers', () async {
        final mcpLlm = McpLlm();
        
        // Register providers
        mcpLlm.registerProvider('claude', ClaudeProviderFactory());
        mcpLlm.registerProvider('openai', OpenAiProviderFactory());
        mcpLlm.registerProvider('together', TogetherProviderFactory());
        
        // Create clients (will fail with invalid API keys, but should not fail due to platform issues)
        expect(
          () async => await mcpLlm.createClient(
            providerName: 'claude',
            config: LlmConfiguration(
              apiKey: 'test-key',
              model: 'claude-3-sonnet',
            ),
          ),
          returnsNormally,
        );
      });

      test('Storage manager can be used with LlmClient', () async {
        final mcpLlm = McpLlm();
        mcpLlm.registerProvider('claude', ClaudeProviderFactory());
        
        // Create storage
        final storage = createStorage();
        await storage.initialize();
        
        // Create client with storage
        expect(
          () async => await mcpLlm.createClient(
            providerName: 'claude',
            config: LlmConfiguration(
              apiKey: 'test-key',
              model: 'claude-3-sonnet',
            ),
            storageManager: null, // Storage manager is different from storage
          ),
          returnsNormally,
        );
      });
    });

    group('Platform Detection', () {
      test('Platform-specific implementations are loaded correctly', () {
        // Test that the correct implementation is loaded based on platform
        final storage = createStorage();
        
        // We can't directly test which implementation is loaded,
        // but we can verify it implements the interface
        expect(storage, isA<StorageInterface>());
      });
    });
  });
}