import '../core/models.dart';
import '../providers/provider.dart';

/// Base interface for all MCPLlm plugins
abstract class LlmPlugin {
  /// Plugin name
  String get name;

  /// Plugin version
  String get version;

  /// Plugin description
  String get description;

  /// Initialize the plugin with configuration
  Future<void> initialize(Map<String, dynamic> config);

  /// Shutdown and clean up resources
  Future<void> shutdown();
}

/// Interface for tool plugins that provide tool functionality
abstract class ToolPlugin extends LlmPlugin {
  /// Get the tool definition
  Tool getToolDefinition();

  /// Execute the tool with the given arguments
  Future<CallToolResult> execute(Map<String, dynamic> arguments);
}

/// Interface for prompt plugins that provide prompt templates
abstract class PromptPlugin extends LlmPlugin {
  /// Get the prompt definition
  Prompt getPromptDefinition();

  /// Execute the prompt with the given arguments
  Future<GetPromptResult> execute(Map<String, dynamic> arguments);
}

/// Interface for embedding plugins that provide embedding functionality
abstract class EmbeddingPlugin extends LlmPlugin {
  /// Generate embeddings for the given text
  Future<List<double>> embed(String text);
}

/// Interface for preprocessor plugins that transform inputs
abstract class PreprocessorPlugin extends LlmPlugin {
  /// Process the input text before sending to LLM
  Future<String> preprocess(String input, Map<String, dynamic> context);
}

/// Interface for postprocessor plugins that transform LLM outputs
abstract class PostprocessorPlugin extends LlmPlugin {
  /// Process the output text from the LLM
  Future<String> postprocess(String output, Map<String, dynamic> context);
}

/// Interface for provider plugins that implement new LLM providers
abstract class ProviderPlugin extends LlmPlugin {
  /// Get the LLM provider factory
  LlmProviderFactory getProviderFactory();
}

/// Manager interface for plugins
abstract class IPluginManager {
  /// Register a plugin
  Future<void> registerPlugin(LlmPlugin plugin, [Map<String, dynamic>? config]);

  /// Get a plugin by name
  LlmPlugin? getPlugin(String name);

  /// Get a tool plugin by name
  ToolPlugin? getToolPlugin(String name);

  /// Get a prompt plugin by name
  PromptPlugin? getPromptPlugin(String name);

  /// Get an embedding plugin by name
  EmbeddingPlugin? getEmbeddingPlugin(String name);

  /// Get all tool plugins
  List<ToolPlugin> getAllToolPlugins();

  /// Get all prompt plugins
  List<PromptPlugin> getAllPromptPlugins();

  /// Unregister a plugin
  Future<void> unregisterPlugin(String name);

  /// Shutdown all plugins
  Future<void> shutdown();
}
