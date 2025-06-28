import 'dart:io';
import 'compression_interface.dart';

/// IO implementation of compression using gzip
class CompressionIo implements CompressionInterface {
  @override
  Future<List<int>> compress(List<int> input) async {
    return gzip.encode(input);
  }

  @override
  Future<List<int>> decompress(List<int> input) async {
    return gzip.decode(input);
  }
}

/// Factory function to create IO compression
CompressionInterface createCompression() => CompressionIo();