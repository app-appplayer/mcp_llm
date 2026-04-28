/// OpenAI Whisper Provider - OpenAI Whisper API integration.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mcp_bundle/ports.dart' as bundle;

import 'asr_provider.dart';

/// OpenAI Whisper API provider.
///
/// Provides speech-to-text using OpenAI's Whisper model.
/// Features: multilingual support, word-level timestamps, translation.
class OpenAIWhisperProvider extends BaseAsrProvider {
  static const String _baseUrl = 'https://api.openai.com/v1/audio';

  final http.Client _httpClient;
  final String _model;

  /// Supported languages by Whisper.
  static const List<String> _supportedLanguages = [
    'af', 'ar', 'hy', 'az', 'be', 'bs', 'bg', 'ca', 'zh', 'hr', 'cs', 'da',
    'nl', 'en', 'et', 'fi', 'fr', 'gl', 'de', 'el', 'he', 'hi', 'hu', 'is',
    'id', 'it', 'ja', 'kn', 'kk', 'ko', 'lv', 'lt', 'mk', 'ms', 'mr', 'mi',
    'ne', 'no', 'fa', 'pl', 'pt', 'ro', 'ru', 'sr', 'sk', 'sl', 'es', 'sw',
    'sv', 'tl', 'ta', 'th', 'tr', 'uk', 'ur', 'vi', 'cy',
  ];

  OpenAIWhisperProvider({
    http.Client? httpClient,
    String model = 'whisper-1',
  })  : _httpClient = httpClient ?? http.Client(),
        _model = model;

  @override
  String get id => 'openai-whisper';

  @override
  Future<List<String>> supportedLanguages() async => _supportedLanguages;

  @override
  Future<bundle.AsrResult> transcribe(
    Stream<List<int>> audioData,
    bundle.AsrOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();

    final bytes = await collectBytes(audioData);

    // Build multipart request
    final uri = options.translate
        ? Uri.parse('$_baseUrl/translations')
        : Uri.parse('$_baseUrl/transcriptions');

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer ${config.apiKey}';

    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: 'audio.wav',
    ));

    request.fields['model'] = _model;

    if (!options.translate && options.language.isNotEmpty) {
      request.fields['language'] = options.language;
    }

    // Request word-level timestamps if needed
    String responseFormat = 'json';
    if (options.wordTimestamps) {
      responseFormat = 'verbose_json';
      request.fields['timestamp_granularities[]'] = 'word';
    }
    request.fields['response_format'] = responseFormat;

    final streamedResponse = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    final audioDuration = _estimateAudioDuration(bytes);
    stopwatch.stop();

    if (response.statusCode != 200) {
      throw AsrProviderException(
        'OpenAI Whisper API error: ${response.statusCode} - ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final text = json['text'] as String? ?? '';

    // Extract segments if available
    List<bundle.AsrSegment>? segments;
    if (json.containsKey('words')) {
      segments = _extractWordSegments(json['words'] as List<dynamic>);
    } else if (json.containsKey('segments')) {
      segments = _extractSegments(json['segments'] as List<dynamic>);
    }

    // Detect language if returned
    final detectedLanguage = json['language'] as String?;

    return bundle.AsrResult(
      text: text,
      confidence: 0.95, // Whisper doesn't return confidence, using high default
      language: detectedLanguage ?? options.language,
      segments: segments,
      audioDuration: audioDuration,
      processingTime: stopwatch.elapsed,
    );
  }

  List<bundle.AsrSegment> _extractWordSegments(List<dynamic> words) {
    return words.map((word) {
      return bundle.AsrSegment(
        text: word['word'] as String,
        startTime: Duration(milliseconds: ((word['start'] as num) * 1000).round()),
        endTime: Duration(milliseconds: ((word['end'] as num) * 1000).round()),
        confidence: 0.95,
      );
    }).toList();
  }

  List<bundle.AsrSegment> _extractSegments(List<dynamic> segments) {
    return segments.map((segment) {
      return bundle.AsrSegment(
        text: segment['text'] as String,
        startTime: Duration(milliseconds: ((segment['start'] as num) * 1000).round()),
        endTime: Duration(milliseconds: ((segment['end'] as num) * 1000).round()),
        confidence: 0.95,
      );
    }).toList();
  }

  Duration _estimateAudioDuration(List<int> bytes) {
    // Rough estimate: assume 16kHz, 16-bit mono audio
    // bytes / (sampleRate * bytesPerSample * channels)
    final seconds = bytes.length / (16000 * 2 * 1);
    return Duration(milliseconds: (seconds * 1000).round());
  }

  @override
  Future<void> close() async {
    _httpClient.close();
    await super.close();
  }
}
