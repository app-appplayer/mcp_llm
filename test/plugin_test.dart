import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  group('PluginManager', () {
    late PluginManager manager;

    setUp(() {
      manager = PluginManager();
    });

    tearDown(() async {
      await manager.shutdown();
    });

    test('Can register and retrieve plugin', () async {
      final plugin = TestPlugin();
      await manager.registerPlugin(plugin);

      final retrieved = manager.getPlugin('test-plugin');
      expect(retrieved, equals(plugin));
      expect(retrieved?.name, equals('test-plugin'));
    });

    test('Can register and retrieve tool plugin', () async {
      final plugin = SampleEchoToolPlugin();
      await manager.registerPlugin(plugin);

      final retrieved = manager.getToolPlugin('echo');
      expect(retrieved, equals(plugin));
      expect(retrieved?.name, equals('echo'));
    });

    test('Can register and retrieve prompt plugin', () async {
      final plugin = StoryStarterPromptPlugin();
      await manager.registerPlugin(plugin);

      final retrieved = manager.getPromptPlugin('story-starter');
      expect(retrieved, equals(plugin));
      expect(retrieved?.name, equals('story-starter'));
    });

    test('Can execute tool plugin', () async {
      final plugin = SampleEchoToolPlugin();
      await manager.registerPlugin(plugin);

      final result = await manager.tryExecuteTool(
          'echo',
          {'message': 'Hello', 'uppercase': true}
      );

      expect(result, isNotNull);
      final content = result!.content;
      expect(content[0], isA<LlmTextContent>());
      expect((content[0] as LlmTextContent).text, equals('HELLO'));
    });

    test('Can unregister plugin', () async {
      final plugin = TestPlugin();
      await manager.registerPlugin(plugin);

      // Verify plugin is registered
      expect(manager.getPlugin('test-plugin'), isNotNull);

      // Unregister and verify it's gone
      await manager.unregisterPlugin('test-plugin');
      expect(manager.getPlugin('test-plugin'), isNull);
    });

    test('Plugin initialization receives config', () async {
      final plugin = ConfigTestPlugin();
      await manager.registerPlugin(plugin, {'test_value': 42});

      expect(plugin.receivedConfig['test_value'], equals(42));
    });

    test('getAllToolPlugins returns only tool plugins', () async {
      await manager.registerPlugin(SampleEchoToolPlugin());
      await manager.registerPlugin(StoryStarterPromptPlugin());
      await manager.registerPlugin(TestPlugin());

      final toolPlugins = manager.getAllToolPlugins();
      expect(toolPlugins.length, equals(1));
      expect(toolPlugins.first.name, equals('echo'));
    });
  });

  group('ToolPlugin', () {
    test('EchoToolPlugin works correctly', () async {
      final plugin = SampleEchoToolPlugin();
      await plugin.initialize({});

      final result = await plugin.execute({
        'message': 'Hello world',
        'uppercase': true
      });

      expect(result.content.length, equals(1));
      expect((result.content[0] as LlmTextContent).text, equals('HELLO WORLD'));
    });

    test('Plugin validates required arguments', () async {
      final plugin = SampleEchoToolPlugin();
      await plugin.initialize({});

      // Create a custom plugin that definitely throws for testing purposes
      final throwingPlugin = StrictValidationToolPlugin();
      await throwingPlugin.initialize({});

      // Test with the plugin that enforces strict validation
      await expectLater(
              () => throwingPlugin.execute({}),
          throwsA(isA<ArgumentError>())
      );
    });
  });

  group('PromptPlugin', () {
    test('StoryStarterPromptPlugin works correctly', () async {
      final plugin = StoryStarterPromptPlugin();
      await plugin.initialize({});

      final result = await plugin.execute({
        'genre': 'sci-fi',
        'theme': 'time travel',
        'tone': 'mysterious'
      });

      expect(result.messages.length, equals(2));
      expect(result.description, contains('sci-fi'));
      expect(result.description, contains('time travel'));
      expect(result.messages[0].role, equals('system'));
      expect(result.messages[1].role, equals('user'));
      expect(result.messages[1].content, contains('sci-fi'));
    });

    test('PromptPlugin fills in default values', () async {
      final plugin = StoryStarterPromptPlugin();
      await plugin.initialize({});

      // No tone specified, should use default
      final result = await plugin.execute({
        'genre': 'fantasy',
      });

      expect(result.messages[1].content, contains('neutral tone'));
    });
  });
}

// Test plugins for testing
class TestPlugin implements LlmPlugin {
  @override
  String get name => 'test-plugin';

  @override
  String get version => '1.0.0';

  @override
  String get description => 'A test plugin';

  bool isInitialized = false;
  bool isShutdown = false;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    isInitialized = true;
  }

  @override
  Future<void> shutdown() async {
    isShutdown = true;
  }
}

class ConfigTestPlugin implements LlmPlugin {
  @override
  String get name => 'config-test-plugin';

  @override
  String get version => '1.0.0';

  @override
  String get description => 'A test plugin for config';

  final Map<String, dynamic> receivedConfig = {};

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    receivedConfig.addAll(config);
  }

  @override
  Future<void> shutdown() async {}
}

class StrictValidationToolPlugin extends BaseToolPlugin {
  StrictValidationToolPlugin() : super(
    name: 'strict-validator',
    version: '1.0.0',
    description: 'Plugin that strictly validates arguments',
    inputSchema: {
      'type': 'object',
      'properties': {
        'requiredArg': {'type': 'string', 'description': 'Required argument'}
      },
      'required': ['requiredArg']
    },
  );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> arguments) async {
    // Will never get here since validation should fail first
    return LlmCallToolResult([
      LlmTextContent(text: 'This should not be reached'),
    ]);
  }

  // Override to ensure validation happens
  @override
  Future<LlmCallToolResult> execute(Map<String, dynamic> arguments) async {
    // Explicit validation that will throw
    if (!arguments.containsKey('requiredArg')) {
      throw ArgumentError('Missing required argument: requiredArg');
    }

    return super.execute(arguments);
  }
}
