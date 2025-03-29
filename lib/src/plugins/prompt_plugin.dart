import '../../mcp_llm.dart';
import '../core/models.dart';
import 'plugin_interface.dart';
import '../utils/logger.dart';

/// Base implementation of a prompt plugin
abstract class BasePromptPlugin implements PromptPlugin {
  @override
  final String name;

  @override
  final String version;

  @override
  final String description;

  /// Arguments definition for the prompt
  final List<PromptArgument> _arguments;

  /// Logger instance
  final Logger _logger = Logger.getLogger('mcp_llm.prompt_plugin');

  /// Plugin configuration
  Map<String, dynamic> _config = {};

  /// Plugin initialization state
  bool _isInitialized = false;

  BasePromptPlugin({
    required this.name,
    required this.version,
    required this.description,
    required List<PromptArgument> arguments,
  }) : _arguments = arguments;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _config = Map<String, dynamic>.from(config);
    _isInitialized = true;

    await onInitialize(config);

    _logger.debug('Initialized prompt plugin: $name v$version');
  }

  /// Hook for plugin-specific initialization logic
  Future<void> onInitialize(Map<String, dynamic> config) async {
    // Override in subclass if needed
  }

  @override
  Future<void> shutdown() async {
    await onShutdown();
    _isInitialized = false;

    _logger.debug('Shut down prompt plugin: $name');
  }

  /// Hook for plugin-specific shutdown logic
  Future<void> onShutdown() async {
    // Override in subclass if needed
  }

  @override
  Prompt getPromptDefinition() {
    _checkInitialized();

    return Prompt(
      name: name,
      description: description,
      arguments: _arguments,
    );
  }

  @override
  Future<GetPromptResult> execute(Map<String, dynamic> arguments) async {
    _checkInitialized();

    try {
      _logger.debug('Executing prompt plugin: $name with arguments: $arguments');

      // Validate arguments
      _validateArguments(arguments);

      // Fill in default values for missing arguments
      final processedArgs = _processArguments(arguments);

      // Execute the prompt
      final result = await onExecute(processedArgs);

      _logger.debug('Prompt plugin execution completed: $name');
      return result;
    } catch (e, stackTrace) {
      _logger.error('Error executing prompt plugin $name: $e');
      _logger.debug('Stack trace: $stackTrace');

      throw Exception('Error executing prompt: $e');
    }
  }

  /// Hook for plugin-specific execution logic
  Future<GetPromptResult> onExecute(Map<String, dynamic> arguments);

  /// Check if the plugin is initialized
  void _checkInitialized() {
    if (!_isInitialized) {
      throw StateError('Prompt plugin $name is not initialized');
    }
  }

  /// Get a configured value with fallback
  T getConfigValue<T>(String key, T defaultValue) {
    return _config.containsKey(key) ? _config[key] as T : defaultValue;
  }

  /// Validate arguments against the defined arguments
  void _validateArguments(Map<String, dynamic> arguments) {
    // Check required arguments
    for (final arg in _arguments) {
      if (arg.required && !arguments.containsKey(arg.name)) {
        throw ArgumentError('Missing required argument: ${arg.name}');
      }
    }
  }

  /// Process arguments, applying defaults where needed
  Map<String, dynamic> _processArguments(Map<String, dynamic> arguments) {
    final processedArgs = Map<String, dynamic>.from(arguments);

    // Apply defaults for missing arguments
    for (final arg in _arguments) {
      if (!processedArgs.containsKey(arg.name) && arg.defaultValue != null) {
        processedArgs[arg.name] = arg.defaultValue;
      }
    }

    return processedArgs;
  }
}

/// Example prompt plugin for generating creative story starters
class StoryStarterPromptPlugin extends BasePromptPlugin {
  StoryStarterPromptPlugin() : super(
    name: 'story-starter',
    version: '1.0.0',
    description: 'Generates creative story starters based on genre and theme',
    arguments: [
      PromptArgument(
        name: 'genre',
        description: 'Genre of the story (e.g., sci-fi, fantasy, mystery)',
        required: true,
      ),
      PromptArgument(
        name: 'theme',
        description: 'Primary theme or topic for the story',
        required: false,
      ),
      PromptArgument(
        name: 'tone',
        description: 'Tone of the story (e.g., dark, humorous, whimsical)',
        required: false,
        defaultValue: 'neutral',
      ),
    ],
  );

  @override
  Future<GetPromptResult> onExecute(Map<String, dynamic> arguments) async {
    final genre = arguments['genre'] as String;
    final theme = arguments['theme'] as String?;
    final tone = arguments['tone'] as String? ?? 'neutral';

    // Build system message
    final systemMessage = Message.system(
      'You are a creative writing assistant specializing in ${genre.toLowerCase()} stories '
          'with a ${tone.toLowerCase()} tone. Your task is to create engaging story starters '
          'that will inspire writers.',
    );

    // Build user message
    String userPrompt = 'Please create a story starter for a ${genre.toLowerCase()} story';
    if (theme != null) {
      userPrompt += ' with the theme of "${theme}"';
    }
    userPrompt += ' and a ${tone.toLowerCase()} tone.';

    final userMessage = Message.user(userPrompt);

    // Create the result
    return GetPromptResult(
      description: 'A ${tone.toLowerCase()} ${genre.toLowerCase()} story starter' +
          (theme != null ? ' about ${theme.toLowerCase()}' : ''),
      messages: [systemMessage, userMessage],
    );
  }
}