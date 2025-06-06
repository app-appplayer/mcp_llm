import '../core/models.dart';
import 'plugin_interface.dart';
import '../utils/logger.dart';

/// Manages plugins for the MCPLlm system
class PluginManager implements IPluginManager {
  /// All registered plugins
  final Map<String, LlmPlugin> _plugins = {};

  /// Tool plugins
  final Map<String, ToolPlugin> _toolPlugins = {};

  /// Prompt plugins
  final Map<String, PromptPlugin> _promptPlugins = {};

  /// Resource plugins
  final Map<String, ResourcePlugin> _resourcePlugins = {};

  /// Embedding plugins
  final Map<String, EmbeddingPlugin> _embeddingPlugins = {};

  /// Preprocessor plugins
  final Map<String, PreprocessorPlugin> _preprocessorPlugins = {};

  /// Postprocessor plugins
  final Map<String, PostprocessorPlugin> _postprocessorPlugins = {};

  /// Provider plugins
  final Map<String, ProviderPlugin> _providerPlugins = {};

  /// Logger
  final Logger _logger = Logger('mcp_llm.plugin');

  /// Create a new plugin manager
  PluginManager();

  /// Register a plugin
  @override
  Future<void> registerPlugin(LlmPlugin plugin, [Map<String, dynamic>? config]) async {
    if (_plugins.containsKey(plugin.name)) {
      throw StateError('Plugin ${plugin.name} is already registered');
    }

    // Initialize the plugin
    await plugin.initialize(config ?? {});

    // Add to main registry
    _plugins[plugin.name] = plugin;

    // Add to type-specific registry
    if (plugin is ToolPlugin) {
      _toolPlugins[plugin.name] = plugin;
    } else if (plugin is PromptPlugin) {
      _promptPlugins[plugin.name] = plugin;
    } else if (plugin is ResourcePlugin) {
      _resourcePlugins[plugin.name] = plugin;
    } else if (plugin is EmbeddingPlugin) {
      _embeddingPlugins[plugin.name] = plugin;
    } else if (plugin is PreprocessorPlugin) {
      _preprocessorPlugins[plugin.name] = plugin;
    } else if (plugin is PostprocessorPlugin) {
      _postprocessorPlugins[plugin.name] = plugin;
    } else if (plugin is ProviderPlugin) {
      _providerPlugins[plugin.name] = plugin;
    }

    _logger.info('Registered plugin: ${plugin.name} v${plugin.version}');
  }

  /// Get a plugin by name
  @override
  LlmPlugin? getPlugin(String name) {
    return _plugins[name];
  }

  /// Get a tool plugin by name
  @override
  ToolPlugin? getToolPlugin(String name) {
    return _toolPlugins[name];
  }

  /// Get a prompt plugin by name
  @override
  PromptPlugin? getPromptPlugin(String name) {
    return _promptPlugins[name];
  }

  /// Get a resource plugin by name
  @override
  ResourcePlugin? getResourcePlugin(String name) {
    return _resourcePlugins[name];
  }

  /// Get an embedding plugin by name
  @override
  EmbeddingPlugin? getEmbeddingPlugin(String name) {
    return _embeddingPlugins[name];
  }

  /// Get a preprocessor plugin by name
  PreprocessorPlugin? getPreprocessorPlugin(String name) {
    return _preprocessorPlugins[name];
  }

  /// Get a postprocessor plugin by name
  PostprocessorPlugin? getPostprocessorPlugin(String name) {
    return _postprocessorPlugins[name];
  }

  /// Get a provider plugin by name
  ProviderPlugin? getProviderPlugin(String name) {
    return _providerPlugins[name];
  }

  /// Get all tool plugins
  @override
  List<ToolPlugin> getAllToolPlugins() {
    return _toolPlugins.values.toList();
  }

  /// Get all prompt plugins
  @override
  List<PromptPlugin> getAllPromptPlugins() {
    return _promptPlugins.values.toList();
  }

  /// Get all resource plugins
  @override
  List<ResourcePlugin> getAllResourcePlugins() {
    return _resourcePlugins.values.toList();
  }

  /// Get all embedding plugins
  List<EmbeddingPlugin> getAllEmbeddingPlugins() {
    return _embeddingPlugins.values.toList();
  }

  /// Get all preprocessor plugins
  List<PreprocessorPlugin> getAllPreprocessorPlugins() {
    return _preprocessorPlugins.values.toList();
  }

  /// Get all postprocessor plugins
  List<PostprocessorPlugin> getAllPostprocessorPlugins() {
    return _postprocessorPlugins.values.toList();
  }

  /// Get all provider plugins
  List<ProviderPlugin> getAllProviderPlugins() {
    return _providerPlugins.values.toList();
  }

  /// Get all registered plugin names
  List<String> getAllPluginNames() {
    return _plugins.keys.toList();
  }

  /// Check if a plugin is registered
  bool hasPlugin(String name) {
    return _plugins.containsKey(name);
  }

  /// Unregister a plugin
  @override
  Future<void> unregisterPlugin(String name) async {
    final plugin = _plugins.remove(name);

    if (plugin != null) {
      // Shutdown the plugin
      await plugin.shutdown();

      // Remove from type-specific registry
      _toolPlugins.remove(name);
      _promptPlugins.remove(name);
      _resourcePlugins.remove(name);
      _embeddingPlugins.remove(name);
      _preprocessorPlugins.remove(name);
      _postprocessorPlugins.remove(name);
      _providerPlugins.remove(name);

      _logger.info('Unregistered plugin: $name');
    } else {
      _logger.warning('Attempted to unregister non-existent plugin: $name');
    }
  }

  /// Shutdown all plugins
  @override
  Future<void> shutdown() async {
    _logger.info('Shutting down all plugins...');

    final futures = <Future<void>>[];

    for (final plugin in _plugins.values) {
      try {
        futures.add(plugin.shutdown());
      } catch (e) {
        _logger.error('Error shutting down plugin ${plugin.name}: $e');
      }
    }

    await Future.wait(futures);

    _plugins.clear();
    _toolPlugins.clear();
    _promptPlugins.clear();
    _resourcePlugins.clear();
    _embeddingPlugins.clear();
    _preprocessorPlugins.clear();
    _postprocessorPlugins.clear();
    _providerPlugins.clear();

    _logger.info('All plugins have been shut down');
  }

  /// Execute preprocessing on input text using all preprocessor plugins
  Future<String> preprocess(String input, Map<String, dynamic> context) async {
    String processedText = input;

    for (final plugin in _preprocessorPlugins.values) {
      try {
        processedText = await plugin.preprocess(processedText, context);
      } catch (e) {
        _logger.error('Error during preprocessing with ${plugin.name}: $e');
      }
    }

    return processedText;
  }

  /// Execute postprocessing on output text using all postprocessor plugins
  Future<String> postprocess(String output, Map<String, dynamic> context) async {
    String processedText = output;

    for (final plugin in _postprocessorPlugins.values) {
      try {
        processedText = await plugin.postprocess(processedText, context);
      } catch (e) {
        _logger.error('Error during postprocessing with ${plugin.name}: $e');
      }
    }

    return processedText;
  }

  /// Get plugin information for all registered plugins
  List<Map<String, dynamic>> getPluginInfo() {
    return _plugins.values.map((plugin) => {
      'name': plugin.name,
      'version': plugin.version,
      'description': plugin.description,
      'type': _getPluginType(plugin),
    }).toList();
  }

  /// Get the plugin type as a string
  String _getPluginType(LlmPlugin plugin) {
    if (plugin is ToolPlugin) return 'tool';
    if (plugin is PromptPlugin) return 'prompt';
    if (plugin is ResourcePlugin) return 'resource';
    if (plugin is EmbeddingPlugin) return 'embedding';
    if (plugin is PreprocessorPlugin) return 'preprocessor';
    if (plugin is PostprocessorPlugin) return 'postprocessor';
    if (plugin is ProviderPlugin) return 'provider';
    return 'unknown';
  }

  /// Try to execute a tool by name
  Future<LlmCallToolResult?> tryExecuteTool(String toolName, Map<String, dynamic> arguments) async {
    final plugin = getToolPlugin(toolName);
    if (plugin == null) return null;

    try {
      return await plugin.execute(arguments);
    } catch (e) {
      _logger.error('Error executing tool plugin $toolName: $e');
      return LlmCallToolResult(
        [LlmTextContent(text: 'Error executing tool: $e')],
        isError: true,
      );
    }
  }

  /// Try to execute a prompt by name
  Future<LlmGetPromptResult?> tryExecutePrompt(String promptName, Map<String, dynamic> arguments) async {
    final plugin = getPromptPlugin(promptName);
    if (plugin == null) return null;

    try {
      return await plugin.execute(arguments);
    } catch (e) {
      _logger.error('Error executing prompt plugin $promptName: $e');
      throw Exception('Error executing prompt plugin $promptName: $e');
    }
  }

  /// Try to read a resource by name
  Future<LlmReadResourceResult?> tryReadResource(String resourceName, Map<String, dynamic> parameters) async {
    final plugin = getResourcePlugin(resourceName);
    if (plugin == null) return null;

    try {
      return await plugin.read(parameters);
    } catch (e) {
      _logger.error('Error reading resource plugin $resourceName: $e');
      throw Exception('Error reading resource plugin $resourceName: $e');
    }
  }
}