import 'dart:math';

import '../../mcp_llm.dart';

class BatchEmbeddingProcessor {
  final LlmInterface llmProvider;
  // Modified from final to mutable batchSize
  int batchSize;

  BatchEmbeddingProcessor({
    required this.llmProvider,
    this.batchSize = 10, // Default batch size
  });

  // Process document batch (default method)
  Future<List<Document>> processDocumentBatch(List<Document> documents) async {
    final List<Document> processedDocuments = [];

    // Process in batches
    for (int i = 0; i < documents.length; i += batchSize) {
      final end = min(i + batchSize, documents.length);
      final batch = documents.sublist(i, end);

      // Filter documents that need embeddings
      final needsEmbedding = batch
          .where((doc) => doc.embedding == null || doc.embedding!.isEmpty)
          .toList();

      // Generate embeddings and update documents
      if (needsEmbedding.isNotEmpty) {
        final updatedBatch = await _generateEmbeddingsForBatch(needsEmbedding);
        processedDocuments.addAll(updatedBatch);

        // Add documents that already have embeddings
        processedDocuments.addAll(batch.where(
            (doc) => doc.embedding != null && doc.embedding!.isNotEmpty));
      } else {
        processedDocuments.addAll(batch);
      }
    }

    return processedDocuments;
  }

  // Generate embeddings for batch
  Future<List<Document>> _generateEmbeddingsForBatch(
      List<Document> batch) async {
    // Prepare embedding requests for each document content
    final futures = <Future<List<double>>>[];

    for (final doc in batch) {
      futures.add(llmProvider.getEmbeddings(doc.content));
    }

    // Collect all embedding results
    final embeddings = await Future.wait(futures);

    // Apply embeddings to documents
    return List.generate(batch.length, (index) {
      return batch[index].withEmbedding(embeddings[index]);
    });
  }

  // Process entire document collection
  Future<void> processCollection(
    DocumentStore documentStore,
    String collectionId, {
    int? customBatchSize,
  }) async {
    // Get all documents in collection
    final documents = documentStore.getDocumentsInCollection(collectionId);

    // Generate embeddings - Fixed error: process with custom batch size
    final processedDocuments = await processDocumentBatchWithCustomSize(
      documents,
      customBatchSize ?? batchSize,
    );

    // Update document store
    for (final doc in processedDocuments) {
      await documentStore.updateDocument(doc);
    }
  }

  // Renamed: Method to process with custom batch size
  Future<List<Document>> processDocumentBatchWithCustomSize(
    List<Document> documents,
    int customBatchSize,
  ) async {
    // Save original batch size
    final savedBatchSize = batchSize;

    // Temporarily change batch size
    batchSize = customBatchSize;

    try {
      // Use default method
      return await processDocumentBatch(documents);
    } finally {
      // Restore original batch size
      batchSize = savedBatchSize;
    }
  }
}
