/// Cloud Provider Registry - Unified provider management for mcp_llm.
///
/// Provides a central registry for all cloud AI providers (LLM, Vision, ASR, OCR, Storage).
library;

import '../core/llm_interface.dart';
import '../providers/vision/vision_provider.dart';
import '../providers/vision/google_vision_provider.dart';
import '../providers/vision/openai_vision_provider.dart';
import '../providers/asr/asr_provider.dart';
import '../providers/asr/openai_whisper_provider.dart';
import '../providers/asr/google_speech_provider.dart';
import '../providers/ocr/ocr_provider.dart';
import '../providers/ocr/google_vision_ocr_provider.dart';
import '../providers/ocr/aws_textract_provider.dart';
import '../providers/storage/binary_storage_provider.dart';

/// Central registry for all cloud AI providers.
///
/// Manages LLM, Vision, ASR, OCR, and Storage providers with a unified interface.
///
/// Usage:
/// ```dart
/// // Create registry with default providers
/// final registry = await CloudProviderRegistry.defaults(
///   anthropicApiKey: 'sk-...',
///   openAiApiKey: 'sk-...',
///   googleApiKey: 'AIza...',
/// );
///
/// // Get providers by ID
/// final llm = registry.getLlm('claude');
/// final vision = registry.getVision('google');
/// final asr = registry.getAsr('whisper');
/// ```
class CloudProviderRegistry {
  final Map<String, LlmProvider> _llmProviders = {};
  final Map<String, VisionProvider> _visionProviders = {};
  final Map<String, AsrProvider> _asrProviders = {};
  final Map<String, OcrProvider> _ocrProviders = {};
  final Map<String, BinaryStorageProvider> _storageProviders = {};

  /// Create an empty registry.
  CloudProviderRegistry();

  /// Register an LLM provider.
  void registerLlm(String id, LlmProvider provider) {
    _llmProviders[id] = provider;
  }

  /// Register a Vision provider.
  void registerVision(String id, VisionProvider provider) {
    _visionProviders[id] = provider;
  }

  /// Register an ASR provider.
  void registerAsr(String id, AsrProvider provider) {
    _asrProviders[id] = provider;
  }

  /// Register an OCR provider.
  void registerOcr(String id, OcrProvider provider) {
    _ocrProviders[id] = provider;
  }

  /// Register a Storage provider.
  void registerStorage(String id, BinaryStorageProvider provider) {
    _storageProviders[id] = provider;
  }

  /// Get an LLM provider by ID.
  LlmProvider? getLlm(String id) => _llmProviders[id];

  /// Get a Vision provider by ID.
  VisionProvider? getVision(String id) => _visionProviders[id];

  /// Get an ASR provider by ID.
  AsrProvider? getAsr(String id) => _asrProviders[id];

  /// Get an OCR provider by ID.
  OcrProvider? getOcr(String id) => _ocrProviders[id];

  /// Get a Storage provider by ID.
  BinaryStorageProvider? getStorage(String id) => _storageProviders[id];

  /// Get all registered LLM provider IDs.
  List<String> get llmIds => _llmProviders.keys.toList();

  /// Get all registered Vision provider IDs.
  List<String> get visionIds => _visionProviders.keys.toList();

  /// Get all registered ASR provider IDs.
  List<String> get asrIds => _asrProviders.keys.toList();

  /// Get all registered OCR provider IDs.
  List<String> get ocrIds => _ocrProviders.keys.toList();

  /// Get all registered Storage provider IDs.
  List<String> get storageIds => _storageProviders.keys.toList();

  /// Unregister an LLM provider.
  void unregisterLlm(String id) {
    _llmProviders.remove(id);
  }

  /// Unregister a Vision provider.
  void unregisterVision(String id) {
    _visionProviders.remove(id);
  }

  /// Unregister an ASR provider.
  void unregisterAsr(String id) {
    _asrProviders.remove(id);
  }

  /// Unregister an OCR provider.
  void unregisterOcr(String id) {
    _ocrProviders.remove(id);
  }

  /// Unregister a Storage provider.
  void unregisterStorage(String id) {
    _storageProviders.remove(id);
  }

  /// Close all providers and clear the registry.
  Future<void> close() async {
    // Close all vision providers
    for (final provider in _visionProviders.values) {
      await provider.close();
    }
    _visionProviders.clear();

    // Close all ASR providers
    for (final provider in _asrProviders.values) {
      await provider.close();
    }
    _asrProviders.clear();

    // Close all OCR providers
    for (final provider in _ocrProviders.values) {
      await provider.close();
    }
    _ocrProviders.clear();

    // Close all storage providers
    for (final provider in _storageProviders.values) {
      await provider.close();
    }
    _storageProviders.clear();

    // Note: LLM providers have their own lifecycle management
    _llmProviders.clear();
  }

  /// Create a registry with default providers for common cloud services.
  ///
  /// This factory creates and initializes providers based on the API keys provided.
  /// Only providers with valid API keys will be registered.
  ///
  /// [anthropicApiKey] - API key for Anthropic (Claude)
  /// [openAiApiKey] - API key for OpenAI (GPT-4, Whisper)
  /// [googleApiKey] - API key for Google Cloud (Vision, Speech, OCR)
  /// [awsAccessKey] - AWS access key for S3, Textract
  /// [awsSecretKey] - AWS secret key
  /// [awsRegion] - AWS region (default: us-east-1)
  static Future<CloudProviderRegistry> defaults({
    String? anthropicApiKey,
    String? openAiApiKey,
    String? googleApiKey,
    String? awsAccessKey,
    String? awsSecretKey,
    String? awsRegion,
  }) async {
    final registry = CloudProviderRegistry();

    // Register Vision providers
    if (googleApiKey != null) {
      final googleVision = GoogleVisionProvider();
      await googleVision.initialize(VisionProviderConfig(apiKey: googleApiKey));
      registry.registerVision('google', googleVision);
    }

    if (openAiApiKey != null) {
      final openaiVision = OpenAIVisionProvider();
      await openaiVision.initialize(VisionProviderConfig(apiKey: openAiApiKey));
      registry.registerVision('openai', openaiVision);
    }

    // Register ASR providers
    if (openAiApiKey != null) {
      final whisper = OpenAIWhisperProvider();
      await whisper.initialize(AsrProviderConfig(apiKey: openAiApiKey));
      registry.registerAsr('whisper', whisper);
      registry.registerAsr('openai', whisper);
    }

    if (googleApiKey != null) {
      final googleSpeech = GoogleSpeechProvider();
      await googleSpeech.initialize(AsrProviderConfig(apiKey: googleApiKey));
      registry.registerAsr('google', googleSpeech);
    }

    // Register OCR providers
    if (googleApiKey != null) {
      final googleOcr = GoogleVisionOcrProvider();
      await googleOcr.initialize(OcrProviderConfig(apiKey: googleApiKey));
      registry.registerOcr('google', googleOcr);
    }

    if (awsAccessKey != null) {
      final textract = AwsTextractProvider(region: awsRegion ?? 'us-east-1');
      await textract.initialize(OcrProviderConfig(
        apiKey: '$awsAccessKey:${awsSecretKey ?? ''}',
        region: awsRegion,
      ));
      registry.registerOcr('textract', textract);
      registry.registerOcr('aws', textract);
    }

    return registry;
  }

  /// Create an empty registry.
  factory CloudProviderRegistry.empty() {
    return CloudProviderRegistry();
  }
}
