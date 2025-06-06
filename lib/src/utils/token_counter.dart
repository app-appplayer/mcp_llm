import '../../mcp_llm.dart';

class TokenCounter {
  final Logger _logger = Logger('mcp_llm.token_counter');

  final Map<String, double> _modelToFactor = {
    'gpt-3.5-turbo': 0.25, // Approximately 1 token per 4 characters
    'gpt-4': 0.25,
    'gpt-4o': 0.25,
    'claude-3-opus': 0.25,
    'claude-3-sonnet': 0.25,
    'claude-3-haiku': 0.25,
    'default': 0.25,
  };

  // Optional model-specific tokenizers for higher accuracy
  final Map<String, Tokenizer> _tokenizers = {};

  TokenCounter();

  /// Register a custom tokenizer for a specific model
  void registerTokenizer(String model, Tokenizer tokenizer) {
    _tokenizers[model.toLowerCase()] = tokenizer;
    _logger.debug('Registered custom tokenizer for model: $model');
  }

  /// Count tokens in text
  int countTokens(String text, String model) {
    // Use model-specific tokenizer if available
    final modelLower = model.toLowerCase();

    if (_tokenizers.containsKey(modelLower)) {
      return _tokenizers[modelLower]!.countTokens(text);
    }

    // Find appropriate factor for the model
    final factor = _getFactorForModel(model);

    // Estimate tokens considering whitespace, punctuation, etc.
    return _estimateTokens(text, factor);
  }


  int countMessageTokens(List<LlmMessage> messages, String model) {
    final factor = _getFactorForModel(model);

    int total = 0;

    // Base tokens (role separators, etc.)
    int baseTokens = 3;

    for (final message in messages) {
      // Message role tokens (around 4 tokens)
      total += 4;

      // Content tokens
      if (message.content is String) {
        total += _estimateTokens(message.content as String, factor);
      } else if (message.content is Map) {
        final contentMap = message.content as Map;
        if (contentMap['type'] == 'text') {
          total += _estimateTokens(contentMap['text'] as String, factor);
        } else if (contentMap['type'] == 'image') {
          // Images vary greatly by model and size
          // Generally images use hundreds to thousands of tokens
          total += 1000; // Default value for image tokens
        }
      }
    }

    return total + baseTokens;
  }

  double _getFactorForModel(String model) {
    final modelLower = model.toLowerCase();

    // Exact model name matching
    if (_modelToFactor.containsKey(modelLower)) {
      return _modelToFactor[modelLower]!;
    }

    // Prefix-based matching
    for (final entry in _modelToFactor.entries) {
      if (modelLower.startsWith(entry.key)) {
        return entry.value;
      }
    }

    // Return default factor
    return _modelToFactor['default']!;
  }

  int _estimateTokens(String text, double factor) {
    if (text.isEmpty) return 0;

    // Basic character length-based estimation
    int baseCount = (text.length * factor).ceil();

    // Consider line breaks, special characters, etc.
    final specialCharsRegex =
        RegExp("[\n\t!\"#\$%&\\'()*+,-./:;<=>?@[\\\\]^_`{|}~]");
    int specialChars = specialCharsRegex.allMatches(text).length;

    // Numbers use fewer tokens
    int numbers = RegExp(r'\d+').allMatches(text).length;

    // Spaces also use separate tokens
    int spaces = RegExp(r'\s+').allMatches(text).length;

    // Apply slight weighting to special elements
    return baseCount + (specialChars ~/ 5) + (spaces ~/ 2) - (numbers ~/ 4);
  }

  // Register custom tokenizer (for extensibility)
  void registerCustomFactor(String modelPrefix, double factor) {
    _modelToFactor[modelPrefix.toLowerCase()] = factor;
  }
}

// Tokenizer interface (for extensibility)
abstract class Tokenizer {
  int countTokens(String text);
  int countMessageTokens(LlmMessage message);
  int getBaseTokens();
}

// Default tokenizer implementation
class DefaultTokenizer implements Tokenizer {
  @override
  int countTokens(String text) {
    // Heuristic: on average in English text, 1 token = 4 characters
    return (text.length / 4).ceil();
  }

  @override
  int countMessageTokens(LlmMessage message) {
    int tokens = 4; // Role marker tokens

    if (message.content is String) {
      tokens += countTokens(message.content as String);
    }

    return tokens;
  }

  @override
  int getBaseTokens() {
    return 3; // Base system marker tokens
  }
}
