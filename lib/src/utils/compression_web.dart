import 'compression_interface.dart';

/// Web implementation of compression
/// Note: Web browsers don't have built-in gzip compression in Dart,
/// so we return data as-is. For production use, consider using a
/// JavaScript compression library via JS interop.
class CompressionWeb implements CompressionInterface {
  @override
  Future<List<int>> compress(List<int> input) async {
    // TODO: Implement web compression using JS interop or pure Dart library
    // For now, return uncompressed data
    return input;
  }

  @override
  Future<List<int>> decompress(List<int> input) async {
    // TODO: Implement web decompression using JS interop or pure Dart library
    // For now, return data as-is
    return input;
  }
}

/// Factory function to create web compression
CompressionInterface createCompression() => CompressionWeb();