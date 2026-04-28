/// GCS Storage Provider - Google Cloud Storage API integration.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mcp_bundle/ports.dart' as bundle;

import 'binary_storage_provider.dart';

/// Google Cloud Storage provider.
///
/// Provides binary storage using Google Cloud Storage.
/// Features: content-addressable storage, metadata, lifecycle management.
class GcsStorageProvider extends BaseBinaryStorageProvider {
  static const String _baseUrl = 'https://storage.googleapis.com';
  static const String _uploadUrl = 'https://storage.googleapis.com/upload/storage/v1';

  final http.Client _httpClient;
  final Map<String, bundle.StorageMetadata> _metadataCache = {};

  GcsStorageProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  @override
  String get id => 'gcs';

  @override
  Future<String> store(
    Stream<List<int>> data,
    String mimeType, [
    bundle.StorageOptions options = const bundle.StorageOptions(),
  ]) async {
    final bytes = await collectBytes(data);

    // Generate object name
    String objectName;
    if (options.contentAddressable) {
      final hash = _sha256Hash(bytes);
      objectName = '${options.prefix ?? ''}$hash';
    } else {
      objectName = '${options.prefix ?? ''}${DateTime.now().millisecondsSinceEpoch}';
    }

    // Build upload URL
    final uri = Uri.parse(
      '$_uploadUrl/b/${config.bucket}/o?uploadType=media&name=${Uri.encodeComponent(objectName)}',
    );

    final headers = {
      'Authorization': 'Bearer ${config.accessKey}',
      'Content-Type': mimeType,
      'Content-Length': bytes.length.toString(),
    };

    // Add custom metadata
    final customMetadata = <String, String>{
      'sha256': _sha256Hash(bytes),
    };

    if (options.ttlSeconds > 0) {
      final expiresAt = DateTime.now().add(Duration(seconds: options.ttlSeconds));
      customMetadata['expires-at'] = expiresAt.toIso8601String();
    }

    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: bytes,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StorageProviderException(
        'GCS upload error: ${response.statusCode} - ${response.body}',
      );
    }

    // Update metadata with custom fields if needed
    await _updateMetadata(objectName, customMetadata);

    // Store metadata locally
    _metadataCache[objectName] = bundle.StorageMetadata(
      key: objectName,
      mimeType: mimeType,
      size: bytes.length,
      sha256: customMetadata['sha256']!,
      createdAt: DateTime.now(),
      expiresAt: options.ttlSeconds > 0
          ? DateTime.now().add(Duration(seconds: options.ttlSeconds))
          : null,
    );

    return 'gs://${config.bucket}/$objectName';
  }

  Future<void> _updateMetadata(String objectName, Map<String, String> metadata) async {
    final uri = Uri.parse(
      '$_baseUrl/storage/v1/b/${config.bucket}/o/${Uri.encodeComponent(objectName)}',
    );

    final body = jsonEncode({
      'metadata': metadata,
    });

    await _httpClient.patch(
      uri,
      headers: {
        'Authorization': 'Bearer ${config.accessKey}',
        'Content-Type': 'application/json',
      },
      body: body,
    );
  }

  @override
  Future<Uint8List> retrieve(String reference) async {
    final objectName = _extractObjectName(reference);
    final uri = Uri.parse(
      '$_baseUrl/${config.bucket}/${Uri.encodeComponent(objectName)}',
    );

    final response = await _httpClient.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${config.accessKey}',
      },
    );

    if (response.statusCode == 404) {
      throw StorageProviderException('Object not found: $reference');
    }

    if (response.statusCode != 200) {
      throw StorageProviderException(
        'GCS download error: ${response.statusCode} - ${response.body}',
      );
    }

    return response.bodyBytes;
  }

  @override
  Future<bool> exists(String reference) async {
    final objectName = _extractObjectName(reference);
    final uri = Uri.parse(
      '$_baseUrl/storage/v1/b/${config.bucket}/o/${Uri.encodeComponent(objectName)}',
    );

    final response = await _httpClient.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${config.accessKey}',
      },
    );

    return response.statusCode == 200;
  }

  @override
  Future<bundle.StorageMetadata?> metadata(String reference) async {
    final objectName = _extractObjectName(reference);

    // Check cache first
    if (_metadataCache.containsKey(objectName)) {
      return _metadataCache[objectName];
    }

    final uri = Uri.parse(
      '$_baseUrl/storage/v1/b/${config.bucket}/o/${Uri.encodeComponent(objectName)}',
    );

    final response = await _httpClient.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${config.accessKey}',
      },
    );

    if (response.statusCode != 200) {
      return null;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    final size = int.tryParse(json['size'] as String? ?? '0') ?? 0;
    final contentType = json['contentType'] as String? ?? 'application/octet-stream';
    final timeCreated = json['timeCreated'] as String?;
    final customMetadata = json['metadata'] as Map<String, dynamic>?;

    DateTime? createdAt;
    if (timeCreated != null) {
      createdAt = DateTime.tryParse(timeCreated);
    }

    DateTime? expiresAt;
    if (customMetadata != null && customMetadata.containsKey('expires-at')) {
      expiresAt = DateTime.tryParse(customMetadata['expires-at'] as String);
    }

    return bundle.StorageMetadata(
      key: objectName,
      mimeType: contentType,
      size: size,
      sha256: customMetadata?['sha256'] as String? ?? '',
      createdAt: createdAt ?? DateTime.now(),
      expiresAt: expiresAt,
    );
  }

  @override
  Future<bool> delete(String reference) async {
    final objectName = _extractObjectName(reference);
    final uri = Uri.parse(
      '$_baseUrl/storage/v1/b/${config.bucket}/o/${Uri.encodeComponent(objectName)}',
    );

    final response = await _httpClient.delete(
      uri,
      headers: {
        'Authorization': 'Bearer ${config.accessKey}',
      },
    );

    if (response.statusCode == 204 || response.statusCode == 200) {
      _metadataCache.remove(objectName);
      return true;
    }

    return false;
  }

  @override
  Future<List<String>> list([String? prefix]) async {
    var uri = Uri.parse(
      '$_baseUrl/storage/v1/b/${config.bucket}/o',
    );

    if (prefix != null) {
      uri = uri.replace(queryParameters: {'prefix': prefix});
    }

    final response = await _httpClient.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${config.accessKey}',
      },
    );

    if (response.statusCode != 200) {
      throw StorageProviderException(
        'GCS list error: ${response.statusCode} - ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final items = json['items'] as List<dynamic>?;

    if (items == null) {
      return [];
    }

    return items.map((item) {
      final name = item['name'] as String;
      return 'gs://${config.bucket}/$name';
    }).toList();
  }

  String _extractObjectName(String reference) {
    if (reference.startsWith('gs://')) {
      final parts = reference.substring(5).split('/');
      return parts.skip(1).join('/');
    }
    return reference;
  }

  String _sha256Hash(List<int> data) {
    return sha256.convert(data).toString();
  }

  @override
  Future<void> close() async {
    _httpClient.close();
    _metadataCache.clear();
    await super.close();
  }
}
