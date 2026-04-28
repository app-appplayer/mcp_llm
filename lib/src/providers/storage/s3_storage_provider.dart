/// S3 Storage Provider - AWS S3 API integration.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mcp_bundle/ports.dart' as bundle;

import 'binary_storage_provider.dart';

/// AWS S3 storage provider.
///
/// Provides binary storage using AWS S3.
/// Features: content-addressable storage, metadata, TTL support.
class S3StorageProvider extends BaseBinaryStorageProvider {
  final http.Client _httpClient;
  final Map<String, bundle.StorageMetadata> _metadataCache = {};

  S3StorageProvider({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  @override
  String get id => 's3';

  String get _endpoint => 'https://${config.bucket}.s3.${config.region ?? 'us-east-1'}.amazonaws.com';

  @override
  Future<String> store(
    Stream<List<int>> data,
    String mimeType, [
    bundle.StorageOptions options = const bundle.StorageOptions(),
  ]) async {
    final bytes = await collectBytes(data);

    // Generate key
    String key;
    if (options.contentAddressable) {
      final hash = _sha256Hash(bytes);
      key = '${options.prefix ?? ''}$hash';
    } else {
      key = '${options.prefix ?? ''}${DateTime.now().millisecondsSinceEpoch}';
    }

    // Build request
    final uri = Uri.parse('$_endpoint/$key');
    final headers = await _signRequest(
      method: 'PUT',
      uri: uri,
      contentType: mimeType,
      body: bytes,
    );

    headers['Content-Type'] = mimeType;
    headers['Content-Length'] = bytes.length.toString();

    // Add metadata headers
    if (options.ttlSeconds > 0) {
      final expiresAt = DateTime.now().add(Duration(seconds: options.ttlSeconds));
      headers['x-amz-meta-expires-at'] = expiresAt.toIso8601String();
    }

    final response = await _httpClient.put(
      uri,
      headers: headers,
      body: bytes,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StorageProviderException(
        'S3 PUT error: ${response.statusCode} - ${response.body}',
      );
    }

    // Store metadata locally
    _metadataCache[key] = bundle.StorageMetadata(
      key: key,
      mimeType: mimeType,
      size: bytes.length,
      sha256: _sha256Hash(bytes),
      createdAt: DateTime.now(),
      expiresAt: options.ttlSeconds > 0
          ? DateTime.now().add(Duration(seconds: options.ttlSeconds))
          : null,
    );

    return 's3://${config.bucket}/$key';
  }

  @override
  Future<Uint8List> retrieve(String reference) async {
    final key = _extractKey(reference);
    final uri = Uri.parse('$_endpoint/$key');

    final headers = await _signRequest(
      method: 'GET',
      uri: uri,
    );

    final response = await _httpClient.get(uri, headers: headers);

    if (response.statusCode == 404) {
      throw StorageProviderException('Object not found: $reference');
    }

    if (response.statusCode != 200) {
      throw StorageProviderException(
        'S3 GET error: ${response.statusCode} - ${response.body}',
      );
    }

    return response.bodyBytes;
  }

  @override
  Future<bool> exists(String reference) async {
    final key = _extractKey(reference);
    final uri = Uri.parse('$_endpoint/$key');

    final headers = await _signRequest(
      method: 'HEAD',
      uri: uri,
    );

    final response = await _httpClient.head(uri, headers: headers);
    return response.statusCode == 200;
  }

  @override
  Future<bundle.StorageMetadata?> metadata(String reference) async {
    final key = _extractKey(reference);

    // Check cache first
    if (_metadataCache.containsKey(key)) {
      return _metadataCache[key];
    }

    final uri = Uri.parse('$_endpoint/$key');
    final headers = await _signRequest(
      method: 'HEAD',
      uri: uri,
    );

    final response = await _httpClient.head(uri, headers: headers);

    if (response.statusCode != 200) {
      return null;
    }

    final contentLength = int.tryParse(response.headers['content-length'] ?? '') ?? 0;
    final contentType = response.headers['content-type'] ?? 'application/octet-stream';
    final lastModified = response.headers['last-modified'];

    DateTime? createdAt;
    if (lastModified != null) {
      createdAt = HttpDate.parse(lastModified);
    }

    return bundle.StorageMetadata(
      key: key,
      mimeType: contentType,
      size: contentLength,
      sha256: response.headers['x-amz-meta-sha256'] ?? '',
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  @override
  Future<bool> delete(String reference) async {
    final key = _extractKey(reference);
    final uri = Uri.parse('$_endpoint/$key');

    final headers = await _signRequest(
      method: 'DELETE',
      uri: uri,
    );

    final response = await _httpClient.delete(uri, headers: headers);

    if (response.statusCode == 204 || response.statusCode == 200) {
      _metadataCache.remove(key);
      return true;
    }

    return false;
  }

  @override
  Future<List<String>> list([String? prefix]) async {
    var uri = Uri.parse('$_endpoint?list-type=2');
    if (prefix != null) {
      uri = uri.replace(queryParameters: {'list-type': '2', 'prefix': prefix});
    }

    final headers = await _signRequest(
      method: 'GET',
      uri: uri,
    );

    final response = await _httpClient.get(uri, headers: headers);

    if (response.statusCode != 200) {
      throw StorageProviderException(
        'S3 LIST error: ${response.statusCode} - ${response.body}',
      );
    }

    // Parse XML response
    final keys = <String>[];
    final keyPattern = RegExp(r'<Key>([^<]+)</Key>');
    final matches = keyPattern.allMatches(response.body);

    for (final match in matches) {
      keys.add('s3://${config.bucket}/${match.group(1)}');
    }

    return keys;
  }

  String _extractKey(String reference) {
    if (reference.startsWith('s3://')) {
      final parts = reference.substring(5).split('/');
      return parts.skip(1).join('/');
    }
    return reference;
  }

  String _sha256Hash(List<int> data) {
    return sha256.convert(data).toString();
  }

  Future<Map<String, String>> _signRequest({
    required String method,
    required Uri uri,
    String? contentType,
    List<int>? body,
  }) async {
    final now = DateTime.now().toUtc();
    final dateStamp = _formatDateStamp(now);
    final amzDate = _formatAmzDate(now);

    final host = uri.host;
    final region = config.region ?? 'us-east-1';
    const service = 's3';

    final payloadHash = body != null ? _sha256Hash(body) : _sha256Hash([]);

    final canonicalHeaders = StringBuffer();
    canonicalHeaders.writeln('host:$host');
    canonicalHeaders.writeln('x-amz-content-sha256:$payloadHash');
    canonicalHeaders.writeln('x-amz-date:$amzDate');

    const signedHeaders = 'host;x-amz-content-sha256;x-amz-date';

    final canonicalRequest = '$method\n'
        '${uri.path}\n'
        '${uri.query}\n'
        '${canonicalHeaders.toString()}\n'
        '$signedHeaders\n'
        '$payloadHash';

    const algorithm = 'AWS4-HMAC-SHA256';
    final credentialScope = '$dateStamp/$region/$service/aws4_request';
    final canonicalRequestHash = sha256.convert(utf8.encode(canonicalRequest)).toString();

    final stringToSign = '$algorithm\n'
        '$amzDate\n'
        '$credentialScope\n'
        '$canonicalRequestHash';

    final signature = _calculateSignature(
      config.secretKey ?? config.accessKey,
      dateStamp,
      region,
      service,
      stringToSign,
    );

    final authorization = '$algorithm '
        'Credential=${config.accessKey}/$credentialScope, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature';

    return {
      'Host': host,
      'x-amz-date': amzDate,
      'x-amz-content-sha256': payloadHash,
      'Authorization': authorization,
    };
  }

  String _formatDateStamp(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }

  String _formatAmzDate(DateTime date) {
    return '${_formatDateStamp(date)}T'
        '${date.hour.toString().padLeft(2, '0')}'
        '${date.minute.toString().padLeft(2, '0')}'
        '${date.second.toString().padLeft(2, '0')}Z';
  }

  String _calculateSignature(
    String secretKey,
    String dateStamp,
    String region,
    String service,
    String stringToSign,
  ) {
    final kDate = _hmacSha256(utf8.encode('AWS4$secretKey'), utf8.encode(dateStamp));
    final kRegion = _hmacSha256(kDate, utf8.encode(region));
    final kService = _hmacSha256(kRegion, utf8.encode(service));
    final kSigning = _hmacSha256(kService, utf8.encode('aws4_request'));

    return _hmacSha256Hex(kSigning, utf8.encode(stringToSign));
  }

  List<int> _hmacSha256(List<int> key, List<int> data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(data).bytes;
  }

  String _hmacSha256Hex(List<int> key, List<int> data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(data).toString();
  }

  @override
  Future<void> close() async {
    _httpClient.close();
    _metadataCache.clear();
    await super.close();
  }
}

/// HTTP date parsing helper.
class HttpDate {
  static DateTime parse(String date) {
    // Parse HTTP date format: "Sun, 06 Nov 1994 08:49:37 GMT"
    try {
      return DateTime.parse(date);
    } catch (_) {
      // Fallback for HTTP date format
      final parts = date.split(' ');
      if (parts.length >= 4) {
        final day = int.tryParse(parts[1]) ?? 1;
        final month = _parseMonth(parts[2]);
        final year = int.tryParse(parts[3]) ?? DateTime.now().year;
        return DateTime(year, month, day);
      }
      return DateTime.now();
    }
  }

  static int _parseMonth(String month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final index = months.indexOf(month);
    return index >= 0 ? index + 1 : 1;
  }
}
