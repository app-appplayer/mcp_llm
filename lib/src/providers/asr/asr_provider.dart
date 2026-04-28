/// ASR Provider - Cloud speech recognition API abstraction.
///
/// Provides interface for cloud ASR services (OpenAI Whisper, Google Speech).
library;

import 'dart:typed_data';

import 'package:mcp_bundle/ports.dart' as bundle;

/// Abstract interface for ASR (Automatic Speech Recognition) providers.
///
/// Implementations connect to cloud ASR APIs and provide speech-to-text
/// capabilities that can be adapted to bundle.AsrPort.
abstract interface class AsrProvider {
  /// Provider identifier.
  String get id;

  /// Transcribe audio stream to text.
  ///
  /// [audioData] - Audio bytes as a stream.
  /// [options] - ASR transcription options.
  ///
  /// Returns a [bundle.AsrResult] with transcribed text and metadata.
  Future<bundle.AsrResult> transcribe(
    Stream<List<int>> audioData,
    bundle.AsrOptions options,
  );

  /// Check if the provider is available.
  Future<bool> isAvailable();

  /// Get list of supported languages.
  Future<List<String>> supportedLanguages();

  /// Initialize the provider with configuration.
  Future<void> initialize(AsrProviderConfig config);

  /// Close and cleanup resources.
  Future<void> close();
}

/// Configuration for ASR providers.
class AsrProviderConfig {
  /// API key for the ASR service.
  final String apiKey;

  /// Optional project ID (for Google Cloud).
  final String? projectId;

  /// Request timeout.
  final Duration timeout;

  /// Maximum retries on failure.
  final int maxRetries;

  const AsrProviderConfig({
    required this.apiKey,
    this.projectId,
    this.timeout = const Duration(minutes: 5),
    this.maxRetries = 3,
  });
}

/// Base class for ASR providers with common functionality.
abstract class BaseAsrProvider implements AsrProvider {
  AsrProviderConfig? _config;
  bool _initialized = false;

  @override
  Future<void> initialize(AsrProviderConfig config) async {
    _config = config;
    _initialized = true;
  }

  @override
  Future<void> close() async {
    _initialized = false;
  }

  @override
  Future<bool> isAvailable() async => _initialized;

  /// Get the current configuration.
  AsrProviderConfig get config {
    if (_config == null) {
      throw StateError('Provider not initialized. Call initialize() first.');
    }
    return _config!;
  }

  /// Collect stream bytes into Uint8List.
  Future<Uint8List> collectBytes(Stream<List<int>> stream) async {
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }
}

/// Exception thrown by ASR providers.
class AsrProviderException implements Exception {
  final String message;
  final Object? cause;

  AsrProviderException(this.message, [this.cause]);

  @override
  String toString() => 'AsrProviderException: $message${cause != null ? ' ($cause)' : ''}';
}
