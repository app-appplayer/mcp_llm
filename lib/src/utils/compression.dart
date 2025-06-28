import 'dart:convert';

import 'compression_interface.dart';
export 'compression_interface.dart' show CompressionOptions;

// Import platform-specific implementation
import 'compression_stub.dart'
    if (dart.library.io) 'compression_io.dart'
    if (dart.library.html) 'compression_web.dart';

/// Data compression utility
class DataCompressor {
  static final CompressionInterface _compression = createCompression();

  /// Compress string and encode as base64
  static Future<String> compressAndEncodeString(String input) async {
    final inputBytes = utf8.encode(input);
    final compressedBytes = await compressData(inputBytes);
    return base64Encode(compressedBytes);
  }

  /// Decode base64 and decompress string
  static Future<String> decodeAndDecompressString(String input) async {
    final compressedBytes = base64Decode(input);
    final outputBytes = await decompressData(compressedBytes);
    return utf8.decode(outputBytes);
  }

  /// Compress binary data
  static Future<List<int>> compressData(List<int> input) async {
    return await _compression.compress(input);
  }

  /// Decompress binary data
  static Future<List<int>> decompressData(List<int> input) async {
    return await _compression.decompress(input);
  }

  /// Calculate compression ratio
  static double calculateCompressionRatio(
      int originalSize, int compressedSize) {
    if (originalSize == 0) return 0.0;
    return (originalSize - compressedSize) / originalSize;
  }
}
