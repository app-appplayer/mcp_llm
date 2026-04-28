/// Google Vision OCR Provider - Google Cloud Vision OCR API integration.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mcp_bundle/ports.dart' as bundle;

import 'ocr_provider.dart';

/// Google Cloud Vision OCR API provider.
///
/// Provides text recognition using Google Cloud Vision API.
/// Features: text detection, document text detection, handwriting recognition.
class GoogleVisionOcrProvider extends BaseOcrProvider {
  static const String _baseUrl = 'https://vision.googleapis.com/v1/images:annotate';

  final http.Client _httpClient;

  /// Supported languages for OCR.
  static const List<String> _supportedLanguages = [
    'en', 'es', 'fr', 'de', 'it', 'pt', 'ru', 'ja', 'ko', 'zh',
    'ar', 'hi', 'th', 'vi', 'nl', 'pl', 'tr', 'uk', 'he', 'el',
    'cs', 'da', 'fi', 'hu', 'id', 'ms', 'no', 'ro', 'sk', 'sv',
  ];

  GoogleVisionOcrProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  @override
  String get id => 'google-vision-ocr';

  @override
  Future<List<String>> supportedLanguages() async => _supportedLanguages;

  @override
  Future<bundle.OcrResult> recognize(
    Stream<List<int>> imageData,
    bundle.OcrOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();

    final bytes = await collectBytes(imageData);
    final base64Image = base64Encode(bytes);

    // Use DOCUMENT_TEXT_DETECTION for better layout preservation
    final featureType = options.preserveLayout
        ? 'DOCUMENT_TEXT_DETECTION'
        : 'TEXT_DETECTION';

    final requestBody = {
      'requests': [
        {
          'image': {'content': base64Image},
          'features': [
            {'type': featureType},
          ],
          'imageContext': {
            'languageHints': [options.language],
          },
        }
      ]
    };

    final response = await _httpClient.post(
      Uri.parse('$_baseUrl?key=${config.apiKey}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );

    stopwatch.stop();

    if (response.statusCode != 200) {
      throw OcrProviderException(
        'Google Vision OCR API error: ${response.statusCode} - ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final responses = json['responses'] as List<dynamic>;

    if (responses.isEmpty) {
      return bundle.OcrResult(
        text: '',
        confidence: 0.0,
        processingTime: stopwatch.elapsed,
      );
    }

    final result = responses.first as Map<String, dynamic>;

    // Check for errors
    if (result.containsKey('error')) {
      final error = result['error'] as Map<String, dynamic>;
      throw OcrProviderException(
        'Google Vision OCR error: ${error['message']}',
      );
    }

    // Extract full text
    String fullText = '';
    String? detectedLanguage;
    double confidence = 0.0;
    final regions = <bundle.OcrRegion>[];

    if (options.preserveLayout && result.containsKey('fullTextAnnotation')) {
      final fullTextAnnotation = result['fullTextAnnotation'] as Map<String, dynamic>;
      fullText = fullTextAnnotation['text'] as String? ?? '';

      // Extract page-level information
      final pages = fullTextAnnotation['pages'] as List<dynamic>?;
      if (pages != null && pages.isNotEmpty) {
        final page = pages.first as Map<String, dynamic>;

        // Get detected language
        final property = page['property'] as Map<String, dynamic>?;
        if (property != null) {
          final detectedLanguages = property['detectedLanguages'] as List<dynamic>?;
          if (detectedLanguages != null && detectedLanguages.isNotEmpty) {
            final lang = detectedLanguages.first as Map<String, dynamic>;
            detectedLanguage = lang['languageCode'] as String?;
            confidence = (lang['confidence'] as num?)?.toDouble() ?? 0.9;
          }
        }

        // Extract blocks as regions
        final blocks = page['blocks'] as List<dynamic>?;
        if (blocks != null) {
          for (final block in blocks) {
            final region = _extractBlockRegion(block as Map<String, dynamic>);
            if (region != null) {
              regions.add(region);
            }
          }
        }
      }
    } else if (result.containsKey('textAnnotations')) {
      final textAnnotations = result['textAnnotations'] as List<dynamic>;
      if (textAnnotations.isNotEmpty) {
        // First annotation is the full text
        fullText = textAnnotations.first['description'] as String? ?? '';
        detectedLanguage = textAnnotations.first['locale'] as String?;
        confidence = 0.9; // Google doesn't return confidence for TEXT_DETECTION

        // Remaining annotations are individual words/blocks
        for (int i = 1; i < textAnnotations.length; i++) {
          final annotation = textAnnotations[i] as Map<String, dynamic>;
          final region = _extractAnnotationRegion(annotation);
          if (region != null) {
            regions.add(region);
          }
        }
      }
    }

    return bundle.OcrResult(
      text: fullText,
      confidence: confidence,
      language: detectedLanguage ?? options.language,
      regions: regions.isNotEmpty ? regions : null,
      processingTime: stopwatch.elapsed,
    );
  }

  bundle.OcrRegion? _extractBlockRegion(Map<String, dynamic> block) {
    final paragraphs = block['paragraphs'] as List<dynamic>?;
    if (paragraphs == null || paragraphs.isEmpty) return null;

    final textBuffer = StringBuffer();
    double totalConfidence = 0.0;
    int wordCount = 0;

    for (final paragraph in paragraphs) {
      final words = paragraph['words'] as List<dynamic>?;
      if (words != null) {
        for (final word in words) {
          final symbols = word['symbols'] as List<dynamic>?;
          if (symbols != null) {
            for (final symbol in symbols) {
              textBuffer.write(symbol['text'] as String? ?? '');

              final property = symbol['property'] as Map<String, dynamic>?;
              if (property != null) {
                final detectedBreak = property['detectedBreak'] as Map<String, dynamic>?;
                if (detectedBreak != null) {
                  final breakType = detectedBreak['type'] as String?;
                  if (breakType == 'SPACE' || breakType == 'SURE_SPACE') {
                    textBuffer.write(' ');
                  } else if (breakType == 'EOL_SURE_SPACE' || breakType == 'LINE_BREAK') {
                    textBuffer.write('\n');
                  }
                }
              }
            }
          }

          final wordProperty = word['property'] as Map<String, dynamic>?;
          if (wordProperty != null) {
            final wordConfidence = word['confidence'] as num?;
            if (wordConfidence != null) {
              totalConfidence += wordConfidence.toDouble();
              wordCount++;
            }
          }
        }
      }
    }

    final text = textBuffer.toString().trim();
    if (text.isEmpty) return null;

    final boundingBox = _extractBoundingBox(block['boundingBox'] as Map<String, dynamic>?);

    return bundle.OcrRegion(
      text: text,
      confidence: wordCount > 0 ? totalConfidence / wordCount : 0.9,
      boundingBox: boundingBox,
    );
  }

  bundle.OcrRegion? _extractAnnotationRegion(Map<String, dynamic> annotation) {
    final text = annotation['description'] as String?;
    if (text == null || text.isEmpty) return null;

    final boundingPoly = annotation['boundingPoly'] as Map<String, dynamic>?;
    final boundingBox = _extractBoundingBox(boundingPoly);

    return bundle.OcrRegion(
      text: text,
      confidence: 0.9,
      boundingBox: boundingBox,
    );
  }

  bundle.BoundingBox _extractBoundingBox(Map<String, dynamic>? boundingPoly) {
    if (boundingPoly == null) {
      return const bundle.BoundingBox(x: 0, y: 0, width: 0, height: 0);
    }

    final vertices = boundingPoly['vertices'] as List<dynamic>?;
    if (vertices == null || vertices.length < 4) {
      return const bundle.BoundingBox(x: 0, y: 0, width: 0, height: 0);
    }

    final x = (vertices[0]['x'] as num? ?? 0).toDouble();
    final y = (vertices[0]['y'] as num? ?? 0).toDouble();
    final x2 = (vertices[2]['x'] as num? ?? 0).toDouble();
    final y2 = (vertices[2]['y'] as num? ?? 0).toDouble();

    return bundle.BoundingBox(
      x: x,
      y: y,
      width: x2 - x,
      height: y2 - y,
    );
  }

  @override
  Future<void> close() async {
    _httpClient.close();
    await super.close();
  }
}
