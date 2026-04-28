/// Google Speech Provider - Google Cloud Speech-to-Text API integration.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mcp_bundle/ports.dart' as bundle;

import 'asr_provider.dart';

/// Google Cloud Speech-to-Text API provider.
///
/// Provides speech-to-text using Google Cloud Speech API.
/// Features: speaker diarization, real-time streaming, multiple languages.
class GoogleSpeechProvider extends BaseAsrProvider {
  static const String _baseUrl = 'https://speech.googleapis.com/v1/speech:recognize';

  final http.Client _httpClient;

  /// Supported languages by Google Speech.
  static const List<String> _supportedLanguages = [
    'en-US', 'en-GB', 'en-AU', 'en-IN', 'es-ES', 'es-MX', 'es-US',
    'fr-FR', 'fr-CA', 'de-DE', 'it-IT', 'pt-BR', 'pt-PT', 'ru-RU',
    'ja-JP', 'ko-KR', 'zh-CN', 'zh-TW', 'ar-SA', 'hi-IN', 'nl-NL',
    'pl-PL', 'sv-SE', 'tr-TR', 'uk-UA', 'vi-VN', 'th-TH', 'id-ID',
  ];

  GoogleSpeechProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  @override
  String get id => 'google-speech';

  @override
  Future<List<String>> supportedLanguages() async => _supportedLanguages;

  @override
  Future<bundle.AsrResult> transcribe(
    Stream<List<int>> audioData,
    bundle.AsrOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();

    final bytes = await collectBytes(audioData);
    final base64Audio = base64Encode(bytes);

    // Map simple language code to BCP-47
    final languageCode = _mapLanguageCode(options.language);

    final requestBody = <String, dynamic>{
      'config': {
        'encoding': 'LINEAR16',
        'sampleRateHertz': 16000,
        'languageCode': languageCode,
        'enableAutomaticPunctuation': true,
        'enableWordTimeOffsets': options.wordTimestamps,
        if (options.enableDiarization) ...{
          'enableSpeakerDiarization': true,
          'diarizationSpeakerCount': options.maxSpeakers ?? 2,
        },
        if (options.modelSize != null)
          'model': _mapModelSize(options.modelSize!),
      },
      'audio': {
        'content': base64Audio,
      },
    };

    final response = await _httpClient.post(
      Uri.parse('$_baseUrl?key=${config.apiKey}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );

    final audioDuration = _estimateAudioDuration(bytes);
    stopwatch.stop();

    if (response.statusCode != 200) {
      throw AsrProviderException(
        'Google Speech API error: ${response.statusCode} - ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final results = json['results'] as List<dynamic>?;

    if (results == null || results.isEmpty) {
      return bundle.AsrResult(
        text: '',
        confidence: 0.0,
        language: languageCode,
        audioDuration: audioDuration,
        processingTime: stopwatch.elapsed,
      );
    }

    // Combine all transcripts
    final transcripts = <String>[];
    final segments = <bundle.AsrSegment>[];
    double totalConfidence = 0.0;
    int confidenceCount = 0;

    for (final result in results) {
      final alternatives = result['alternatives'] as List<dynamic>?;
      if (alternatives != null && alternatives.isNotEmpty) {
        final best = alternatives.first as Map<String, dynamic>;
        transcripts.add(best['transcript'] as String? ?? '');

        if (best.containsKey('confidence')) {
          totalConfidence += (best['confidence'] as num).toDouble();
          confidenceCount++;
        }

        // Extract word timings
        if (best.containsKey('words')) {
          for (final word in best['words'] as List<dynamic>) {
            final startTime = _parseDuration(word['startTime'] as String?);
            final endTime = _parseDuration(word['endTime'] as String?);
            final speakerId = word['speakerTag'] as int?;

            segments.add(bundle.AsrSegment(
              text: word['word'] as String,
              startTime: startTime,
              endTime: endTime,
              confidence: (word['confidence'] as num?)?.toDouble() ?? 0.9,
              speakerId: speakerId != null ? 'speaker_$speakerId' : null,
            ));
          }
        }
      }
    }

    final text = transcripts.join(' ');
    final avgConfidence = confidenceCount > 0 ? totalConfidence / confidenceCount : 0.9;

    return bundle.AsrResult(
      text: text,
      confidence: avgConfidence,
      language: languageCode,
      segments: segments.isNotEmpty ? segments : null,
      audioDuration: audioDuration,
      processingTime: stopwatch.elapsed,
    );
  }

  String _mapLanguageCode(String code) {
    // Map simple codes to BCP-47
    final mapping = {
      'en': 'en-US',
      'es': 'es-ES',
      'fr': 'fr-FR',
      'de': 'de-DE',
      'it': 'it-IT',
      'pt': 'pt-BR',
      'ru': 'ru-RU',
      'ja': 'ja-JP',
      'ko': 'ko-KR',
      'zh': 'zh-CN',
      'ar': 'ar-SA',
      'hi': 'hi-IN',
    };

    return mapping[code] ?? code;
  }

  String _mapModelSize(String size) {
    switch (size.toLowerCase()) {
      case 'tiny':
      case 'base':
        return 'default';
      case 'small':
      case 'medium':
        return 'command_and_search';
      case 'large':
        return 'latest_long';
      default:
        return 'default';
    }
  }

  Duration _parseDuration(String? durationStr) {
    if (durationStr == null) return Duration.zero;
    // Format: "1.5s" or "0.123456s"
    final seconds = double.tryParse(durationStr.replaceAll('s', '')) ?? 0.0;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  Duration _estimateAudioDuration(List<int> bytes) {
    // Rough estimate: assume 16kHz, 16-bit mono audio
    final seconds = bytes.length / (16000 * 2 * 1);
    return Duration(milliseconds: (seconds * 1000).round());
  }

  @override
  Future<void> close() async {
    _httpClient.close();
    await super.close();
  }
}
