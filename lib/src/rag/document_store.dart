import 'dart:math';

import '../storage/storage_manager.dart';
import '../utils/logger.dart';
import 'embeddings.dart';

/// Represents a document with content and optional metadata
class Document {
  /// Unique identifier for the document
  final String id;

  /// Document title
  final String title;

  /// Document content
  final String content;

  /// Document embedding (if available)
  final List<double>? embedding;

  /// Document metadata
  final Map<String, dynamic> metadata;

  /// Collection ID this document belongs to
  final String? collectionId;

  /// Last updated timestamp
  final DateTime updatedAt;

  /// Create a document
  Document({
    String? id,
    required this.title,
    required this.content,
    this.embedding,
    this.metadata = const {},
    this.collectionId,
    DateTime? updatedAt,
  }) : id = id ?? 'doc_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}',
        updatedAt = updatedAt ?? DateTime.now();

  /// Create a document from JSON
  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      embedding: json['embedding'] != null
          ? (json['embedding'] as List<dynamic>).cast<double>()
          : null,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : {},
      collectionId: json['collection_id'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  /// Convert document to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'embedding': embedding,
      'metadata': metadata,
      'collection_id': collectionId,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy of this document with an embedding
  Document withEmbedding(List<double> newEmbedding) {
    return Document(
      id: id,
      title: title,
      content: content,
      embedding: newEmbedding,
      metadata: Map<String, dynamic>.from(metadata),
      collectionId: collectionId,
      updatedAt: updatedAt,
    );
  }

  /// Create a copy of this document with a collection ID
  Document withCollectionId(String newCollectionId) {
    return Document(
      id: id,
      title: title,
      content: content,
      embedding: embedding,
      metadata: Map<String, dynamic>.from(metadata),
      collectionId: newCollectionId,
      updatedAt: updatedAt,
    );
  }

  /// Create a copy of this document with updated metadata
  Document withMetadata(Map<String, dynamic> newMetadata) {
    return Document(
      id: id,
      title: title,
      content: content,
      embedding: embedding,
      metadata: newMetadata,
      collectionId: collectionId,
      updatedAt: DateTime.now(),
    );
  }
}

/// Represents a collection of documents
class DocumentCollection {
  /// Collection ID
  final String id;

  /// Collection name
  final String name;

  /// Collection description
  final String? description;

  /// Metadata
  final Map<String, dynamic> metadata;

  /// Create a collection
  DocumentCollection({
    String? id,
    required this.name,
    this.description,
    this.metadata = const {},
  }) : id = id ?? 'col_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';

  /// Create a collection from JSON
  factory DocumentCollection.fromJson(Map<String, dynamic> json) {
    return DocumentCollection(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : {},
    );
  }

  /// Convert collection to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'metadata': metadata,
    };
  }
}

/// Store for documents with vector search capabilities
class DocumentStore {
  /// Storage manager for persistence
  final StorageManager storageManager;

  /// In-memory document store
  final Map<String, Document> _documents = {};

  /// Collections by ID
  final Map<String, DocumentCollection> _collections = {};

  /// Logger instance
  final Logger _logger = Logger('mcp_llm.document_store');

  /// Create a document store
  DocumentStore(this.storageManager);

  /// Initialize the store from storage
  Future<void> initialize() async {
    _logger.debug('Initializing document store');

    // Load collections
    final collectionKeys = await storageManager.listKeys('collection_');
    for (final key in collectionKeys) {
      final json = await storageManager.loadObject(key);
      if (json != null) {
        final collection = DocumentCollection.fromJson(json);
        _collections[collection.id] = collection;
      }
    }

    // Load documents
    final documentKeys = await storageManager.listKeys('document_');
    for (final key in documentKeys) {
      final json = await storageManager.loadObject(key);
      if (json != null) {
        final document = Document.fromJson(json);
        _documents[document.id] = document;
      }
    }

    _logger.debug('Document store initialized with ${_documents.length} documents and ${_collections.length} collections');
  }

  /// Add a document to the store
  Future<String> addDocument(Document document) async {
    _documents[document.id] = document;

    // Save to storage
    await storageManager.saveObject('document_${document.id}', document.toJson());

    _logger.debug('Added document to store: ${document.id}');
    return document.id;
  }

  /// Get a document by ID
  Document? getDocument(String id) {
    return _documents[id];
  }

  /// Update a document
  Future<void> updateDocument(Document document) async {
    if (!_documents.containsKey(document.id)) {
      throw ArgumentError('Document not found: ${document.id}');
    }

    _documents[document.id] = document;

    // Save to storage
    await storageManager.saveObject('document_${document.id}', document.toJson());

    _logger.debug('Updated document: ${document.id}');
  }

  /// Delete a document
  Future<bool> deleteDocument(String id) async {
    final removed = _documents.remove(id) != null;

    if (removed) {
      // Delete from storage
      await storageManager.delete('document_$id');
      _logger.debug('Deleted document: $id');
    }

    return removed;
  }

  /// Create a collection
  Future<String> createCollection(DocumentCollection collection) async {
    _collections[collection.id] = collection;

    // Save to storage
    await storageManager.saveObject('collection_${collection.id}', collection.toJson());

    _logger.debug('Created collection: ${collection.id}');
    return collection.id;
  }

  /// Get a collection by ID
  DocumentCollection? getCollection(String id) {
    return _collections[id];
  }

  /// Delete a collection (doesn't delete documents)
  Future<bool> deleteCollection(String id) async {
    final removed = _collections.remove(id) != null;

    if (removed) {
      // Delete from storage
      await storageManager.delete('collection_$id');
      _logger.debug('Deleted collection: $id');
    }

    return removed;
  }

  /// Find documents similar to a query embedding
  Future<List<Document>> findSimilar(
      List<double> queryEmbedding, {
        int limit = 5,
        double? minimumScore,
      }) async {
    _logger.debug('Finding similar documents (limit=$limit)');

    // Create embedding object for convenient similarity calculation
    final queryEmb = Embedding(queryEmbedding);

    // Calculate similarities for all documents with embeddings
    final scoredDocs = <ScoredDoc>[];

    for (final doc in _documents.values) {
      if (doc.embedding != null && doc.embedding!.isNotEmpty) {
        final docEmb = Embedding(doc.embedding!);
        final similarity = queryEmb.cosineSimilarity(docEmb);

        // Filter by minimum score if specified
        if (minimumScore == null || similarity >= minimumScore) {
          scoredDocs.add(ScoredDoc(doc, similarity));
        }
      }
    }

    // Sort by similarity (highest first)
    scoredDocs.sort((a, b) => b.score.compareTo(a.score));

    // Take top results
    final results = scoredDocs.take(limit).map((scored) => scored.document).toList();

    _logger.debug('Found ${results.length} similar documents');
    return results;
  }

  /// Find documents similar to a query embedding within a specific collection
  Future<List<Document>> findSimilarInCollection(
      String collectionId,
      List<double> queryEmbedding, {
        int limit = 5,
        double? minimumScore,
      }) async {
    _logger.debug('Finding similar documents in collection $collectionId (limit=$limit)');

    // Create embedding object for convenient similarity calculation
    final queryEmb = Embedding(queryEmbedding);

    // Calculate similarities for documents in the collection with embeddings
    final scoredDocs = <ScoredDoc>[];

    for (final doc in _documents.values) {
      if (doc.collectionId == collectionId &&
          doc.embedding != null &&
          doc.embedding!.isNotEmpty) {
        final docEmb = Embedding(doc.embedding!);
        final similarity = queryEmb.cosineSimilarity(docEmb);

        // Filter by minimum score if specified
        if (minimumScore == null || similarity >= minimumScore) {
          scoredDocs.add(ScoredDoc(doc, similarity));
        }
      }
    }

    // Sort by similarity (highest first)
    scoredDocs.sort((a, b) => b.score.compareTo(a.score));

    // Take top results
    final results = scoredDocs.take(limit).map((scored) => scored.document).toList();

    _logger.debug('Found ${results.length} similar documents in collection $collectionId');
    return results;
  }

  /// Get all documents in a collection
  List<Document> getDocumentsInCollection(String collectionId) {
    return _documents.values
        .where((doc) => doc.collectionId == collectionId)
        .toList();
  }

  /// Delete all documents in a collection
  Future<int> deleteDocumentsInCollection(String collectionId) async {
    final docsToDelete = getDocumentsInCollection(collectionId);

    for (final doc in docsToDelete) {
      await deleteDocument(doc.id);
    }

    _logger.debug('Deleted ${docsToDelete.length} documents from collection $collectionId');
    return docsToDelete.length;
  }

  /// Search documents by text content
  List<Document> searchByContent(String query, {int limit = 5}) {
    final queryLower = query.toLowerCase();
    final matches = <ScoredDoc>[];

    for (final doc in _documents.values) {
      final titleLower = doc.title.toLowerCase();
      final contentLower = doc.content.toLowerCase();

      // Calculate a simple relevance score
      int score = 0;

      // Exact match in title
      if (titleLower == queryLower) {
        score += 100;
      }
      // Title contains query
      else if (titleLower.contains(queryLower)) {
        score += 50;
      }

      // Content contains query
      if (contentLower.contains(queryLower)) {
        score += 25;

        // Bonus points for multiple occurrences
        final occurences =
            RegExp(queryLower, caseSensitive: false)
                .allMatches(contentLower)
                .length;
        score += occurences * 5;
      }

      if (score > 0) {
        matches.add(ScoredDoc(doc, score.toDouble()));
      }
    }

    // Sort by score (highest first)
    matches.sort((a, b) => b.score.compareTo(a.score));

    // Return top matches
    return matches.take(limit).map((scored) => scored.document).toList();
  }

  /// Get document count
  int get documentCount => _documents.length;

  /// Get collection count
  int get collectionCount => _collections.length;
}

/// Helper class for document scoring
class ScoredDoc {
  final Document document;
  final double score;

  ScoredDoc(this.document, this.score);
}