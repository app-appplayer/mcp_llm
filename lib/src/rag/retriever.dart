import 'dart:math';
import '../../mcp_llm.dart';
import '../core/models.dart';

/// Manages retrieval of relevant documents for RAG
class RetrievalManager {
  final DocumentStore documentStore;
  final LlmInterface llmProvider;
  final Logger _logger = Logger.getLogger('mcp_llm.retriever');

  RetrievalManager({
    required this.documentStore,
    required this.llmProvider,
  });

  /// Add a document to the store with embeddings
  Future<String> addDocument(Document document) async {
    _logger.debug('Adding document to store: ${document.id}');

    // If the document doesn't have an embedding, generate one
    if (document.embedding == null || document.embedding!.isEmpty) {
      _logger.debug('Generating embedding for document: ${document.id}');
      final embedding = await llmProvider.getEmbeddings(document.content);
      final docWithEmbedding = document.withEmbedding(embedding);
      return await documentStore.addDocument(docWithEmbedding);
    }

    // Document already has embedding
    return await documentStore.addDocument(document);
  }

  /// Add multiple documents in batch
  Future<List<String>> addDocuments(List<Document> documents) async {
    _logger.debug('Adding ${documents.length} documents to store');

    final results = <String>[];
    for (final doc in documents) {
      final id = await addDocument(doc);
      results.add(id);
    }

    return results;
  }

  /// Retrieve relevant documents for a query
  Future<List<Document>> retrieveRelevant(String query, {
    int topK = 5,
    double? minimumScore,
  }) async {
    _logger.debug('Retrieving documents for query: $query (topK=$topK)');

    try {
      // Get embedding for the query
      final queryEmbedding = await llmProvider.getEmbeddings(query);

      // Retrieve similar documents
      final results = await documentStore.findSimilar(
        queryEmbedding,
        limit: topK,
        minimumScore: minimumScore,
      );

      _logger.debug('Retrieved ${results.length} relevant documents');
      return results;
    } catch (e) {
      _logger.error('Error retrieving documents: $e');
      throw Exception('Failed to retrieve documents: $e');
    }
  }

  /// Retrieve and generate a response in one call
  Future<String> retrieveAndGenerate(String query, {
    int topK = 5,
    double? minimumScore,
    Map<String, dynamic> generationParams = const {},
  }) async {
    _logger.debug('Performing RAG for query: $query');

    // Retrieve relevant documents
    final docs = await retrieveRelevant(query, topK: topK, minimumScore: minimumScore);

    if (docs.isEmpty) {
      _logger.warning('No relevant documents found for query: $query');

      // Fall back to just answering without context
      final fallbackRequest = LlmRequest(
        prompt: 'Answer the following question without additional context: $query',
        parameters: Map<String, dynamic>.from(generationParams),
      );

      final fallbackResponse = await llmProvider.complete(fallbackRequest);
      return fallbackResponse.text;
    }

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

  /// Search within a specific collection of documents
  Future<List<Document>> searchCollection(String collectionId, String query, {
    int topK = 5,
    double? minimumScore,
  }) async {
    _logger.debug('Searching collection $collectionId for query: $query');

    // Get embedding for the query
    final queryEmbedding = await llmProvider.getEmbeddings(query);

    // Retrieve documents from the specific collection
    return await documentStore.findSimilarInCollection(
      collectionId,
      queryEmbedding,
      limit: topK,
      minimumScore: minimumScore,
    );
  }

  /// Retrieve and rerank documents using two-stage retrieval
  Future<List<Document>> retrieveAndRerank(String query, {
    int retrievalTopK = 10,
    int rerankTopK = 5,
  }) async {
    // First stage: Retrieve using vector similarity
    final candidates = await retrieveRelevant(query, topK: retrievalTopK);

    if (candidates.isEmpty) {
      return [];
    }

    // Second stage: Rerank based on relevance scores
    final rerankedDocs = await _rerank(query, candidates);

    // Return the top documents after reranking
    return rerankedDocs.take(rerankTopK).toList();
  }

  /// Rerank documents based on relevance to query
  Future<List<Document>> _rerank(String query, List<Document> documents) async {
    // Create a prompt for the LLM to score document relevance
    final scoringPrompts = <LlmRequest>[];

    for (final doc in documents) {
      final prompt = 'Rate the relevance of the following document to the query on a scale of 0.0 to 1.0.\n\n'
          'Query: $query\n\n'
          'Document: ${doc.content}\n\n'
          'Relevance score (0.0 to 1.0):';

      scoringPrompts.add(LlmRequest(
        prompt: prompt,
        parameters: {'temperature': 0.1},
      ));
    }

    // Process scoring in parallel
    final scoreFutures = scoringPrompts.map((req) => llmProvider.complete(req));
    final scoreResponses = await Future.wait(scoreFutures);

    // Parse scores and pair with documents
    final scoredDocs = <ScoredDocument>[];

    for (var i = 0; i < documents.length; i++) {
      double score;
      try {
        // Extract numeric score from response
        final scoreText = scoreResponses[i].text.trim();
        // Convert string like "0.75" to a double
        score = double.parse(RegExp(r'([0-9]*[.])?[0-9]+').firstMatch(scoreText)?.group(0) ?? '0.0');
        // Clamp to valid range
        score = max(0.0, min(1.0, score));
      } catch (e) {
        // Default score if parsing fails
        score = 0.5;
      }

      scoredDocs.add(ScoredDocument(documents[i], score));
    }

    // Sort by score in descending order
    scoredDocs.sort((a, b) => b.score.compareTo(a.score));

    // Return sorted documents
    return scoredDocs.map((scored) => scored.document).toList();
  }
}

/// Helper class for document scoring
class ScoredDocument {
  final Document document;
  final double score;

  ScoredDocument(this.document, this.score);
}