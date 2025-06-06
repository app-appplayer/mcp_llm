import '../../mcp_llm.dart';

/// Registry that dynamically registers and manages LLM providers
class LlmRegistry {
  // Singleton code removed

  // Registered provider map
  final Map<String, LlmProviderFactory> _providers = {};

  // Regular constructor
  LlmRegistry();

  /// Register new LLM provider
  void registerProvider(String name, LlmProviderFactory factory) {
    _providers[name] = factory;
    // Output log (receive Logger as instance or create when needed)
    final logger = Logger('mcp_llm.llm_registry');
    logger.info('LLM provider registered: $name');
  }

  /// Get provider factory by name
  LlmProviderFactory? getProviderFactory(String providerName) {
    return _providers[providerName];
  }

  /// Get all registered provider names
  List<String> getAvailableProviders() {
    return _providers.keys.toList();
  }

  /// Filter providers that support specific capability
  List<String> getProvidersWithCapability(LlmCapability capability) {
    return _providers.entries
        .where((entry) => entry.value.capabilities.contains(capability))
        .map((entry) => entry.key)
        .toList();
  }

  /// Clear all registered providers (mainly for testing)
  void clear() {
    _providers.clear();
  }
}
