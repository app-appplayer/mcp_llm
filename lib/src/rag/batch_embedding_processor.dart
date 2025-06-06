import 'dart:math';
import '../../mcp_llm.dart';

/// Handles batch processing of documents for embedding generation
class BatchEmbeddingProcessor {
  final LlmInterface llmProvider;
  int batchSize;
  final Logger _logger = Logger('mcp_llm.batch_embedding_processor');

  BatchEmbeddingProcessor({
    required this.llmProvider,
    this.batchSize = 10, // Default batch size
  });

  /// Process document batch with improved error handling and efficiency
  Future<List<Document>> processDocumentBatch(List<Document> documents) async {
    if (documents.isEmpty) {
      return [];
    }

    final List<Document> processedDocuments = [];

    // Process in batches
    for (int i = 0; i < documents.length; i += batchSize) {
      final end = min(i + batchSize, documents.length);
      final batch = documents.sublist(i, end);

      try {
        // Process all documents in batch
        final updatedBatch = await _generateEmbeddingsForBatch(batch);
        processedDocuments.addAll(updatedBatch);
      } catch (e) {
        _logger.error('Error processing batch ${i ~/ batchSize}: $e');

        // Still add original documents to not lose them completely
        processedDocuments.addAll(batch);
      }
    }

    return processedDocuments;
  }

  /// Generate embeddings for batch with better error handling
  Future<List<Document>> _generateEmbeddingsForBatch(List<Document> batch) async {
    final results = <Document>[];
    final futures = <Future<MapEntry<int, List<double>>>>[];
    final indexMap = <int, int>{};

    for (int i = 0; i < batch.length; i++) {
      final doc = batch[i];
      if (doc.embedding != null && doc.embedding!.isNotEmpty) {
        results.add(doc);
      } else {
        indexMap[futures.length] = i;
        futures.add(_getEmbeddingWithIndex(doc.content, futures.length));
      }
    }

    final embeddings = await Future.wait(
      futures,
      eagerError: false,
    ).catchError((e) {
      _logger.error('Error in batch embedding generation: \$e');
      return <MapEntry<int, List<double>>>[];
    });

    for (final entry in embeddings) {
      final batchIndex = indexMap[entry.key];
      if (batchIndex != null) {
        final originalDoc = batch[batchIndex];
        results.add(originalDoc.withEmbedding(entry.value));
      }
    }

    return results;
  }

  /// Helper method to get embedding with index for error tracking
  Future<MapEntry<int, List<double>>> _getEmbeddingWithIndex(String content, int index) async {
    try {
      final embedding = await llmProvider.getEmbeddings(content);
      return MapEntry(index, embedding);
    } catch (e) {
      _logger.error('Failed to get embedding for document at index $index: $e');
      rethrow; // Let the caller handle this
    }
  }

  /// Process document collection with custom batch size
  Future<void> processCollection(
      DocumentStore documentStore,
      String collectionId, {
        int? customBatchSize,
        bool skipExisting = true,
      }) async {
    // Get all documents in collection
    final documents = documentStore.getDocumentsInCollection(collectionId);

    // Filter documents if skipping those with existing embeddings
    final documentsToProcess = skipExisting
        ? documents.where((doc) => doc.embedding == null || doc.embedding!.isEmpty).toList()
        : documents;

    _logger.info('Processing ${documentsToProcess.length} documents '
        '(out of ${documents.length} total) in collection: $collectionId');

    // Process with appropriate batch size
    final actualBatchSize = customBatchSize ?? batchSize;
    final processedDocuments = await processDocumentBatchWithCustomSize(
      documentsToProcess,
      actualBatchSize,
    );

    // Update document store only for successfully processed documents
    int updateCount = 0;
    for (final doc in processedDocuments) {
      if (doc.embedding != null && doc.embedding!.isNotEmpty) {
        await documentStore.updateDocument(doc);
        updateCount++;
      }
    }

    _logger.info('Updated $updateCount documents with embeddings in collection: $collectionId');
  }

  /// Process with custom batch size
  Future<List<Document>> processDocumentBatchWithCustomSize(
      List<Document> documents,
      int customBatchSize,
      ) async {
    // Save original batch size
    final savedBatchSize = batchSize;

    try {
      // Temporarily change batch size
      batchSize = customBatchSize;

      // Use standard method
      return await processDocumentBatch(documents);
    } finally {
      // Restore original batch size
      batchSize = savedBatchSize;
    }
  }
}