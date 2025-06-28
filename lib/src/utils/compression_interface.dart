
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

/// Abstract interface for compression implementations
abstract class CompressionInterface {
  /// Compress binary data
  Future<List<int>> compress(List<int> input);

  /// Decompress binary data
  Future<List<int>> decompress(List<int> input);
}