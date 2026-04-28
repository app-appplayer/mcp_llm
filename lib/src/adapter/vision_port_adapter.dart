/// Vision Port Adapter - Bridges VisionProvider with mcp_bundle.VisionPort.
library;

import 'package:mcp_bundle/ports.dart' as bundle;

import '../providers/vision/vision_provider.dart';
import '../providers/vision/google_vision_provider.dart';
import '../providers/vision/openai_vision_provider.dart';

/// Adapter that implements mcp_bundle's VisionPort using mcp_llm's VisionProvider.
///
/// Converts between Contract Layer types (mcp_bundle) and mcp_llm internal types.
///
/// Usage:
/// ```dart
/// import 'package:mcp_llm/mcp_llm.dart';
/// import 'package:mcp_bundle/ports.dart' as bundle;
///
/// // Create vision provider
/// final provider = GoogleVisionProvider();
/// await provider.initialize(VisionProviderConfig(apiKey: '...'));
///
/// // Create adapter implementing bundle.VisionPort
/// final visionPort = VisionPortAdapter(provider);
///
/// // Use with mcp_ingest
/// final ingestPorts = IngestPorts(vision: visionPort, ...);
/// ```
class VisionPortAdapter implements bundle.VisionPort {
  /// The underlying mcp_llm vision provider.
  final VisionProvider _provider;

  /// Create an adapter wrapping a VisionProvider.
  ///
  /// [provider] - The mcp_llm vision provider to wrap.
  VisionPortAdapter(this._provider);

  @override
  Future<bundle.VisionResult> describe(
    Stream<List<int>> imageData,
    bundle.VisionOptions options,
  ) {
    return _provider.describe(imageData, options);
  }

  @override
  Future<bool> isAvailable() {
    return _provider.isAvailable();
  }
}

/// Factory for creating VisionPortAdapter instances.
class VisionPortAdapterFactory {
  /// Create an adapter for Google Vision.
  static Future<VisionPortAdapter> google({
    required String apiKey,
  }) async {
    final provider = GoogleVisionProvider();
    await provider.initialize(VisionProviderConfig(apiKey: apiKey));
    return VisionPortAdapter(provider);
  }

  /// Create an adapter for OpenAI Vision.
  static Future<VisionPortAdapter> openai({
    required String apiKey,
    String model = 'gpt-4-vision-preview',
  }) async {
    final provider = OpenAIVisionProvider(model: model);
    await provider.initialize(VisionProviderConfig(apiKey: apiKey));
    return VisionPortAdapter(provider);
  }
}
