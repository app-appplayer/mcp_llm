import 'package:mockito/annotations.dart';
import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_llm/src/rag/batch_embedding_processor.dart';
import 'package:mockito/mockito.dart';

import 'rag_test.mocks.dart'; // Reuse mocks from rag_test

@GenerateMocks([
  DocumentStore,
  LlmInterface,
  LlmResponse,
])
void main() {
  group('EnhancedRetriever', () {
    late MockDocumentStore mockStore;
    late MockLlmInterface mockLlm;
    late RetrievalManager retriever;

    setUp(() {
      mockStore = MockDocumentStore();
      mockLlm = MockLlmInterface();
      retriever =  RetrievalManager.withDocumentStore(
        llmProvider: mockLlm,
        documentStore: mockStore,
      );
    });

    test('hybridSearch combines keyword and semantic search results', () async {
      // Setup semantic search
      when(mockLlm.getEmbeddings(any)).thenAnswer(
              (_) async => [0.1, 0.2, 0.3, 0.4]
      );

      // Create test documents
      final semanticDocs = [
        Document(
          id: 'sem1',
          title: 'Semantic Doc 1',
          content: 'Semantic content 1',
          embedding: [0.1, 0.2, 0.3, 0.4],
        ),
        Document(
          id: 'sem2',
          title: 'Semantic Doc 2',
          content: 'Semantic content 2',
          embedding: [0.2, 0.3, 0.4, 0.5],
        ),
      ];

      final keywordDocs = [
        Document(
          id: 'key1',
          title: 'Keyword Doc 1',
          content: 'Keyword content 1',
          embedding: [0.5, 0.6, 0.7, 0.8],
        ),
        Document(
          id: 'sem1', // Overlap with semantic results
          title: 'Semantic Doc 1',
          content: 'Semantic content 1',
          embedding: [0.1, 0.2, 0.3, 0.4],
        ),
      ];

      // Setup mock responses
      when(mockStore.findSimilar(
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenAnswer((_) async => semanticDocs);

      when(mockStore.searchByContent(
        any,
        limit: anyNamed('limit'),
      )).thenReturn(keywordDocs);

      // Call hybrid search
      final results = await retriever.hybridSearch(
        'test query',
        semanticResults: 2,
        keywordResults: 2,
        finalResults: 3,
      );

      // Verify correct calls were made
      verify(mockLlm.getEmbeddings('test query')).called(1);
      verify(mockStore.findSimilar(
        any,
        limit: 2,
        minimumScore: null,
      )).called(1);
      verify(mockStore.searchByContent(
        'test query',
        limit: 2,
      )).called(1);

// Results should include both semantic and keyword matches
      // with duplicates removed
      expect(results.length, equals(3));

      // Check that we have the expected document IDs
      final resultIds = results.map((doc) => doc.id).toList();
      expect(resultIds, containsAll(['sem1', 'sem2', 'key1']));

      // Document that appears in both sets should appear only once
      expect(resultIds.where((id) => id == 'sem1').length, equals(1));
    });

    test('contextAwareSearch uses previous queries for context', () async {
      // Setup mocks
      final mockResponse = MockLlmResponse();
      when(mockResponse.text).thenReturn('expanded query with context');

      when(mockLlm.complete(any)).thenAnswer((_) async => mockResponse);
      when(mockLlm.getEmbeddings(any)).thenAnswer((_) async => [0.1, 0.2, 0.3, 0.4]);

      // Adjust mock return value
      when(mockStore.findSimilar(
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenAnswer((_) async => [
        Document(id: 'doc1', title: 'Doc 1', content: 'Content 1'),
        Document(id: 'doc2', title: 'Doc 2', content: 'Content 2'),
        Document(id: 'doc3', title: 'Doc 3', content: 'Content 3'),
      ]);

      when(mockStore.searchByContent(any, limit: anyNamed('limit')))
          .thenReturn([Document(id: 'doc3', title: 'Doc 3', content: 'Content 3')]);

      // Previous queries for context
      final previousQueries = [
        'What are neural networks?',
        'How do transformers work?'
      ];

      // Current query
      final results = await retriever.contextAwareSearch(
          'What are their limitations?',
          previousQueries
      );

      // Check actual result size
      expect(results.length, equals(3));
    });

    test('rerankResults reorders documents by relevance', () async {
      // Create test documents with varying relevance
      final candidates = [
        Document(id: 'doc1', title: 'Doc 1', content: 'Very relevant content'),
        Document(id: 'doc2', title: 'Doc 2', content: 'Somewhat relevant'),
        Document(id: 'doc3', title: 'Doc 3', content: 'Not relevant at all'),
        Document(id: 'doc4', title: 'Doc 4', content: 'Highly relevant content'),
        Document(id: 'doc5', title: 'Doc 5', content: 'Marginally relevant'),
      ];

      // Stub for rerank LLM call
      when(mockLlm.complete(any)).thenAnswer((_) async {
        return LlmResponse(text: '[4, 1, 2]'); // Assume LLM says doc4 > doc1 > doc2
      });

      final query = 'test query about relevant content';

      final results = await retriever.rerankResults(
        query,
        candidates,
        topK: 3,
        useLightweightRanker: false,
      );

      // Should return 3 results
      expect(results.length, equals(3));

      // Expected ranked order based on mock response
      expect(results[0].id, equals('doc4'));
      expect(results[1].id, equals('doc1'));
      expect(results[2].id, equals('doc2'));

      // Make sure excluded doc is not present
      final resultIds = results.map((doc) => doc.id).toList();
      expect(resultIds, isNot(contains('doc3')));
      expect(resultIds, isNot(contains('doc5')));
    });
  });

  group('BatchEmbeddingProcessor', () {
    late MockDocumentStore mockStore;
    late MockLlmInterface mockLlm;
    late BatchEmbeddingProcessor processor;

    setUp(() {
      mockStore = MockDocumentStore();
      mockLlm = MockLlmInterface();
      processor = BatchEmbeddingProcessor(
        llmProvider: mockLlm,
        batchSize: 2, // Small batch size for testing
      );
    });

    test('processDocumentBatch processes in batches', () async {
      // Create test documents without embeddings
      final documents = [
        Document(id: 'doc1', title: 'Doc 1', content: 'Content 1'),
        Document(id: 'doc2', title: 'Doc 2', content: 'Content 2'),
        Document(id: 'doc3', title: 'Doc 3', content: 'Content 3'),
        Document(id: 'doc4', title: 'Doc 4', content: 'Content 4'),
        Document(id: 'doc5', title: 'Doc 5', content: 'Content 5'),
      ];

      // Setup mock embedding responses
      when(mockLlm.getEmbeddings('Content 1')).thenAnswer((_) async => [0.1, 0.2]);
      when(mockLlm.getEmbeddings('Content 2')).thenAnswer((_) async => [0.3, 0.4]);
      when(mockLlm.getEmbeddings('Content 3')).thenAnswer((_) async => [0.5, 0.6]);
      when(mockLlm.getEmbeddings('Content 4')).thenAnswer((_) async => [0.7, 0.8]);
      when(mockLlm.getEmbeddings('Content 5')).thenAnswer((_) async => [0.9, 1.0]);

      // Process documents
      final processed = await processor.processDocumentBatch(documents);

      // Should process all documents
      expect(processed.length, equals(5));

      // Each document should have embeddings
      for (final doc in processed) {
        expect(doc.embedding, isNotNull);
        expect(doc.embedding!.length, equals(2));
      }

      // Verify batching - should make 3 batches of 2, 2, and 1 documents
      verify(mockLlm.getEmbeddings('Content 1')).called(1);
      verify(mockLlm.getEmbeddings('Content 2')).called(1);
      verify(mockLlm.getEmbeddings('Content 3')).called(1);
      verify(mockLlm.getEmbeddings('Content 4')).called(1);
      verify(mockLlm.getEmbeddings('Content 5')).called(1);
    });

    test('processDocumentBatchWithCustomSize overrides batch size', () async {
      // Create test documents
      final documents = [
        Document(id: 'doc1', title: 'Doc 1', content: 'Content 1'),
        Document(id: 'doc2', title: 'Doc 2', content: 'Content 2'),
        Document(id: 'doc3', title: 'Doc 3', content: 'Content 3'),
      ];

      // Setup mock responses
      when(mockLlm.getEmbeddings(any)).thenAnswer((_) async => [0.1, 0.2]);

      // Process with custom batch size
      final processed = await processor.processDocumentBatchWithCustomSize(
          documents,
          1 // Process one at a time
      );

      // Should process all documents
      expect(processed.length, equals(3));

      // Original batch size should be preserved
      expect(processor.batchSize, equals(2));
    });

    test('processCollection updates document store', () async {
      // Create test documents
      final documents = [
        Document(id: 'doc1', title: 'Doc 1', content: 'Content 1'),
        Document(id: 'doc2', title: 'Doc 2', content: 'Content 2'),
      ];

      // Setup mock responses
      when(mockLlm.getEmbeddings(any)).thenAnswer((_) async => [0.1, 0.2]);

      when(mockStore.getDocumentsInCollection('test-collection'))
          .thenReturn(documents);

      // Process collection
      await processor.processCollection(mockStore, 'test-collection');

      // Should update each document in store
      verify(mockStore.updateDocument(any)).called(2);
    });

    test('Skips documents that already have embeddings', () async {
      // Mix of documents with and without embeddings
      final documents = [
        Document(
          id: 'doc1',
          title: 'Doc 1',
          content: 'Content 1',
          embedding: [0.5, 0.6], // Already has embedding
        ),
        Document(
          id: 'doc2',
          title: 'Doc 2',
          content: 'Content 2',
        ),
      ];

      // Setup mock response
      when(mockLlm.getEmbeddings('Content 2')).thenAnswer((_) async => [0.3, 0.4]);

      // Process documents
      final processed = await processor.processDocumentBatch(documents);

      // Verify all documents processed
      expect(processed.length, equals(2));

      // Verify only doc2 embedding generated
      verify(mockLlm.getEmbeddings('Content 2')).called(1);
      verifyNever(mockLlm.getEmbeddings('Content 1'));

      // Adjust expectation: If actual implementation changes doc1's embedding
      expect(processed[0].embedding, equals([0.5, 0.6]));
    });
  });
}