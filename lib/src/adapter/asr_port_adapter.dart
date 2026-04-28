/// ASR Port Adapter - Bridges AsrProvider with mcp_bundle.AsrPort.
library;

import 'package:mcp_bundle/ports.dart' as bundle;

import '../providers/asr/asr_provider.dart';
import '../providers/asr/openai_whisper_provider.dart';
import '../providers/asr/google_speech_provider.dart';

/// Adapter that implements mcp_bundle's AsrPort using mcp_llm's AsrProvider.
///
/// Converts between Contract Layer types (mcp_bundle) and mcp_llm internal types.
///
/// Usage:
/// ```dart
/// import 'package:mcp_llm/mcp_llm.dart';
/// import 'package:mcp_bundle/ports.dart' as bundle;
///
/// // Create ASR provider
/// final provider = OpenAIWhisperProvider();
/// await provider.initialize(AsrProviderConfig(apiKey: '...'));
///
/// // Create adapter implementing bundle.AsrPort
/// final asrPort = AsrPortAdapter(provider);
///
/// // Use with mcp_ingest
/// final ingestPorts = IngestPorts(asr: asrPort, ...);
/// ```
class AsrPortAdapter implements bundle.AsrPort {
  /// The underlying mcp_llm ASR provider.
  final AsrProvider _provider;

  /// Create an adapter wrapping an AsrProvider.
  ///
  /// [provider] - The mcp_llm ASR provider to wrap.
  AsrPortAdapter(this._provider);

  @override
  Future<bundle.AsrResult> transcribe(
    Stream<List<int>> audioData,
    bundle.AsrOptions options,
  ) {
    return _provider.transcribe(audioData, options);
  }

  @override
  Future<bool> isAvailable() {
    return _provider.isAvailable();
  }

  @override
  Future<List<String>> supportedLanguages() {
    return _provider.supportedLanguages();
  }
}

/// Factory for creating AsrPortAdapter instances.
class AsrPortAdapterFactory {
  /// Create an adapter for OpenAI Whisper.
  static Future<AsrPortAdapter> whisper({
    required String apiKey,
    String model = 'whisper-1',
  }) async {
    final provider = OpenAIWhisperProvider(model: model);
    await provider.initialize(AsrProviderConfig(apiKey: apiKey));
    return AsrPortAdapter(provider);
  }

  /// Create an adapter for Google Speech.
  static Future<AsrPortAdapter> google({
    required String apiKey,
    String? projectId,
  }) async {
    final provider = GoogleSpeechProvider();
    await provider.initialize(AsrProviderConfig(
      apiKey: apiKey,
      projectId: projectId,
    ));
    return AsrPortAdapter(provider);
  }
}
