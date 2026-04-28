/// Google Vision Provider - Google Cloud Vision API integration.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mcp_bundle/ports.dart' as bundle;

import 'vision_provider.dart';

/// Google Cloud Vision API provider.
///
/// Provides image analysis using Google Cloud Vision API.
/// Features: label detection, face detection, object detection.
class GoogleVisionProvider extends BaseVisionProvider {
  static const String _baseUrl = 'https://vision.googleapis.com/v1/images:annotate';

  final http.Client _httpClient;

  GoogleVisionProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  @override
  String get id => 'google-vision';

  @override
  Future<bundle.VisionResult> describe(
    Stream<List<int>> imageData,
    bundle.VisionOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();

    final bytes = await collectBytes(imageData);
    final base64Image = base64Encode(bytes);

    final features = <Map<String, dynamic>>[];

    // Always include label detection for description
    features.add({'type': 'LABEL_DETECTION', 'maxResults': 10});

    if (options.detectObjects) {
      features.add({'type': 'OBJECT_LOCALIZATION', 'maxResults': 10});
    }

    if (options.detectFaces) {
      features.add({'type': 'FACE_DETECTION', 'maxResults': 10});
    }

    if (options.extractText) {
      features.add({'type': 'TEXT_DETECTION'});
    }

    final requestBody = {
      'requests': [
        {
          'image': {'content': base64Image},
          'features': features,
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
      throw VisionProviderException(
        'Google Vision API error: ${response.statusCode} - ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final responses = json['responses'] as List<dynamic>;

    if (responses.isEmpty) {
      return bundle.VisionResult(
        description: '',
        confidence: 0.0,
        processingTime: stopwatch.elapsed,
      );
    }

    final result = responses.first as Map<String, dynamic>;

    // Extract labels
    final labels = <bundle.VisionLabel>[];
    if (result.containsKey('labelAnnotations')) {
      for (final label in result['labelAnnotations'] as List<dynamic>) {
        labels.add(bundle.VisionLabel(
          name: label['description'] as String,
          confidence: (label['score'] as num).toDouble(),
        ));
      }
    }

    // Extract objects with bounding boxes
    if (result.containsKey('localizedObjectAnnotations')) {
      for (final obj in result['localizedObjectAnnotations'] as List<dynamic>) {
        final vertices = obj['boundingPoly']['normalizedVertices'] as List<dynamic>;
        if (vertices.length >= 4) {
          labels.add(bundle.VisionLabel(
            name: obj['name'] as String,
            confidence: (obj['score'] as num).toDouble(),
            boundingBox: _extractBoundingBox(vertices),
          ));
        }
      }
    }

    // Extract faces
    final faces = <bundle.VisionFace>[];
    if (result.containsKey('faceAnnotations')) {
      for (final face in result['faceAnnotations'] as List<dynamic>) {
        final vertices = face['boundingPoly']['vertices'] as List<dynamic>;
        faces.add(bundle.VisionFace(
          boundingBox: _extractBoundingBoxFromVertices(vertices),
          confidence: (face['detectionConfidence'] as num? ?? 0.9).toDouble(),
          emotions: _extractEmotions(face),
        ));
      }
    }

    // Extract text
    String? extractedText;
    if (result.containsKey('textAnnotations')) {
      final textAnnotations = result['textAnnotations'] as List<dynamic>;
      if (textAnnotations.isNotEmpty) {
        extractedText = textAnnotations.first['description'] as String;
      }
    }

    // Generate description from labels
    final description = _generateDescription(labels, faces, extractedText);

    // Calculate average confidence
    double confidence = 0.0;
    if (labels.isNotEmpty) {
      confidence = labels.map((l) => l.confidence).reduce((a, b) => a + b) / labels.length;
    }

    return bundle.VisionResult(
      description: description,
      labels: labels.isNotEmpty ? labels : null,
      faces: faces.isNotEmpty ? faces : null,
      text: extractedText,
      confidence: confidence,
      processingTime: stopwatch.elapsed,
    );
  }

  bundle.BoundingBox _extractBoundingBox(List<dynamic> vertices) {
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

  bundle.BoundingBox _extractBoundingBoxFromVertices(List<dynamic> vertices) {
    if (vertices.isEmpty) {
      return const bundle.BoundingBox(x: 0, y: 0, width: 0, height: 0);
    }

    final x = (vertices[0]['x'] as num? ?? 0).toDouble();
    final y = (vertices[0]['y'] as num? ?? 0).toDouble();
    final x2 = vertices.length > 2 ? (vertices[2]['x'] as num? ?? 0).toDouble() : x;
    final y2 = vertices.length > 2 ? (vertices[2]['y'] as num? ?? 0).toDouble() : y;

    return bundle.BoundingBox(
      x: x,
      y: y,
      width: x2 - x,
      height: y2 - y,
    );
  }

  Map<String, double>? _extractEmotions(Map<String, dynamic> face) {
    final emotions = <String, double>{};

    final emotionFields = {
      'joyLikelihood': 'joy',
      'sorrowLikelihood': 'sorrow',
      'angerLikelihood': 'anger',
      'surpriseLikelihood': 'surprise',
    };

    for (final entry in emotionFields.entries) {
      if (face.containsKey(entry.key)) {
        emotions[entry.value] = _likelihoodToScore(face[entry.key] as String);
      }
    }

    return emotions.isNotEmpty ? emotions : null;
  }

  double _likelihoodToScore(String likelihood) {
    switch (likelihood) {
      case 'VERY_LIKELY':
        return 0.95;
      case 'LIKELY':
        return 0.75;
      case 'POSSIBLE':
        return 0.5;
      case 'UNLIKELY':
        return 0.25;
      case 'VERY_UNLIKELY':
        return 0.05;
      default:
        return 0.0;
    }
  }

  String _generateDescription(
    List<bundle.VisionLabel> labels,
    List<bundle.VisionFace> faces,
    String? text,
  ) {
    final parts = <String>[];

    if (labels.isNotEmpty) {
      final topLabels = labels.take(5).map((l) => l.name).join(', ');
      parts.add('Image contains: $topLabels');
    }

    if (faces.isNotEmpty) {
      parts.add('${faces.length} face(s) detected');
    }

    if (text != null && text.isNotEmpty) {
      final preview = text.length > 100 ? '${text.substring(0, 100)}...' : text;
      parts.add('Text found: $preview');
    }

    return parts.join('. ');
  }

  @override
  Future<void> close() async {
    _httpClient.close();
    await super.close();
  }
}

/// Exception thrown by vision providers.
class VisionProviderException implements Exception {
  final String message;
  final Object? cause;

  VisionProviderException(this.message, [this.cause]);

  @override
  String toString() => 'VisionProviderException: $message${cause != null ? ' ($cause)' : ''}';
}
