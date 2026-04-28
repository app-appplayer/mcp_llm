/// Storage Port Adapter - Bridges BinaryStorageProvider with mcp_bundle.BinaryStoragePort.
library;

import 'dart:typed_data';

import 'package:mcp_bundle/ports.dart' as bundle;

import '../providers/storage/binary_storage_provider.dart';
import '../providers/storage/s3_storage_provider.dart';
import '../providers/storage/gcs_storage_provider.dart';

/// Adapter that implements mcp_bundle's BinaryStoragePort using mcp_llm's BinaryStorageProvider.
///
/// Converts between Contract Layer types (mcp_bundle) and mcp_llm internal types.
///
/// Usage:
/// ```dart
/// import 'package:mcp_llm/mcp_llm.dart';
/// import 'package:mcp_bundle/ports.dart' as bundle;
///
/// // Create storage provider
/// final provider = S3StorageProvider();
/// await provider.initialize(StorageProviderConfig(
///   accessKey: '...',
///   secretKey: '...',
///   bucket: 'my-bucket',
///   region: 'us-east-1',
/// ));
///
/// // Create adapter implementing bundle.BinaryStoragePort
/// final storagePort = BinaryStoragePortAdapter(provider);
///
/// // Use with mcp_ingest
/// final ingestPorts = IngestPorts(storage: storagePort, ...);
/// ```
class BinaryStoragePortAdapter implements bundle.BinaryStoragePort {
  /// The underlying mcp_llm storage provider.
  final BinaryStorageProvider _provider;

  /// Create an adapter wrapping a BinaryStorageProvider.
  ///
  /// [provider] - The mcp_llm storage provider to wrap.
  BinaryStoragePortAdapter(this._provider);

  @override
  Future<String> store(
    Stream<List<int>> data,
    String mimeType, [
    bundle.StorageOptions options = const bundle.StorageOptions(),
  ]) {
    return _provider.store(data, mimeType, options);
  }

  @override
  Future<Uint8List> retrieve(String reference) {
    return _provider.retrieve(reference);
  }

  @override
  Future<bool> exists(String reference) {
    return _provider.exists(reference);
  }

  @override
  Future<bundle.StorageMetadata?> metadata(String reference) {
    return _provider.metadata(reference);
  }

  @override
  Future<bool> delete(String reference) {
    return _provider.delete(reference);
  }

  @override
  Future<List<String>> list([String? prefix]) {
    return _provider.list(prefix);
  }
}

/// Factory for creating BinaryStoragePortAdapter instances.
class BinaryStoragePortAdapterFactory {
  /// Create an adapter for AWS S3.
  static Future<BinaryStoragePortAdapter> s3({
    required String accessKey,
    required String secretKey,
    required String bucket,
    String region = 'us-east-1',
  }) async {
    final provider = S3StorageProvider();
    await provider.initialize(StorageProviderConfig(
      accessKey: accessKey,
      secretKey: secretKey,
      bucket: bucket,
      region: region,
    ));
    return BinaryStoragePortAdapter(provider);
  }

  /// Create an adapter for Google Cloud Storage.
  static Future<BinaryStoragePortAdapter> gcs({
    required String accessToken,
    required String bucket,
    String? projectId,
  }) async {
    final provider = GcsStorageProvider();
    await provider.initialize(StorageProviderConfig(
      accessKey: accessToken,
      bucket: bucket,
      projectId: projectId,
    ));
    return BinaryStoragePortAdapter(provider);
  }
}
