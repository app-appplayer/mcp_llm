/// OCR Port Adapter - Bridges OcrProvider with mcp_bundle.OcrPort.
library;

import 'package:mcp_bundle/ports.dart' as bundle;

import '../providers/ocr/ocr_provider.dart';
import '../providers/ocr/google_vision_ocr_provider.dart';
import '../providers/ocr/aws_textract_provider.dart';

/// Adapter that implements mcp_bundle's OcrPort using mcp_llm's OcrProvider.
///
/// Converts between Contract Layer types (mcp_bundle) and mcp_llm internal types.
///
/// Usage:
/// ```dart
/// import 'package:mcp_llm/mcp_llm.dart';
/// import 'package:mcp_bundle/ports.dart' as bundle;
///
/// // Create OCR provider
/// final provider = GoogleVisionOcrProvider();
/// await provider.initialize(OcrProviderConfig(apiKey: '...'));
///
/// // Create adapter implementing bundle.OcrPort
/// final ocrPort = OcrPortAdapter(provider);
///
/// // Use with mcp_ingest
/// final ingestPorts = IngestPorts(ocr: ocrPort, ...);
/// ```
class OcrPortAdapter implements bundle.OcrPort {
  /// The underlying mcp_llm OCR provider.
  final OcrProvider _provider;

  /// Create an adapter wrapping an OcrProvider.
  ///
  /// [provider] - The mcp_llm OCR provider to wrap.
  OcrPortAdapter(this._provider);

  @override
  Future<bundle.OcrResult> recognize(
    Stream<List<int>> imageData,
    bundle.OcrOptions options,
  ) {
    return _provider.recognize(imageData, options);
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

/// Factory for creating OcrPortAdapter instances.
class OcrPortAdapterFactory {
  /// Create an adapter for Google Vision OCR.
  static Future<OcrPortAdapter> google({
    required String apiKey,
    String? projectId,
  }) async {
    final provider = GoogleVisionOcrProvider();
    await provider.initialize(OcrProviderConfig(
      apiKey: apiKey,
      projectId: projectId,
    ));
    return OcrPortAdapter(provider);
  }

  /// Create an adapter for AWS Textract.
  static Future<OcrPortAdapter> textract({
    required String apiKey,
    String region = 'us-east-1',
  }) async {
    final provider = AwsTextractProvider(region: region);
    await provider.initialize(OcrProviderConfig(
      apiKey: apiKey,
      region: region,
    ));
    return OcrPortAdapter(provider);
  }
}
