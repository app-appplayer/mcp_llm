import 'dart:io';
import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_llm/src/storage/storage.dart';
import 'package:mcp_llm/src/utils/compression.dart';

/// Simple calculator tool plugin for testing
class CalculatorToolPlugin extends ToolPlugin {
  @override
  String get name => 'calculator';

  @override
  String get version => '1.0.0';

  @override
  String get description => 'Perform basic math calculations';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}

  @override
  Future<void> shutdown() async {}

  @override
  LlmTool getToolDefinition() {
    return LlmTool(
      name: 'calculator',
      description: 'Perform basic math calculations',
      inputSchema: {
        'type': 'object',
        'properties': {
          'expression': {
            'type': 'string',
            'description': 'Math expression to evaluate (e.g., "2 + 2")',
          },
        },
        'required': ['expression'],
      },
    );
  }

  @override
  Future<LlmCallToolResult> execute(Map<String, dynamic> arguments) async {
    final expression = arguments['expression'] as String? ?? '';
    int result = 0;

    if (expression.contains('15') && expression.contains('27')) {
      result = 42;
    } else if (expression.contains('10') && expression.contains('5')) {
      result = 15;
    }

    return LlmCallToolResult(
      [LlmTextContent(text: 'Result: $result')],
    );
  }
}

/// Get number tool plugin for multi-round testing
class GetNumberToolPlugin extends ToolPlugin {
  @override
  String get name => 'get_number';

  @override
  String get version => '1.0.0';

  @override
  String get description => 'Get a specific number';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}

  @override
  Future<void> shutdown() async {}

  @override
  LlmTool getToolDefinition() {
    return LlmTool(
      name: 'get_number',
      description: 'Get a specific number by name',
      inputSchema: {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'Name of the number (first or second)',
          },
        },
        'required': ['name'],
      },
    );
  }

  @override
  Future<LlmCallToolResult> execute(Map<String, dynamic> arguments) async {
    final name = (arguments['name'] as String? ?? '').toLowerCase();
    int value = 0;

    if (name.contains('first')) {
      value = 10;
    } else if (name.contains('second')) {
      value = 5;
    }

    return LlmCallToolResult(
      [LlmTextContent(text: 'Value: $value')],
    );
  }
}

/// Add numbers tool plugin for multi-round testing
class AddNumbersToolPlugin extends ToolPlugin {
  @override
  String get name => 'add_numbers';

  @override
  String get version => '1.0.0';

  @override
  String get description => 'Add two numbers';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}

  @override
  Future<void> shutdown() async {}

  @override
  LlmTool getToolDefinition() {
    return LlmTool(
      name: 'add_numbers',
      description: 'Add two numbers together',
      inputSchema: {
        'type': 'object',
        'properties': {
          'a': {'type': 'number', 'description': 'First number'},
          'b': {'type': 'number', 'description': 'Second number'},
        },
        'required': ['a', 'b'],
      },
    );
  }

  @override
  Future<LlmCallToolResult> execute(Map<String, dynamic> arguments) async {
    final a = (arguments['a'] as num?)?.toDouble() ?? 0;
    final b = (arguments['b'] as num?)?.toDouble() ?? 0;
    final result = a + b;

    return LlmCallToolResult(
      [LlmTextContent(text: 'Sum: $result')],
    );
  }
}

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
          model: 'claude-sonnet-4-20250514',
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

    test('Claude API tool calling test', () async {
      if (anthropicApiKey == null || anthropicApiKey!.isEmpty) {
        print('Skipping Claude tool calling test - no API key');
        return;
      }

      final mcpLlm = McpLlm();
      mcpLlm.registerProvider('claude', ClaudeProviderFactory());

      final client = await mcpLlm.createClient(
        providerName: 'claude',
        config: LlmConfiguration(
          apiKey: anthropicApiKey,
          model: 'claude-sonnet-4-20250514',
        ),
      );

      // Register calculator tool plugin
      await client.pluginManager.registerPlugin(CalculatorToolPlugin());

      // Test tool calling
      final response = await client.chat(
        'What is 15 + 27? Use the calculator tool to compute this.',
        enableTools: false,
        enablePlugins: true,
      );

      expect(response, isNotNull);
      expect(response.text, isNotEmpty);

      print('✅ Claude tool calling test successful: ${response.text.trim()}');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('OpenAI API tool calling test', () async {
      if (openaiApiKey == null || openaiApiKey!.isEmpty) {
        print('Skipping OpenAI tool calling test - no API key');
        return;
      }

      final mcpLlm = McpLlm();
      mcpLlm.registerProvider('openai', OpenAiProviderFactory());

      final client = await mcpLlm.createClient(
        providerName: 'openai',
        config: LlmConfiguration(
          apiKey: openaiApiKey,
          model: 'gpt-4o-mini',
        ),
      );

      // Register calculator tool plugin
      await client.pluginManager.registerPlugin(CalculatorToolPlugin());

      // Test tool calling
      final response = await client.chat(
        'What is 15 + 27? Use the calculator tool to compute this.',
        enableTools: false,
        enablePlugins: true,
      );

      expect(response, isNotNull);
      expect(response.text, isNotEmpty);

      print('✅ OpenAI tool calling test successful: ${response.text.trim()}');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('Claude multi-round tool calling test', () async {
      if (anthropicApiKey == null || anthropicApiKey!.isEmpty) {
        print('Skipping Claude multi-round test - no API key');
        return;
      }

      final mcpLlm = McpLlm();
      mcpLlm.registerProvider('claude', ClaudeProviderFactory());

      // Note: McpLlm.createClient doesn't support maxToolRounds parameter
      // Multi-round tool calling works because LLM can call multiple tools in sequence
      final client = await mcpLlm.createClient(
        providerName: 'claude',
        config: LlmConfiguration(
          apiKey: anthropicApiKey,
          model: 'claude-sonnet-4-20250514',
        ),
      );

      // Register tool plugins
      await client.pluginManager.registerPlugin(GetNumberToolPlugin());
      await client.pluginManager.registerPlugin(AddNumbersToolPlugin());

      // Test multi-round tool calling
      final response = await client.chat(
        'Get the first number and second number, then add them together.',
        enableTools: false,
        enablePlugins: true,
      );

      expect(response, isNotNull);
      expect(response.text, isNotEmpty);

      print('✅ Claude multi-round tool calling test successful: ${response.text.trim()}');
    }, timeout: const Timeout(Duration(seconds: 90)));

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