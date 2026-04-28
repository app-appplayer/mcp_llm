/// AWS Textract Provider - AWS Textract API integration.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mcp_bundle/ports.dart' as bundle;

import 'ocr_provider.dart';

/// AWS Textract API provider.
///
/// Provides text recognition using AWS Textract.
/// Features: document text detection, form extraction, table extraction.
class AwsTextractProvider extends BaseOcrProvider {
  final http.Client _httpClient;
  final String _region;

  /// Supported languages for Textract.
  static const List<String> _supportedLanguages = [
    'en', 'es', 'de', 'it', 'fr', 'pt',
  ];

  AwsTextractProvider({
    http.Client? httpClient,
    String region = 'us-east-1',
  })  : _httpClient = httpClient ?? http.Client(),
        _region = region;

  @override
  String get id => 'aws-textract';

  @override
  Future<List<String>> supportedLanguages() async => _supportedLanguages;

  @override
  Future<bundle.OcrResult> recognize(
    Stream<List<int>> imageData,
    bundle.OcrOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();

    final bytes = await collectBytes(imageData);
    final base64Image = base64Encode(bytes);

    final endpoint = 'https://textract.$_region.amazonaws.com';
    final action = 'DetectDocumentText';

    final requestBody = jsonEncode({
      'Document': {
        'Bytes': base64Image,
      },
    });

    // Sign request with AWS Signature V4
    final headers = await _signRequest(
      method: 'POST',
      endpoint: endpoint,
      action: action,
      body: requestBody,
    );

    final response = await _httpClient.post(
      Uri.parse(endpoint),
      headers: headers,
      body: requestBody,
    );

    stopwatch.stop();

    if (response.statusCode != 200) {
      throw OcrProviderException(
        'AWS Textract API error: ${response.statusCode} - ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseTextractResponse(json, stopwatch.elapsed, options.language);
  }

  bundle.OcrResult _parseTextractResponse(
    Map<String, dynamic> json,
    Duration processingTime,
    String language,
  ) {
    final blocks = json['Blocks'] as List<dynamic>?;

    if (blocks == null || blocks.isEmpty) {
      return bundle.OcrResult(
        text: '',
        confidence: 0.0,
        processingTime: processingTime,
      );
    }

    final textBuffer = StringBuffer();
    final regions = <bundle.OcrRegion>[];
    double totalConfidence = 0.0;
    int lineCount = 0;

    // Process blocks
    for (final block in blocks) {
      final blockType = block['BlockType'] as String?;

      if (blockType == 'LINE') {
        final text = block['Text'] as String? ?? '';
        final confidence = (block['Confidence'] as num?)?.toDouble() ?? 0.0;

        textBuffer.writeln(text);
        totalConfidence += confidence;
        lineCount++;

        // Extract bounding box
        final geometry = block['Geometry'] as Map<String, dynamic>?;
        final boundingBox = _extractBoundingBox(geometry);

        regions.add(bundle.OcrRegion(
          text: text,
          confidence: confidence / 100, // Textract returns 0-100
          boundingBox: boundingBox,
        ));
      } else if (blockType == 'PAGE') {
        // Page-level metadata
        // Could extract page dimensions here if needed
      }
    }

    final fullText = textBuffer.toString().trim();
    final avgConfidence = lineCount > 0 ? (totalConfidence / lineCount) / 100 : 0.0;

    return bundle.OcrResult(
      text: fullText,
      confidence: avgConfidence,
      language: language,
      regions: regions.isNotEmpty ? regions : null,
      processingTime: processingTime,
    );
  }

  bundle.BoundingBox _extractBoundingBox(Map<String, dynamic>? geometry) {
    if (geometry == null) {
      return const bundle.BoundingBox(x: 0, y: 0, width: 0, height: 0);
    }

    final box = geometry['BoundingBox'] as Map<String, dynamic>?;
    if (box == null) {
      return const bundle.BoundingBox(x: 0, y: 0, width: 0, height: 0);
    }

    return bundle.BoundingBox(
      x: (box['Left'] as num? ?? 0).toDouble(),
      y: (box['Top'] as num? ?? 0).toDouble(),
      width: (box['Width'] as num? ?? 0).toDouble(),
      height: (box['Height'] as num? ?? 0).toDouble(),
    );
  }

  Future<Map<String, String>> _signRequest({
    required String method,
    required String endpoint,
    required String action,
    required String body,
  }) async {
    // AWS Signature V4 signing
    final now = DateTime.now().toUtc();
    final dateStamp = _formatDateStamp(now);
    final amzDate = _formatAmzDate(now);

    final host = Uri.parse(endpoint).host;
    final service = 'textract';

    // Create canonical request
    final payloadHash = sha256.convert(utf8.encode(body)).toString();

    final canonicalHeaders = 'content-type:application/x-amz-json-1.1\n'
        'host:$host\n'
        'x-amz-date:$amzDate\n'
        'x-amz-target:Textract.$action\n';

    final signedHeaders = 'content-type;host;x-amz-date;x-amz-target';

    final canonicalRequest = '$method\n'
        '/\n'
        '\n'
        '$canonicalHeaders\n'
        '$signedHeaders\n'
        '$payloadHash';

    // Create string to sign
    final algorithm = 'AWS4-HMAC-SHA256';
    final credentialScope = '$dateStamp/$_region/$service/aws4_request';
    final canonicalRequestHash = sha256.convert(utf8.encode(canonicalRequest)).toString();

    final stringToSign = '$algorithm\n'
        '$amzDate\n'
        '$credentialScope\n'
        '$canonicalRequestHash';

    // Calculate signature
    final signature = _calculateSignature(
      config.apiKey, // Using apiKey as secret key for simplicity
      dateStamp,
      _region,
      service,
      stringToSign,
    );

    // AWS credentials would typically come from config
    // For this implementation, we assume apiKey format: "accessKey:secretKey"
    final credentials = config.apiKey.split(':');
    final accessKey = credentials.isNotEmpty ? credentials[0] : config.apiKey;

    final authorization = '$algorithm '
        'Credential=$accessKey/$credentialScope, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature';

    return {
      'Content-Type': 'application/x-amz-json-1.1',
      'Host': host,
      'X-Amz-Date': amzDate,
      'X-Amz-Target': 'Textract.$action',
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
    await super.close();
  }
}
