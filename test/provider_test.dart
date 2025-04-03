// test/provider_test.dart

import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  group('OpenAI Provider', () {
    // Other tests...

    test('OpenAI Provider Factory throws error when API key is missing', () {
      // Clear any environment variable that might exist
      // Note: This might not be possible in all environments,
      // so your test environment setup might need additional configuration

      final factory = OpenAiProviderFactory();

      // Pass a configuration with null API key
      // This should trigger the null check in the factory
      final emptyConfig = LlmConfiguration(apiKey: null);
      expect(
            () => factory.createProvider(emptyConfig),
        throwsA(isA<StateError>()),
      );
    });

    test('OpenAI Provider Factory creates provider with valid API key', () {
      final factory = OpenAiProviderFactory();
      final validConfig = LlmConfiguration(apiKey: 'test-api-key');
      final provider = factory.createProvider(validConfig);
      expect(provider, isA<OpenAiProvider>());
    });
  });

  group('Claude Provider', () {
    // Other tests...

    test('Claude Provider Factory throws error when API key is missing', () {
      final factory = ClaudeProviderFactory();

      // Pass a configuration with null API key
      final emptyConfig = LlmConfiguration(apiKey: null);
      expect(
            () => factory.createProvider(emptyConfig),
        throwsA(isA<StateError>()),
      );
    });

    test('Claude Provider Factory creates provider with valid API key', () {
      final factory = ClaudeProviderFactory();
      final validConfig = LlmConfiguration(apiKey: 'test-api-key');
      final provider = factory.createProvider(validConfig);
      expect(provider, isA<ClaudeProvider>());
    });
  });

  group('Together Provider', () {
    // Other tests...

    test('Together Provider Factory throws error when API key is missing', () {
      final factory = TogetherProviderFactory();

      // Pass a configuration with null API key
      final emptyConfig = LlmConfiguration(apiKey: null);
      expect(
            () => factory.createProvider(emptyConfig),
        throwsA(isA<StateError>()),
      );
    });

    test('Together Provider Factory creates provider with valid API key', () {
      final factory = TogetherProviderFactory();
      final validConfig = LlmConfiguration(apiKey: 'test-api-key');
      final provider = factory.createProvider(validConfig);
      expect(provider, isA<TogetherProvider>());
    });
  });
}