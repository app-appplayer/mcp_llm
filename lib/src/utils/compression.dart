import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Compression configuration options
class CompressionOptions {
  /// Whether to compress strings
  final bool compressStrings;

  /// Whether to compress binary data
  final bool compressBinaryData;

  /// Minimum size for compression (bytes)
  final int minSizeForCompression;

  CompressionOptions({
    this.compressStrings = true,
    this.compressBinaryData = true,
    this.minSizeForCompression = 1024, // 1KB or more
  });
}

/// Data compression utility
class DataCompressor {
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
    final inputData = Uint8List.fromList(input);

    // Use GZIP compression
    final result = gzip.encode(inputData);
    return result;
  }

  /// Decompress binary data
  static Future<List<int>> decompressData(List<int> input) async {
    final compressedData = Uint8List.fromList(input);

    // Decompress GZIP
    final result = gzip.decode(compressedData);
    return result;
  }

  /// Calculate compression ratio
  static double calculateCompressionRatio(
      int originalSize, int compressedSize) {
    if (originalSize == 0) return 0.0;
    return (originalSize - compressedSize) / originalSize;
  }
}
