import '../core/models.dart';
import 'plugin_interface.dart';
import '../utils/logger.dart';

/// Base implementation of a tool plugin
abstract class BaseToolPlugin implements ToolPlugin {
  @override
  final String name;

  @override
  final String version;

  @override
  final String description;

  /// Tool definition schema
  final Map<String, dynamic> _inputSchema;

  /// Logger instance
  final Logger _logger = Logger('mcp_llm.tool_plugin');

  /// Plugin configuration
  Map<String, dynamic> _config = {};

  /// Plugin initialization state
  bool _isInitialized = false;

  BaseToolPlugin({
    required this.name,
    required this.version,
    required this.description,
    required Map<String, dynamic> inputSchema,
  }) : _inputSchema = inputSchema;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _config = Map<String, dynamic>.from(config);
    _isInitialized = true;

    await onInitialize(config);

    _logger.debug('Initialized tool plugin: $name v$version');
  }

  /// Hook for plugin-specific initialization logic
  Future<void> onInitialize(Map<String, dynamic> config) async {
    // Override in subclass if needed
  }

  @override
  Future<void> shutdown() async {
    await onShutdown();
    _isInitialized = false;

    _logger.debug('Shut down tool plugin: $name');
  }

  /// Hook for plugin-specific shutdown logic
  Future<void> onShutdown() async {
    // Override in subclass if needed
  }

  @override
  LlmTool getToolDefinition() {
    _checkInitialized();

    return LlmTool(
      name: name,
      description: description,
      inputSchema: _inputSchema,
    );
  }

  @override
  Future<LlmCallToolResult> execute(Map<String, dynamic> arguments) async {
    _checkInitialized();

    try {
      _logger.debug('Executing tool plugin: $name with arguments: $arguments');

      // Validate arguments against schema
      _validateArguments(arguments);

      // Execute the tool
      final result = await onExecute(arguments);

      _logger.debug('Tool plugin execution completed: $name');
      return result;
    } catch (e, stackTrace) {
      _logger.error('Error executing tool plugin $name: $e');
      _logger.debug('Stack trace: $stackTrace');

      return LlmCallToolResult(
        [LlmTextContent(text: 'Error executing tool: $e')],
        isError: true,
      );
    }
  }

  /// Hook for plugin-specific execution logic
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> arguments);

  /// Check if the plugin is initialized
  void _checkInitialized() {
    if (!_isInitialized) {
      throw StateError('Tool plugin $name is not initialized');
    }
  }

  /// Get a configured value with fallback
  T getConfigValue<T>(String key, T defaultValue) {
    return _config.containsKey(key) ? _config[key] as T : defaultValue;
  }

  /// Validate arguments against the schema
  void _validateArguments(Map<String, dynamic> arguments) {
    // Basic validation for required properties
    if (_inputSchema.containsKey('properties') && _inputSchema.containsKey('required')) {
      final required = _inputSchema['required'] as List<dynamic>;

      for (final requiredProp in required) {
        final prop = requiredProp as String;
        if (!arguments.containsKey(prop)) {
          throw ArgumentError('Missing required argument: $prop');
        }
      }
    }

    // Additional validation would be implemented here
    // (type checking, etc.)
  }
}

/// A simple example tool plugin implementation
class SampleEchoToolPlugin extends BaseToolPlugin {
  SampleEchoToolPlugin() : super(
    name: 'echo',
    version: '1.0.0',
    description: 'Echoes back the input with optional transformation',
    inputSchema: {
      'type': 'object',
      'properties': {
        'message': {
          'type': 'string',
          'description': 'Message to echo back'
        },
        'uppercase': {
          'type': 'boolean',
          'description': 'Whether to convert to uppercase',
          'default': false
        }
      },
      'required': ['message']
    },
  );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> arguments) async {
    final message = arguments['message'] as String;
    final uppercase = arguments['uppercase'] as bool? ?? false;

    final result = uppercase ? message.toUpperCase() : message;

    return LlmCallToolResult([
      LlmTextContent(text: result),
    ]);
  }
}