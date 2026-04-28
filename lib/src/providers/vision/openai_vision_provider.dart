/// OpenAI Vision Provider - OpenAI GPT-4 Vision API integration.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mcp_bundle/ports.dart' as bundle;

import 'vision_provider.dart';
import 'google_vision_provider.dart' show VisionProviderException;

/// OpenAI GPT-4 Vision API provider.
///
/// Provides image analysis using OpenAI's GPT-4 Vision capabilities.
/// Features: detailed image descriptions, visual Q&A, complex scene understanding.
class OpenAIVisionProvider extends BaseVisionProvider {
  static const String _baseUrl = 'https://api.openai.com/v1/chat/completions';

  final http.Client _httpClient;
  final String _model;

  OpenAIVisionProvider({
    http.Client? httpClient,
    String model = 'gpt-4-vision-preview',
  })  : _httpClient = httpClient ?? http.Client(),
        _model = model;

  @override
  String get id => 'openai-vision';

  @override
  Future<bundle.VisionResult> describe(
    Stream<List<int>> imageData,
    bundle.VisionOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();

    final bytes = await collectBytes(imageData);
    final base64Image = base64Encode(bytes);

    // Build prompt based on options
    String prompt;
    if (options.prompt != null && options.prompt!.isNotEmpty) {
      prompt = options.prompt!;
    } else if (options.detailed) {
      prompt = '''Analyze this image in detail. Provide:
1. A comprehensive description of the scene
2. Key objects and their positions
3. Any text visible in the image
4. Notable colors, lighting, and composition
5. Any people or faces, including apparent emotions if visible''';
    } else {
      prompt = 'Briefly describe this image.';
    }

    final requestBody = {
      'model': _model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$base64Image',
                'detail': options.detailed ? 'high' : 'low',
              },
            },
          ],
        },
      ],
      'max_tokens': options.detailed ? 1000 : 300,
    };

    final response = await _httpClient.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey}',
      },
      body: jsonEncode(requestBody),
    );

    stopwatch.stop();

    if (response.statusCode != 200) {
      throw VisionProviderException(
        'OpenAI Vision API error: ${response.statusCode} - ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>;

    if (choices.isEmpty) {
      return bundle.VisionResult(
        description: '',
        confidence: 0.0,
        processingTime: stopwatch.elapsed,
      );
    }

    final message = choices.first['message'] as Map<String, dynamic>;
    final description = message['content'] as String? ?? '';

    // Extract labels from description (simple keyword extraction)
    final labels = _extractLabelsFromDescription(description);

    return bundle.VisionResult(
      description: description,
      labels: labels.isNotEmpty ? labels : null,
      confidence: 0.9, // GPT-4V doesn't provide confidence scores
      processingTime: stopwatch.elapsed,
    );
  }

  List<bundle.VisionLabel> _extractLabelsFromDescription(String description) {
    // Simple extraction of likely objects/concepts from the description
    final labels = <bundle.VisionLabel>[];
    final words = description.toLowerCase().split(RegExp(r'\s+'));

    // Common visual concepts to look for
    final commonObjects = {
      'person', 'people', 'man', 'woman', 'child', 'dog', 'cat', 'car',
      'tree', 'building', 'house', 'sky', 'water', 'beach', 'mountain',
      'food', 'table', 'chair', 'computer', 'phone', 'book', 'flower',
    };

    for (final word in words) {
      final cleanWord = word.replaceAll(RegExp(r'[^\w]'), '');
      if (commonObjects.contains(cleanWord) &&
          !labels.any((l) => l.name.toLowerCase() == cleanWord)) {
        labels.add(bundle.VisionLabel(
          name: cleanWord,
          confidence: 0.8, // Estimated confidence
        ));
      }
    }

    return labels.take(10).toList();
  }

  @override
  Future<void> close() async {
    _httpClient.close();
    await super.close();
  }
}
