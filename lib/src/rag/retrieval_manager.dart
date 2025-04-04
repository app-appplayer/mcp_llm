import 'dart:convert';

import '../core/llm_interface.dart';
import '../core/models.dart';
import '../utils/logger.dart';
import 'document_store.dart';
import 'embeddings.dart';
import 'vector_store.dart';

/// ㄱRetrieval manager with external vector store support
class RetrievalManager {
  final LlmInterface llmProvider;
  final Logger _logger = Logger.getLogger('mcp_llm.retrieval_manager');

  // Internal document store for compatibility
  final DocumentStore? _documentStore;

  // External vector store
  final VectorStore? _vectorStore;

  // Default namespace/collection for vector store operations
  final String? _defaultNamespace;

  /// Create a retrieval manager with a document store (legacy mode)
  RetrievalManager.withDocumentStore({
    required LlmInterface llmProvider,
    required DocumentStore documentStore,
  }) : llmProvider = llmProvider,
        _documentStore = documentStore,
        _vectorStore = null,
        _defaultNamespace = null;

  /// Create a retrieval manager with an external vector store
  RetrievalManager.withVectorStore({
    required LlmInterface llmProvider,
    required VectorStore vectorStore,
    String? defaultNamespace,
  }) : llmProvider = llmProvider,
        _documentStore = null,
        _vectorStore = vectorStore,
        _defaultNamespace = defaultNamespace;

  /// Check if the manager is using an external vector store
  bool get usesVectorStore => _vectorStore != null;

  /// Add a document to the store with embeddings
  Future<String> addDocument(Document document) async {
    _logger.debug('Adding document to store: ${document.id}');

    // If the document doesn't have an embedding, generate one
    Document docWithEmbedding = document;
    if (document.embedding == null || document.embedding!.isEmpty) {
      _logger.debug('Generating embedding for document: ${document.id}');
      final embedding = await llmProvider.getEmbeddings(document.content);
      docWithEmbedding = document.withEmbedding(embedding);
    }

    if (usesVectorStore) {
      await _vectorStore!.upsertDocument(
        docWithEmbedding,
        namespace: _defaultNamespace,
      );
      return docWithEmbedding.id;
    } else {
      return await _documentStore!.addDocument(docWithEmbedding);
    }
  }

  /// Add multiple documents in batch
  Future<List<String>> addDocuments(List<Document> documents) async {
    _logger.debug('Adding ${documents.length} documents to store');

    final results = <String>[];
    final docsWithEmbeddings = <Document>[];

    // Generate embeddings for documents that don't have them
    for (final doc in documents) {
      if (doc.embedding == null || doc.embedding!.isEmpty) {
        final embedding = await llmProvider.getEmbeddings(doc.content);
        docsWithEmbeddings.add(doc.withEmbedding(embedding));
      } else {
        docsWithEmbeddings.add(doc);
      }
    }

    if (usesVectorStore) {
      // Batch upsert to vector store
      await _vectorStore!.upsertDocumentBatch(
        docsWithEmbeddings,
        namespace: _defaultNamespace,
      );

      results.addAll(docsWithEmbeddings.map((doc) => doc.id));
    } else {
      // Add documents one by one to document store
      for (final doc in docsWithEmbeddings) {
        final id = await _documentStore!.addDocument(doc);
        results.add(id);
      }
    }

    return results;
  }

  /// Retrieve relevant documents for a query
  Future<List<Document>> retrieveRelevant(String query, {
    int topK = 5,
    double? minimumScore,
    String? namespace,
    Map<String, dynamic> filters = const {},
  }) async {
    _logger.debug('Retrieving documents for query: $query (topK=$topK)');

    try {
      // Get embedding for the query
      final queryEmbedding = await llmProvider.getEmbeddings(query);
      final embedding = Embedding(queryEmbedding);

      if (usesVectorStore) {
        final results = await _vectorStore!.findSimilarDocuments(
          embedding,
          limit: topK,
          scoreThreshold: minimumScore,
          namespace: namespace ?? _defaultNamespace,
          filters: filters,
        );

        _logger.debug('Retrieved ${results.length} relevant documents from vector store');
        return results.map((scoredDoc) => scoredDoc.document).toList();
      } else {
        // Legacy document store approach
        final results = await _documentStore!.findSimilar(
          queryEmbedding,
          limit: topK,
          minimumScore: minimumScore,
        );

        _logger.debug('Retrieved ${results.length} relevant documents from document store');
        return results;
      }
    } catch (e) {
      _logger.error('Error retrieving documents: $e');
      throw Exception('Failed to retrieve documents: $e');
    }
  }

  /// Retrieve and generate a response in one call
  Future<String> retrieveAndGenerate(String query, {
    int topK = 5,
    double? minimumScore,
    String? namespace,
    Map<String, dynamic> filters = const {},
    Map<String, dynamic> generationParams = const {},
  }) async {
    _logger.debug('Performing RAG for query: $query');

    // Retrieve relevant documents
    final docs = await retrieveRelevant(
      query,
      topK: topK,
      minimumScore: minimumScore,
      namespace: namespace,
      filters: filters,
    );

    if (docs.isEmpty) {
      return await _generateResponseWithoutContext(query, generationParams);
    }

    // Generate response with documents
    return await _generateResponseWithContext(query, docs, generationParams);
  }

  /// Generate a response without document context
  Future<String> _generateResponseWithoutContext(
      String query, Map<String, dynamic> generationParams) async {
    _logger.warning('No relevant documents found for query: $query');

    // Fall back to just answering without context
    final fallbackRequest = LlmRequest(
      prompt: 'Answer the following question without additional context: $query',
      parameters: Map<String, dynamic>.from(generationParams),
    );

    final fallbackResponse = await llmProvider.complete(fallbackRequest);
    return fallbackResponse.text;
  }

  /// Generate a response with document context
  Future<String> _generateResponseWithContext(
      String query, List<Document> docs, Map<String, dynamic> generationParams) async {
    // Build context from documents
    final context = _formatDocumentsAsContext(docs);

    // Create RAG prompt
    final ragPrompt = 'You are provided with some context information to help answer a question.\n\n'
        'Context information:\n$context\n\n'
        'Based on the information above, answer the following question:\n$query\n\n'
        'If the information needed to answer the question is not present in the '
        'context provided, just say "I don\'t have enough information to answer this question."';

    // Generate response with the LLM
    final request = LlmRequest(
      prompt: ragPrompt,
      parameters: Map<String, dynamic>.from(generationParams),
    );

    final response = await llmProvider.complete(request);
    _logger.debug('Generated RAG response for query: $query');

    return response.text;
  }

  /// Format retrieved documents as context for the LLM
  String _formatDocumentsAsContext(List<Document> documents) {
    final buffer = StringBuffer();

    for (var i = 0; i < documents.length; i++) {
      final doc = documents[i];
      buffer.writeln('[Document ${i+1}] ${doc.title}:');
      buffer.writeln(doc.content);
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Search for documents by metadata
  Future<List<Document>> searchByMetadata(
      Map<String, dynamic> metadata, {
        int limit = 5,
        String? namespace,
      }) async {
    _logger.debug('Searching for documents by metadata');

    if (usesVectorStore) {
      // With vector store, use filters
      // We need a placeholder query, so we'll use a generic embedding
      final genericEmbedding = Embedding(List.generate(1536, (_) => 0.0));

      final results = await _vectorStore!.findSimilarDocuments(
        genericEmbedding,
        limit: limit,
        namespace: namespace ?? _defaultNamespace,
        filters: metadata,
        // Use a very low threshold to ensure we get results
        scoreThreshold: 0.0,
      );

      return results.map((scoredDoc) => scoredDoc.document).toList();
    } else {
      // With document store, we have to do manual filtering
      // Get all documents from the collection if specified
      List<Document> candidates;

      if (metadata.containsKey('collectionId')) {
        candidates = _documentStore!.getDocumentsInCollection(
          metadata['collectionId'] as String,
        );

        // Remove collectionId from filter criteria since we already used it
        metadata = Map<String, dynamic>.from(metadata)
          ..remove('collectionId');
      } else {
        // Without a collection, we need to fetch all documents
        // This is inefficient but necessary for the simple document store
        // Since we can't get all documents easily, we'll just use an empty list
        candidates = <Document>[];
        // In a real implementation, you would need a way to get all documents
        _logger.warning('Searching all documents without a collection ID is not supported in the basic implementation');
      }

      // Filter by metadata
      final results = candidates.where((doc) {
        return _matchesMetadata(doc.metadata, metadata);
      }).take(limit).toList();

      return results;
    }
  }

  /// Check if document metadata matches filter criteria
  bool _matchesMetadata(Map<String, dynamic> docMetadata, Map<String, dynamic> filter) {
    for (final entry in filter.entries) {
      final key = entry.key;
      final value = entry.value;

      if (!docMetadata.containsKey(key)) {
        return false;
      }

      final docValue = docMetadata[key];

      if (docValue != value) {
        // Handle special cases like ranges, etc. if needed
        return false;
      }
    }

    return true;
  }

  Future<List<Document>> rerankResults(
      String query,
      List<Document> candidates, {
        int topK = 5,
        bool useLightweightRanker = false,
      }) async {
    _logger.debug('Reranking ${candidates.length} documents for query: $query');

    final contextList = candidates.asMap().entries.map((entry) {
      final idx = entry.key + 1;
      final doc = entry.value;
      return '[$idx] ${doc.title}\n${doc.content}';
    }).join('\n\n');

    final prompt = '''
You are a ranking model. Rank the following documents based on how relevant they are to the query.

Query: "$query"

Documents:
$contextList

Return a JSON array of the top $topK document numbers (e.g., [1, 3, 2])
''';

    final request = LlmRequest(
      prompt: prompt,
      parameters: {
        'temperature': useLightweightRanker ? 0.0 : 0.3,
      },
    );

    final response = await llmProvider.complete(request);
    final text = response.text.trim();

    try {
      final List<dynamic> indices = jsonDecode(text);
      final ranked = <Document>[];

      for (final index in indices) {
        if (index is int && index > 0 && index <= candidates.length) {
          ranked.add(candidates[index - 1]);
        }
      }

      return ranked;
    } catch (e) {
      _logger.error('Failed to parse rerank response: $e\nResponse text: $text');
      return candidates.take(topK).toList();
    }
  }

  /// Delete a document
  Future<bool> deleteDocument(String id, {String? namespace}) async {
    if (usesVectorStore) {
      return await _vectorStore!.deleteEmbedding(id, namespace: namespace ?? _defaultNamespace);
    } else {
      return await _documentStore!.deleteDocument(id);
    }
  }

  /// Delete multiple documents
  Future<int> deleteDocuments(List<String> ids, {String? namespace}) async {
    if (usesVectorStore) {
      return await _vectorStore!.deleteEmbeddingBatch(ids, namespace: namespace ?? _defaultNamespace);
    } else {
      int count = 0;
      for (final id in ids) {
        if (await _documentStore!.deleteDocument(id)) {
          count++;
        }
      }
      return count;
    }
  }

  /// Hybrid search combining keyword and vector search
  Future<List<Document>> hybridSearch(
      String query, {
        int semanticResults = 5,
        int keywordResults = 5,
        int finalResults = 5,
        double boostFactor = 0.25,
        double? minimumScore,
        String? namespace,
      }) async {
    // Get embedding for the query
    final queryEmbedding = await llmProvider.getEmbeddings(query);
    final embedding = Embedding(queryEmbedding);

    // Lists to store results
    List<ScoredDocument> semanticDocs = [];
    List<Document> keywordDocs = [];

    if (usesVectorStore) {
      // With vector store
      semanticDocs = await _vectorStore!.findSimilarDocuments(
        embedding,
        limit: semanticResults,
        scoreThreshold: minimumScore,
        namespace: namespace ?? _defaultNamespace,
      );

      // For keyword search, we need to implement it
      // This depends on the vector store's capabilities
      // For now, we'll skip this step with vector stores
    } else {
      // With document store
      final semanticDocsResult = await _documentStore!.findSimilar(
        queryEmbedding,
        limit: semanticResults,
        minimumScore: minimumScore,
      );

      semanticDocs = semanticDocsResult.map((doc) {
        // Create a similarity score based on embedding distance
        // This is a simplification; real scoring would be more complex
        return ScoredDocument(doc, 0.8); // Placeholder score
      }).toList();

      keywordDocs = _documentStore.searchByContent(query, limit: keywordResults);
    }

    // Combine and deduplicate results
    final combinedResults = <String, ScoredDocument>{};

    // Add semantic search results
    for (final doc in semanticDocs) {
      combinedResults[doc.document.id] = doc;
    }

    // Add keyword search results with boosting
    for (final doc in keywordDocs) {
      final keywordScore = 0.7; // Placeholder score

      if (combinedResults.containsKey(doc.id)) {
        // Boost score if already included in semantic search
        final existing = combinedResults[doc.id]!;
        final boostedScore = existing.score + (keywordScore * boostFactor);
        combinedResults[doc.id] = ScoredDocument(doc, boostedScore);
      } else {
        combinedResults[doc.id] = ScoredDocument(doc, keywordScore * (1 - boostFactor));
      }
    }

    // Sort by score and return top results
    final sortedResults = combinedResults.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return sortedResults.take(finalResults).map((scored) => scored.document).toList();
  }

  Future<List<Document>> contextAwareSearch(
      String query,
      List<String> previousQueries, {
        int topK = 5,
        double? minimumScore,
      }) async {
    final expandedQuery = await _expandQueryWithContext(query, previousQueries);

    return await retrieveRelevant(
      expandedQuery,
      topK: topK,
      minimumScore: minimumScore,
    );
  }

  Future<String> _expandQueryWithContext(String query, List<String> previousQueries) async {
    final contextPrompt = 'Previous queries: ${previousQueries.join(", ")}\n'
        'Current query: $query\n'
        'Expand the current query by considering the context of previous queries:';

    final request = LlmRequest(
      prompt: contextPrompt,
      parameters: {'temperature': 0.3},
    );

    final response = await llmProvider.complete(request);
    return response.text.trim();
  }

  /// Close and clean up resources
  Future<void> close() async {
    if (usesVectorStore) {
      await _vectorStore!.close();
    }
  }
}