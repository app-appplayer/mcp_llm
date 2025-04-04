import 'dart:async';
import 'embeddings.dart';
import 'document_store.dart';

/// Base interface for vector stores
abstract class VectorStore {
  /// Initialize the vector store
  Future<void> initialize();

  /// Store a document embedding
  Future<void> storeEmbedding(String id, Embedding embedding, {
    Map<String, dynamic> metadata = const {},
    String? namespace,
  });

  /// Store multiple document embeddings in batch
  Future<void> storeEmbeddingBatch(Map<String, Embedding> embeddings, {
    Map<String, Map<String, dynamic>> metadata = const {},
    String? namespace,
  });

  /// Find similar embeddings to the query embedding
  Future<List<ScoredEmbedding>> findSimilar(
      Embedding queryEmbedding, {
        int limit = 5,
        double? scoreThreshold,
        String? namespace,
        Map<String, dynamic> filters = const {},
      });

  /// Delete an embedding by ID
  Future<bool> deleteEmbedding(String id, {String? namespace});

  /// Delete multiple embeddings by ID
  Future<int> deleteEmbeddingBatch(List<String> ids, {String? namespace});

  /// Check if an embedding exists
  Future<bool> exists(String id, {String? namespace});

  /// Get an embedding by ID
  Future<Embedding?> getEmbedding(String id, {String? namespace});

  /// Create a namespace (collection)
  Future<void> createNamespace(String namespace, {Map<String, dynamic> options = const {}});

  /// Delete a namespace (collection)
  Future<bool> deleteNamespace(String namespace);

  /// List all namespaces (collections)
  Future<List<String>> listNamespaces();

  /// Upsert a document - store both document and embedding
  Future<void> upsertDocument(Document document, {String? namespace});

  /// Upsert multiple documents in batch
  Future<void> upsertDocumentBatch(List<Document> documents, {String? namespace});

  /// Get document by ID
  Future<Document?> getDocument(String id, {String? namespace});

  /// Find similar documents to the query embedding
  Future<List<ScoredDocument>> findSimilarDocuments(
      Embedding queryEmbedding, {
        int limit = 5,
        double? scoreThreshold,
        String? namespace,
        Map<String, dynamic> filters = const {},
      });

  /// Close and clean up resources
  Future<void> close();
}

/// Scored embedding result
class ScoredEmbedding {
  /// Embedding ID
  final String id;

  /// Embedding vector
  final Embedding embedding;

  /// Similarity score
  final double score;

  /// Associated metadata
  final Map<String, dynamic> metadata;

  ScoredEmbedding({
    required this.id,
    required this.embedding,
    required this.score,
    this.metadata = const {},
  });
}

/// Scored document result
class ScoredDocument {
  /// Document
  final Document document;

  /// Similarity score
  final double score;

  ScoredDocument(this.document, this.score);
}

/// Factory for creating vector stores
abstract class VectorStoreFactory {
  /// Create a vector store instance with the given configuration
  VectorStore createVectorStore(Map<String, dynamic> config);
}

/// Configuration options for vector stores
class VectorStoreConfig {
  /// API key for the vector store service
  final String? apiKey;

  /// Base URL for the vector store service (if applicable)
  final String? baseUrl;

  /// Environment (e.g., production, staging)
  final String? environment;

  /// Default namespace/collection name
  final String? defaultNamespace;

  /// Vector dimension
  final int dimension;

  /// Additional provider-specific options
  final Map<String, dynamic> options;

  VectorStoreConfig({
    this.apiKey,
    this.baseUrl,
    this.environment,
    this.defaultNamespace,
    this.dimension = 1536,
    this.options = const {},
  });

  /// Create a copy with modified values
  VectorStoreConfig copyWith({
    String? apiKey,
    String? baseUrl,
    String? environment,
    String? defaultNamespace,
    int? dimension,
    Map<String, dynamic>? options,
  }) {
    return VectorStoreConfig(
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      environment: environment ?? this.environment,
      defaultNamespace: defaultNamespace ?? this.defaultNamespace,
      dimension: dimension ?? this.dimension,
      options: options ?? Map<String, dynamic>.from(this.options),
    );
  }
}

/// Registry for vector store implementations
class VectorStoreRegistry {
  static final Map<String, VectorStoreFactory> _factories = {};

  /// Register a vector store factory
  static void registerFactory(String name, VectorStoreFactory factory) {
    _factories[name] = factory;
  }

  /// Get a vector store factory by name
  static VectorStoreFactory? getFactory(String name) {
    return _factories[name];
  }

  /// Create a vector store instance with the given configuration
  static VectorStore createVectorStore(String name, Map<String, dynamic> config) {
    final factory = getFactory(name);
    if (factory == null) {
      throw Exception('No vector store factory registered for name: $name');
    }
    return factory.createVectorStore(config);
  }

  /// List all registered vector store factory names
  static List<String> getRegisteredFactories() {
    return _factories.keys.toList();
  }
}