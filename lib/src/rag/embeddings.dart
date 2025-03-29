import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Represents a document's embedding vector
class Embedding {
  /// The embedding vector values
  final List<double> vector;

  /// The embedding dimension
  int get dimension => vector.length;

  Embedding(this.vector);

  /// Create an embedding from JSON
  factory Embedding.fromJson(List<dynamic> json) {
    return Embedding(json.cast<double>());
  }

  /// Convert embedding to JSON
  List<double> toJson() => vector;

  /// Calculate cosine similarity with another embedding
  double cosineSimilarity(Embedding other) {
    if (dimension != other.dimension) {
      throw ArgumentError('Embeddings must have the same dimension');
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (var i = 0; i < dimension; i++) {
      dotProduct += vector[i] * other.vector[i];
      normA += vector[i] * vector[i];
      normB += other.vector[i] * other.vector[i];
    }

    if (normA == 0.0 || normB == 0.0) {
      return 0.0;
    }

    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  /// Calculate Euclidean distance with another embedding
  double euclideanDistance(Embedding other) {
    if (dimension != other.dimension) {
      throw ArgumentError('Embeddings must have the same dimension');
    }

    double sum = 0.0;

    for (var i = 0; i < dimension; i++) {
      double diff = vector[i] - other.vector[i];
      sum += diff * diff;
    }

    return sqrt(sum);
  }

  /// Calculate dot product with another embedding
  double dotProduct(Embedding other) {
    if (dimension != other.dimension) {
      throw ArgumentError('Embeddings must have the same dimension');
    }

    double result = 0.0;

    for (var i = 0; i < dimension; i++) {
      result += vector[i] * other.vector[i];
    }

    return result;
  }

  /// Normalize the embedding vector (L2 normalization)
  Embedding normalize() {
    double sum = 0.0;

    for (final value in vector) {
      sum += value * value;
    }

    final norm = sqrt(sum);
    if (norm == 0.0) {
      return Embedding(List.filled(dimension, 0.0));
    }

    final normalizedVector = vector.map((value) => value / norm).toList();
    return Embedding(normalizedVector);
  }

  /// Encode embedding to binary format
  List<int> toBinary() {
    final buffer = ByteData(dimension * 4);

    for (var i = 0; i < dimension; i++) {
      buffer.setFloat32(i * 4, vector[i], Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  /// Create embedding from binary format
  factory Embedding.fromBinary(List<int> data) {
    final byteData = ByteData.view(Uint8List.fromList(data).buffer);
    final dimension = data.length ~/ 4;
    final vector = List<double>.filled(dimension, 0.0);

    for (var i = 0; i < dimension; i++) {
      vector[i] = byteData.getFloat32(i * 4, Endian.little);
    }

    return Embedding(vector);
  }

  /// Encode embedding to base64 string
  String toBase64() {
    return base64Encode(toBinary());
  }

  /// Create embedding from base64 string
  factory Embedding.fromBase64(String base64Str) {
    final data = base64Decode(base64Str);
    return Embedding.fromBinary(data);
  }
}

/// Utilities for working with embeddings
class EmbeddingUtils {
  /// Average multiple embeddings with optional weights
  static Embedding average(List<Embedding> embeddings, [List<double>? weights]) {
    if (embeddings.isEmpty) {
      throw ArgumentError('Cannot average empty embeddings list');
    }

    final dimension = embeddings.first.dimension;

    // Check all embeddings have the same dimension
    for (final emb in embeddings) {
      if (emb.dimension != dimension) {
        throw ArgumentError('All embeddings must have the same dimension');
      }
    }

    // Use equal weights if not provided
    final actualWeights = weights ?? List.filled(embeddings.length, 1.0);

    // Check weights count matches embeddings count
    if (actualWeights.length != embeddings.length) {
      throw ArgumentError('Number of weights must match number of embeddings');
    }

    // Calculate weighted sum
    final result = List.filled(dimension, 0.0);
    double totalWeight = 0.0;

    for (var i = 0; i < embeddings.length; i++) {
      final weight = actualWeights[i];
      totalWeight += weight;

      for (var j = 0; j < dimension; j++) {
        result[j] += embeddings[i].vector[j] * weight;
      }
    }

    // Normalize by total weight
    if (totalWeight > 0) {
      for (var i = 0; i < dimension; i++) {
        result[i] /= totalWeight;
      }
    }

    return Embedding(result);
  }

  /// Create a random embedding for testing
  static Embedding random(int dimension, {int? seed}) {
    final random = Random(seed);
    final vector = List.generate(dimension, (_) => random.nextDouble() * 2 - 1);
    return Embedding(vector);
  }

  /// Compute pairwise similarities for a list of embeddings
  static List<List<double>> pairwiseSimilarities(List<Embedding> embeddings) {
    final n = embeddings.length;
    final result = List.generate(
      n, (_) => List.filled(n, 0.0),
    );

    for (var i = 0; i < n; i++) {
      for (var j = i; j < n; j++) {
        final similarity = embeddings[i].cosineSimilarity(embeddings[j]);
        result[i][j] = similarity;
        result[j][i] = similarity; // Matrix is symmetric
      }
    }

    return result;
  }
}