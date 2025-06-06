import 'dart:io';

/// Utilities for test configuration
class TestConfig {
  /// Check if OpenAI API key is available
  static bool get hasOpenAiKey =>
      Platform.environment.containsKey('OPENAI_API_KEY');

  /// Check if Claude API key is available
  static bool get hasClaudeKey =>
      Platform.environment.containsKey('ANTHROPIC_API_KEY');

  /// Check if Together API key is available
  static bool get hasTogetherKey =>
      Platform.environment.containsKey('TOGETHER_API_KEY');

  /// Print available keys for testing
  static void printAPIKeyStatus() {
    print('API keys for testing:');
    print('OpenAI API Key: ${hasOpenAiKey ? 'Available ✓' : 'Missing ✗'}');
    print('Claude API Key: ${hasClaudeKey ? 'Available ✓' : 'Missing ✗'}');
    print('Together API Key: ${hasTogetherKey ? 'Available ✓' : 'Missing ✗'}');
  }

  /// Check if integration tests can be run (at least one key available)
  static bool get canRunIntegrationTests =>
      hasOpenAiKey || hasClaudeKey || hasTogetherKey;

  /// Build text to explain why a test is skipped
  static String getSkipReason(String providerName) {
    return 'Skipping $providerName test: API key not available. '
        'Set the appropriate environment variable to run this test.';
  }
}

// Use this in your test files to tag integration tests:
// @Tags(['integration'])
//
// Example:
// @Tags(['integration', 'openai'])
// void main() {
//   // Test code
// }