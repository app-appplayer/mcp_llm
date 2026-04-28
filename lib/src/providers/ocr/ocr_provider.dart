/// OCR Provider - Cloud OCR API abstraction.
///
/// Provides interface for cloud OCR services (Google Vision OCR, AWS Textract).
library;

import 'dart:typed_data';

import 'package:mcp_bundle/ports.dart' as bundle;

/// Abstract interface for OCR providers.
///
/// Implementations connect to cloud OCR APIs and provide text recognition
/// capabilities that can be adapted to bundle.OcrPort.
abstract interface class OcrProvider {
  /// Provider identifier.
  String get id;

  /// Recognize text from image.
  ///
  /// [imageData] - Image bytes as a stream.
  /// [options] - OCR options.
  ///
  /// Returns a [bundle.OcrResult] with recognized text and metadata.
  Future<bundle.OcrResult> recognize(
    Stream<List<int>> imageData,
    bundle.OcrOptions options,
  );

  /// Check if the provider is available.
  Future<bool> isAvailable();

  /// Get list of supported languages.
  Future<List<String>> supportedLanguages();

  /// Initialize the provider with configuration.
  Future<void> initialize(OcrProviderConfig config);

  /// Close and cleanup resources.
  Future<void> close();
}

/// Configuration for OCR providers.
class OcrProviderConfig {
  /// API key for the OCR service.
  final String apiKey;

  /// Optional project ID (for Google Cloud).
  final String? projectId;

  /// Optional region (for AWS).
  final String? region;

  /// Request timeout.
  final Duration timeout;

  /// Maximum retries on failure.
  final int maxRetries;

  const OcrProviderConfig({
    required this.apiKey,
    this.projectId,
    this.region,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
  });
}

/// Base class for OCR providers with common functionality.
abstract class BaseOcrProvider implements OcrProvider {
  OcrProviderConfig? _config;
  bool _initialized = false;

  @override
  Future<void> initialize(OcrProviderConfig config) async {
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
  OcrProviderConfig get config {
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

/// Exception thrown by OCR providers.
class OcrProviderException implements Exception {
  final String message;
  final Object? cause;

  OcrProviderException(this.message, [this.cause]);

  @override
  String toString() => 'OcrProviderException: $message${cause != null ? ' ($cause)' : ''}';
}
