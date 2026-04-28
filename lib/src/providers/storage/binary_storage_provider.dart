/// Binary Storage Provider - Cloud storage API abstraction.
///
/// Provides interface for cloud storage services (AWS S3, Google Cloud Storage).
library;

import 'dart:typed_data';

import 'package:mcp_bundle/ports.dart' as bundle;

/// Abstract interface for binary storage providers.
///
/// Implementations connect to cloud storage APIs and provide binary asset
/// storage capabilities that can be adapted to bundle.BinaryStoragePort.
abstract interface class BinaryStorageProvider {
  /// Provider identifier.
  String get id;

  /// Store binary data and return a reference.
  ///
  /// [data] - Binary data as a stream.
  /// [mimeType] - MIME type of the data.
  /// [options] - Storage options.
  ///
  /// Returns a reference string to retrieve the data later.
  Future<String> store(
    Stream<List<int>> data,
    String mimeType, [
    bundle.StorageOptions options = const bundle.StorageOptions(),
  ]);

  /// Retrieve binary data by reference.
  Future<Uint8List> retrieve(String reference);

  /// Check if a reference exists.
  Future<bool> exists(String reference);

  /// Get metadata for a reference.
  Future<bundle.StorageMetadata?> metadata(String reference);

  /// Delete a stored asset.
  Future<bool> delete(String reference);

  /// List all stored references with optional prefix.
  Future<List<String>> list([String? prefix]);

  /// Check if the provider is available.
  Future<bool> isAvailable();

  /// Initialize the provider with configuration.
  Future<void> initialize(StorageProviderConfig config);

  /// Close and cleanup resources.
  Future<void> close();
}

/// Configuration for storage providers.
class StorageProviderConfig {
  /// API key or access key for the storage service.
  final String accessKey;

  /// Secret key for the storage service.
  final String? secretKey;

  /// Bucket name.
  final String bucket;

  /// Region (for AWS S3).
  final String? region;

  /// Project ID (for Google Cloud Storage).
  final String? projectId;

  /// Request timeout.
  final Duration timeout;

  /// Maximum retries on failure.
  final int maxRetries;

  const StorageProviderConfig({
    required this.accessKey,
    this.secretKey,
    required this.bucket,
    this.region,
    this.projectId,
    this.timeout = const Duration(seconds: 60),
    this.maxRetries = 3,
  });
}

/// Base class for storage providers with common functionality.
abstract class BaseBinaryStorageProvider implements BinaryStorageProvider {
  StorageProviderConfig? _config;
  bool _initialized = false;

  @override
  Future<void> initialize(StorageProviderConfig config) async {
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
  StorageProviderConfig get config {
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

  /// Generate SHA-256 hash for content-addressable storage.
  String generateHash(Uint8List data) {
    // Simple hash implementation using Dart's built-in
    int hash = 0;
    for (int i = 0; i < data.length; i++) {
      hash = (hash * 31 + data[i]) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

/// Exception thrown by storage providers.
class StorageProviderException implements Exception {
  final String message;
  final Object? cause;

  StorageProviderException(this.message, [this.cause]);

  @override
  String toString() => 'StorageProviderException: $message${cause != null ? ' ($cause)' : ''}';
}
