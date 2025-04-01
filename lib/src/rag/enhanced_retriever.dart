import 'dart:math' as math;

import '../../mcp_llm.dart';

class EnhancedRetriever {
  final DocumentStore documentStore;
  final LlmInterface llmProvider;

  EnhancedRetriever({
    required this.documentStore,
    required this.llmProvider,
  });

  // Implementation of hybrid search
  Future<List<Document>> hybridSearch(
    String query, {
    int semanticResults = 5,
    int keywordResults = 5,
    int finalResults = 5,
    double boostFactor = 0.25,
    double? minimumScore,
  }) async {
    // Semantic search (embedding-based)
    final queryEmbedding = await llmProvider.getEmbeddings(query);
    final semanticDocs = await documentStore.findSimilar(
      queryEmbedding,
      limit: semanticResults,
      minimumScore: minimumScore,
    );

    // Keyword search (text matching-based)
    final keywordDocs = documentStore.searchByContent(
      query,
      limit: keywordResults,
    );

    // Combine result sets and remove duplicates
    final Map<String, ScoredDocument> combinedResults = {};

    // Process semantic search results
    for (final doc in semanticDocs) {
      final similarity = _calculateSimilarity(doc, queryEmbedding);
      combinedResults[doc.id] = ScoredDocument(doc, similarity);
    }

    // Process keyword search results
    for (final doc in keywordDocs) {
      final keywordScore = _calculateKeywordScore(doc, query);

      if (combinedResults.containsKey(doc.id)) {
        // Boost score if already included in semantic search
        final existing = combinedResults[doc.id]!;
        final boostedScore = existing.score + (keywordScore * boostFactor);
        combinedResults[doc.id] = ScoredDocument(doc, boostedScore);
      } else {
        // Add new result
        combinedResults[doc.id] =
            ScoredDocument(doc, keywordScore * (1 - boostFactor));
      }
    }

    // Sort by score and return top results
    final sortedResults = combinedResults.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return sortedResults
        .take(finalResults)
        .map((scored) => scored.document)
        .toList();
  }

  // Calculate similarity between document and query embedding
  double _calculateSimilarity(Document doc, List<double> queryEmbedding) {
    if (doc.embedding == null || doc.embedding!.isEmpty) {
      return 0.0;
    }

    final docEmb = Embedding(doc.embedding!);
    final queryEmb = Embedding(queryEmbedding);

    return docEmb.cosineSimilarity(queryEmb);
  }

  // Calculate keyword score for document
  double _calculateKeywordScore(Document doc, String query) {
    final queryTerms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.length > 2) // Filter short words
        .toList();

    // Prepare document title and content
    final titleLower = doc.title.toLowerCase();
    final contentLower = doc.content.toLowerCase();

    double score = 0.0;

    // Title match score
    for (final term in queryTerms) {
      if (titleLower.contains(term)) {
        score += 2.0; // Higher weight for title matches
      }
    }

    // Content match score
    for (final term in queryTerms) {
      final matches =
          RegExp(term, caseSensitive: false).allMatches(contentLower).length;
      score += matches * 0.5; // Medium weight for content matches
    }

    // Exact phrase match bonus
    if (contentLower.contains(query.toLowerCase())) {
      score += 5.0; // High bonus for exact phrase match
    }

    return score;
  }

  // Implementation of context-aware search
  Future<List<Document>> contextAwareSearch(
    String query,
    List<String> previousQueries, {
    int results = 5,
  }) async {
    // Create expanded query considering previous queries
    final expandedQuery = await _createExpandedQuery(query, previousQueries);

    // Perform hybrid search with expanded query
    return hybridSearch(
      expandedQuery,
      finalResults: results,
    );
  }

  // Create expanded query considering previous queries
  Future<String> _createExpandedQuery(
      String query, List<String> previousQueries) async {
    if (previousQueries.isEmpty) {
      return query;
    }

    // Consider only the 3 most recent queries
    final recentQueries = previousQueries.length > 3
        ? previousQueries.sublist(previousQueries.length - 3)
        : previousQueries;

    // Use LLM for context-aware query expansion
    final context = recentQueries.join('\n');
    final prompt = '''
Previous questions:
$context

Current question:
$query

Rewrite the current question to include important context from previous questions.
Keep it concise but include all relevant search terms. Return only the rewritten question.
''';

    try {
      final request =
          LlmRequest(prompt: prompt, parameters: {'temperature': 0.3});
      final response = await llmProvider.complete(request);

      // Check if response is sufficiently relevant
      if (response.text.length > query.length * 3 ||
          response.text.length < query.length / 2) {
        return query; // Use original query if response is too long or too short
      }

      return response.text;
    } catch (e) {
      // Use original query in case of error
      return query;
    }
  }

  // Implementation of document reranking
  Future<List<Document>> rerankResults(
    String query,
    List<Document> candidates, {
    int topK = 5,
    bool useLightweightRanker = true,
  }) async {
    if (candidates.isEmpty || candidates.length <= topK) {
      return candidates;
    }

    if (useLightweightRanker) {
      return _lightweightRerank(query, candidates, topK);
    } else {
      return _llmBasedRerank(query, candidates, topK);
    }
  }

  // Implementation of lightweight reranking (algorithm similar to BM25)
  Future<List<Document>> _lightweightRerank(
      String query, List<Document> documents, int topK) async {
    final queryTerms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.length > 2)
        .toList();

    final scoredDocs = <ScoredDocument>[];

    // BM25 parameters
    const k1 = 1.5;
    const b = 0.75;
    final avgDocLength =
        documents.fold<double>(0, (sum, doc) => sum + doc.content.length) /
            documents.length;

    for (final doc in documents) {
      double score = 0.0;
      final docLength = doc.content.length;

      for (final term in queryTerms) {
        // Calculate term frequency
        final termFreq =
            RegExp(term, caseSensitive: false).allMatches(doc.content).length;
        if (termFreq == 0) continue;

        // Calculate inverse document frequency
        int docsWithTerm = 0;
        for (final checkDoc in documents) {
          if (checkDoc.content.toLowerCase().contains(term)) {
            docsWithTerm++;
          }
        }

        final idf =
            docsWithTerm > 0 ? math.log(documents.length / docsWithTerm) : 0;

        // Calculate BM25 score
        final termScore = idf *
            ((termFreq * (k1 + 1)) /
                (termFreq + k1 * (1 - b + b * (docLength / avgDocLength))));

        score += termScore;
      }

      // Add title weight
      for (final term in queryTerms) {
        if (doc.title.toLowerCase().contains(term)) {
          score += 2.0; // Title match bonus
        }
      }

      scoredDocs.add(ScoredDocument(doc, score));
    }

    // Sort and return top results
    scoredDocs.sort((a, b) => b.score.compareTo(a.score));
    return scoredDocs.take(topK).map((scored) => scored.document).toList();
  }

  // Implementation of LLM-based reranking
  Future<List<Document>> _llmBasedRerank(
      String query, List<Document> documents, int topK) async {
    // Generate relevance scores for each document
    final scoringPrompts = <LlmRequest>[];

    for (final doc in documents) {
      final prompt = '''
Rate the relevance of the following document to the query on a scale of 0.0 to 1.0.

Query: $query

Document title: ${doc.title}
Document content: ${doc.content.length > 500 ? doc.content.substring(0, 500) + "..." : doc.content}

Relevance score (0.0 to 1.0):
''';

      scoringPrompts.add(LlmRequest(
        prompt: prompt,
        parameters: {'temperature': 0.1},
      ));
    }

    // Use parallel processing for efficiency
    final futures = <Future<double>>[];
    for (final req in scoringPrompts) {
      futures.add(_getScoreFromLlm(req));
    }

    // Collect all results
    final scores = await Future.wait(futures);

    // Combine documents and scores
    final scoredDocs = <ScoredDocument>[];
    for (var i = 0; i < documents.length; i++) {
      scoredDocs.add(ScoredDocument(documents[i], scores[i]));
    }

    // Sort and return top results
    scoredDocs.sort((a, b) => b.score.compareTo(a.score));
    return scoredDocs.take(topK).map((scored) => scored.document).toList();
  }

  // Extract score from LLM response
  Future<double> _getScoreFromLlm(LlmRequest request) async {
    try {
      final response = await llmProvider.complete(request);

      // Try to extract number
      final scoreRegex = RegExp(r'([0-9]*[.])?[0-9]+');
      final match = scoreRegex.firstMatch(response.text);

      if (match != null) {
        final scoreStr = match.group(0)!;
        final score = double.tryParse(scoreStr) ?? 0.5;

        // Limit score range
        return math.max(0.0, math.min(1.0, score));
      }
    } catch (e) {
      // Return default value in case of error
    }

    return 0.5; // Default score
  }
}
