/// Vision Provider - Cloud vision API abstraction.
///
/// Provides interface for cloud vision services (Google Vision, AWS Rekognition,
/// Claude Vision, OpenAI Vision).
library;

import 'dart:typed_data';

import 'package:mcp_bundle/ports.dart' as bundle;

/// Abstract interface for vision providers.
///
/// Implementations connect to cloud vision APIs and provide image analysis
/// capabilities that can be adapted to bundle.VisionPort.
abstract interface class VisionProvider {
  /// Provider identifier.
  String get id;

  /// Analyze and describe an image.
  ///
  /// [imageData] - Image bytes as a stream.
  /// [options] - Vision analysis options.
  ///
  /// Returns a [bundle.VisionResult] with description, labels, etc.
  Future<bundle.VisionResult> describe(
    Stream<List<int>> imageData,
    bundle.VisionOptions options,
  );

  /// Check if the provider is available.
  Future<bool> isAvailable();

  /// Initialize the provider with configuration.
  Future<void> initialize(VisionProviderConfig config);

  /// Close and cleanup resources.
  Future<void> close();
}

/// Configuration for vision providers.
class VisionProviderConfig {
  /// API key for the vision service.
  final String apiKey;

  /// Optional project ID (for Google Cloud).
  final String? projectId;

  /// Optional region (for AWS).
  final String? region;

  /// Request timeout.
  final Duration timeout;

  /// Maximum retries on failure.
  final int maxRetries;

  const VisionProviderConfig({
    required this.apiKey,
    this.projectId,
    this.region,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
  });
}

/// Base class for vision providers with common functionality.
abstract class BaseVisionProvider implements VisionProvider {
  VisionProviderConfig? _config;
  bool _initialized = false;

  @override
  Future<void> initialize(VisionProviderConfig config) async {
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
  VisionProviderConfig get config {
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
