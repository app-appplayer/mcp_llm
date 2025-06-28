import 'dart:io';
import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_llm/src/storage/storage.dart';
import 'package:mcp_llm/src/utils/compression.dart';

void main() {
  group('Real API Integration Tests', () {
    late String? anthropicApiKey;
    late String? openaiApiKey;

    setUpAll(() {
      // Try to get from environment variables
      anthropicApiKey = const String.fromEnvironment('ANTHROPIC_API_KEY');
      openaiApiKey = const String.fromEnvironment('OPENAI_API_KEY');
      
      // Fallback to Platform.environment if fromEnvironment doesn't work
      if (anthropicApiKey == null || anthropicApiKey!.isEmpty) {
        anthropicApiKey = Platform.environment['ANTHROPIC_API_KEY'];
      }
      if (openaiApiKey == null || openaiApiKey!.isEmpty) {
        openaiApiKey = Platform.environment['OPENAI_API_KEY'];
      }
      
      print('Claude API Key available: ${anthropicApiKey != null && anthropicApiKey!.isNotEmpty}');
      print('OpenAI API Key available: ${openaiApiKey != null && openaiApiKey!.isNotEmpty}');
    });

    test('Claude API integration test', () async {
      if (anthropicApiKey == null || anthropicApiKey!.isEmpty) {
        print('Skipping Claude test - no API key');
        return;
      }

      final mcpLlm = McpLlm();
      mcpLlm.registerProvider('claude', ClaudeProviderFactory());

      final client = await mcpLlm.createClient(
        providerName: 'claude',
        config: LlmConfiguration(
          apiKey: anthropicApiKey,
          model: 'claude-3-sonnet-20240229',
        ),
      );

      expect(client, isNotNull);

      // Test simple chat
      final response = await client.chat('Say "Hello from Claude!" and nothing else.');
      expect(response, isNotNull);
      expect(response.text, isNotEmpty);
      expect(response.text.toLowerCase(), contains('hello'));
      
      print('✅ Claude API test successful: ${response.text.trim()}');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('OpenAI API integration test', () async {
      if (openaiApiKey == null || openaiApiKey!.isEmpty) {
        print('Skipping OpenAI test - no API key');
        return;
      }

      final mcpLlm = McpLlm();
      mcpLlm.registerProvider('openai', OpenAiProviderFactory());

      final client = await mcpLlm.createClient(
        providerName: 'openai',
        config: LlmConfiguration(
          apiKey: openaiApiKey,
          model: 'gpt-3.5-turbo',
        ),
      );

      expect(client, isNotNull);

      // Test simple chat
      final response = await client.chat('Say "Hello from OpenAI!" and nothing else.');
      expect(response, isNotNull);
      expect(response.text, isNotEmpty);
      expect(response.text.toLowerCase(), contains('hello'));
      
      print('✅ OpenAI API test successful: ${response.text.trim()}');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Storage system with real data', () async {
      final storage = createStorage();
      await storage.initialize();

      // Test storing and retrieving session data
      final testSessionId = 'integration_test_${DateTime.now().millisecondsSinceEpoch}';
      
      final message = LlmMessage(
        role: 'user',
        content: 'Integration test message',
      );

      await storage.storeMessage(testSessionId, message);
      
      final history = await storage.retrieveHistory(testSessionId);
      expect(history, isNotNull);
      expect(history!.messages, hasLength(1));
      expect(history.messages.first.content, equals('Integration test message'));

      // Clean up
      await storage.deleteSession(testSessionId);
      
      print('✅ Storage integration test successful');
    });

    test('Compression system with real data', () async {
      const largeText = '''
      This is a large text document that we will use to test the compression system.
      It contains multiple sentences and paragraphs to ensure that the compression
      algorithms can properly handle real-world data. We want to verify that the
      compression and decompression cycle works correctly across all platforms,
      including web browsers where gzip compression might not be available.
      ''';

      final compressed = await DataCompressor.compressAndEncodeString(largeText);
      expect(compressed, isNotEmpty);

      final decompressed = await DataCompressor.decodeAndDecompressString(compressed);
      expect(decompressed, isNotEmpty);

      // On platforms with compression, should be smaller; on web, might be same size
      print('Original size: ${largeText.length}, Compressed: ${compressed.length}, Decompressed: ${decompressed.length}');
      
      print('✅ Compression integration test successful');
    });
  });
}