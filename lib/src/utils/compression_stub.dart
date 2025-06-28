import 'compression_interface.dart';

/// Stub implementation for unsupported platforms
class CompressionStub implements CompressionInterface {
  @override
  Future<List<int>> compress(List<int> input) async {
    // No compression on unsupported platforms, return as-is
    return input;
  }

  @override
  Future<List<int>> decompress(List<int> input) async {
    // No decompression on unsupported platforms, return as-is
    return input;
  }
}

/// Factory function to create compression stub
CompressionInterface createCompression() => CompressionStub();