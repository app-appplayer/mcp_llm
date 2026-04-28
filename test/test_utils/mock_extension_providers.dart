/// Mock Extension Providers for testing.
///
/// Provides mock implementations of VisionProvider, AsrProvider, OcrProvider,
/// and BinaryStorageProvider for unit testing.
library;

import 'dart:typed_data';

import 'package:mcp_bundle/ports.dart' as bundle;
import 'package:mcp_llm/mcp_llm.dart';

// =============================================================================
// Mock Vision Provider
// =============================================================================

/// Mock implementation of VisionProvider for testing.
class MockVisionProvider implements VisionProvider {
  bool _initialized = false;
  bool _shouldFail = false;
  String _mockDescription = 'A test image description';
  List<bundle.VisionLabel>? _mockLabels;

  MockVisionProvider({
    bool shouldFail = false,
    String mockDescription = 'A test image description',
    List<bundle.VisionLabel>? mockLabels,
  })  : _shouldFail = shouldFail,
        _mockDescription = mockDescription,
        _mockLabels = mockLabels;

  /// Configure mock to fail on next operation.
  void setFailure(bool shouldFail) {
    _shouldFail = shouldFail;
  }

  /// Set mock description to return.
  void setMockDescription(String description) {
    _mockDescription = description;
  }

  /// Set mock labels to return.
  void setMockLabels(List<bundle.VisionLabel> labels) {
    _mockLabels = labels;
  }

  @override
  String get id => 'mock-vision';

  @override
  Future<void> initialize(VisionProviderConfig config) async {
    _initialized = true;
  }

  @override
  Future<void> close() async {
    _initialized = false;
  }

  @override
  Future<bool> isAvailable() async => _initialized;

  @override
  Future<bundle.VisionResult> describe(
    Stream<List<int>> imageData,
    bundle.VisionOptions options,
  ) async {
    if (_shouldFail) {
      throw Exception('Mock vision provider failure');
    }

    // Consume the stream
    final bytes = <int>[];
    await for (final chunk in imageData) {
      bytes.addAll(chunk);
    }

    final stopwatch = Stopwatch()..start();
    await Future.delayed(const Duration(milliseconds: 10));
    stopwatch.stop();

    return bundle.VisionResult(
      description: _mockDescription,
      labels: _mockLabels ??
          [
            const bundle.VisionLabel(name: 'test', confidence: 0.95),
            const bundle.VisionLabel(name: 'mock', confidence: 0.90),
          ],
      confidence: 0.92,
      processingTime: stopwatch.elapsed,
    );
  }
}

// =============================================================================
// Mock ASR Provider
// =============================================================================

/// Mock implementation of AsrProvider for testing.
class MockAsrProvider implements AsrProvider {
  bool _initialized = false;
  bool _shouldFail = false;
  String _mockText = 'This is a test transcription.';
  final List<bundle.AsrSegment>? _mockSegments;
  final List<String> _supportedLanguages;

  MockAsrProvider({
    bool shouldFail = false,
    String mockText = 'This is a test transcription.',
    List<bundle.AsrSegment>? mockSegments,
    List<String>? supportedLanguages,
  })  : _shouldFail = shouldFail,
        _mockText = mockText,
        _mockSegments = mockSegments,
        _supportedLanguages = supportedLanguages ?? const ['en', 'ko', 'ja'];

  /// Configure mock to fail on next operation.
  void setFailure(bool shouldFail) {
    _shouldFail = shouldFail;
  }

  /// Set mock text to return.
  void setMockText(String text) {
    _mockText = text;
  }

  @override
  String get id => 'mock-asr';

  @override
  Future<void> initialize(AsrProviderConfig config) async {
    _initialized = true;
  }

  @override
  Future<void> close() async {
    _initialized = false;
  }

  @override
  Future<bool> isAvailable() async => _initialized;

  @override
  Future<List<String>> supportedLanguages() async => _supportedLanguages;

  @override
  Future<bundle.AsrResult> transcribe(
    Stream<List<int>> audioData,
    bundle.AsrOptions options,
  ) async {
    if (_shouldFail) {
      throw AsrProviderException('Mock ASR provider failure');
    }

    // Consume the stream
    final bytes = <int>[];
    await for (final chunk in audioData) {
      bytes.addAll(chunk);
    }

    final stopwatch = Stopwatch()..start();
    await Future.delayed(const Duration(milliseconds: 10));
    stopwatch.stop();

    return bundle.AsrResult(
      text: _mockText,
      confidence: 0.95,
      language: options.language,
      segments: _mockSegments ??
          [
            bundle.AsrSegment(
              text: _mockText,
              startTime: Duration.zero,
              endTime: const Duration(seconds: 5),
              confidence: 0.95,
            ),
          ],
      audioDuration: const Duration(seconds: 5),
      processingTime: stopwatch.elapsed,
    );
  }
}

// =============================================================================
// Mock OCR Provider
// =============================================================================

/// Mock implementation of OcrProvider for testing.
class MockOcrProvider implements OcrProvider {
  bool _initialized = false;
  bool _shouldFail = false;
  String _mockText = 'Recognized text from image.';
  final List<bundle.OcrRegion>? _mockRegions;
  final List<String> _supportedLanguages;

  MockOcrProvider({
    bool shouldFail = false,
    String mockText = 'Recognized text from image.',
    List<bundle.OcrRegion>? mockRegions,
    List<String>? supportedLanguages,
  })  : _shouldFail = shouldFail,
        _mockText = mockText,
        _mockRegions = mockRegions,
        _supportedLanguages = supportedLanguages ?? const ['eng', 'kor', 'jpn'];

  /// Configure mock to fail on next operation.
  void setFailure(bool shouldFail) {
    _shouldFail = shouldFail;
  }

  /// Set mock text to return.
  void setMockText(String text) {
    _mockText = text;
  }

  @override
  String get id => 'mock-ocr';

  @override
  Future<void> initialize(OcrProviderConfig config) async {
    _initialized = true;
  }

  @override
  Future<void> close() async {
    _initialized = false;
  }

  @override
  Future<bool> isAvailable() async => _initialized;

  @override
  Future<List<String>> supportedLanguages() async => _supportedLanguages;

  @override
  Future<bundle.OcrResult> recognize(
    Stream<List<int>> imageData,
    bundle.OcrOptions options,
  ) async {
    if (_shouldFail) {
      throw OcrProviderException('Mock OCR provider failure');
    }

    // Consume the stream
    final bytes = <int>[];
    await for (final chunk in imageData) {
      bytes.addAll(chunk);
    }

    final stopwatch = Stopwatch()..start();
    await Future.delayed(const Duration(milliseconds: 10));
    stopwatch.stop();

    return bundle.OcrResult(
      text: _mockText,
      confidence: 0.98,
      language: options.language,
      regions: _mockRegions ??
          [
            bundle.OcrRegion(
              text: _mockText,
              confidence: 0.98,
              boundingBox: const bundle.BoundingBox(
                x: 10,
                y: 20,
                width: 100,
                height: 30,
              ),
            ),
          ],
      processingTime: stopwatch.elapsed,
    );
  }
}

// =============================================================================
// Mock Storage Provider
// =============================================================================

/// Mock implementation of BinaryStorageProvider for testing.
class MockBinaryStorageProvider implements BinaryStorageProvider {
  static int _globalCounter = 0;
  bool _initialized = false;
  bool _shouldFail = false;

  final Map<String, Uint8List> _storage = {};
  final Map<String, bundle.StorageMetadata> _metadata = {};

  MockBinaryStorageProvider({
    bool shouldFail = false,
  }) : _shouldFail = shouldFail;

  /// Configure mock to fail on next operation.
  void setFailure(bool shouldFail) {
    _shouldFail = shouldFail;
  }

  /// Clear all stored data.
  void clear() {
    _storage.clear();
    _metadata.clear();
  }

  @override
  String get id => 'mock-storage';

  @override
  Future<void> initialize(StorageProviderConfig config) async {
    _initialized = true;
  }

  @override
  Future<void> close() async {
    _initialized = false;
    _storage.clear();
    _metadata.clear();
  }

  @override
  Future<bool> isAvailable() async => _initialized;

  @override
  Future<String> store(
    Stream<List<int>> data,
    String mimeType, [
    bundle.StorageOptions options = const bundle.StorageOptions(),
  ]) async {
    if (_shouldFail) {
      throw StorageProviderException('Mock storage provider failure');
    }

    // Collect bytes
    final bytes = <int>[];
    await for (final chunk in data) {
      bytes.addAll(chunk);
    }
    final uint8Data = Uint8List.fromList(bytes);

    // Generate unique reference using counter
    final prefix = options.prefix ?? '';
    _globalCounter++;
    final reference =
        '${prefix}mock://${DateTime.now().millisecondsSinceEpoch}_$_globalCounter';

    // Store data
    _storage[reference] = uint8Data;
    _metadata[reference] = bundle.StorageMetadata(
      key: reference,
      mimeType: mimeType,
      size: uint8Data.length,
      sha256: _generateHash(uint8Data),
      createdAt: DateTime.now(),
    );

    return reference;
  }

  @override
  Future<Uint8List> retrieve(String reference) async {
    if (_shouldFail) {
      throw StorageProviderException('Mock storage provider failure');
    }

    final data = _storage[reference];
    if (data == null) {
      throw StorageProviderException('Not found: $reference');
    }
    return data;
  }

  @override
  Future<bool> exists(String reference) async {
    return _storage.containsKey(reference);
  }

  @override
  Future<bundle.StorageMetadata?> metadata(String reference) async {
    return _metadata[reference];
  }

  @override
  Future<bool> delete(String reference) async {
    if (_shouldFail) {
      throw StorageProviderException('Mock storage provider failure');
    }

    _storage.remove(reference);
    _metadata.remove(reference);
    return true;
  }

  @override
  Future<List<String>> list([String? prefix]) async {
    if (prefix == null) {
      return _storage.keys.toList();
    }
    return _storage.keys.where((k) => k.startsWith(prefix)).toList();
  }

  String _generateHash(Uint8List data) {
    int hash = 0;
    for (int i = 0; i < data.length; i++) {
      hash = (hash * 31 + data[i]) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

// =============================================================================
// Helper Functions
// =============================================================================

/// Create a stream from bytes for testing.
Stream<List<int>> bytesToStream(List<int> bytes) async* {
  yield bytes;
}

/// Create a stream from Uint8List for testing.
Stream<List<int>> uint8ListToStream(Uint8List data) async* {
  yield data;
}
