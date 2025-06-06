import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_llm/src/rag/document_chunker.dart';
import 'package:mcp_llm/src/rag/batch_embedding_processor.dart';
import 'package:mockito/mockito.dart';

import 'rag_test.mocks.dart';

void main() {
  group('End-to-End RAG Integration Tests', () {
    late MockDocumentStore documentStore;
    late MockLlmInterface llmProvider;
    late RetrievalManager retrievalManager;
    late DocumentChunker chunker;
    late BatchEmbeddingProcessor embeddingProcessor;

    setUp(() {
      documentStore = MockDocumentStore();
      llmProvider = MockLlmInterface();
      retrievalManager = RetrievalManager(
        llmProvider: llmProvider,
        documentStore: documentStore,
      );
      chunker = DocumentChunker();
      embeddingProcessor = BatchEmbeddingProcessor(
        llmProvider: llmProvider,
      );
    });

    test('Complete RAG pipeline - chunking, embedding, retrieval, generation', () async {
      // 1. Start with a source document
      final sourceDocument = Document(
        id: 'source1',
        title: 'Universe Facts',
        content: '''The universe is vast and contains billions of galaxies.
Our solar system is in the Milky Way galaxy.
The Milky Way contains between 100-400 billion stars.
The Sun is a G-type main-sequence star and is about 4.6 billion years old.
Earth is the third planet from the Sun and is approximately 4.5 billion years old.
Jupiter is the largest planet in our solar system.
Saturn is known for its prominent ring system.''',
      );

      // 2. Chunk the document
      final chunks = chunker.chunkDocument(
        sourceDocument,
        chunkSize: 100,
        chunkOverlap: 20,
      );

      // Verify chunks were created
      expect(chunks.length, greaterThan(1));
      expect(chunks.every((chunk) => chunk.metadata['parent_document_id'] == 'source1'), isTrue);

      // 3. Setup mock for embedding generation
      when(llmProvider.getEmbeddings(any)).thenAnswer((_) async => [0.1, 0.2, 0.3, 0.4]);

      // 4. Process chunks to add embeddings
      final processedChunks = await embeddingProcessor.processDocumentBatch(chunks);

      // Verify embeddings were added
      expect(processedChunks.every((chunk) => chunk.embedding != null), isTrue);

      // 5. Mock adding documents to store
      for (final chunk in processedChunks) {
        when(documentStore.addDocument(chunk)).thenAnswer((_) async => chunk.id);
      }

      // Add documents to store
      for (final chunk in processedChunks) {
        await retrievalManager.addDocument(chunk);
      }

      // 6. Setup mock for retrieval
      when(documentStore.findSimilar(
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenAnswer((_) async => [processedChunks.first, processedChunks.last]);

      // 7. Mock LLM response generation
      final mockResponse = MockLlmResponse();
      when(mockResponse.text).thenReturn('The universe contains billions of galaxies and our solar system is in the Milky Way galaxy.');
      when(llmProvider.complete(any)).thenAnswer((_) async => mockResponse);

      // 8. Test retrieveAndGenerate
      final result = await retrievalManager.retrieveAndGenerate(
        'Tell me about the universe',
      );

      // Verify correct result
      expect(result, contains('universe'));
      expect(result, contains('galaxies'));
      expect(result, contains('Milky Way'));

      // Verify the correct methods were called
      verify(documentStore.findSimilar(
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).called(1);

      verify(llmProvider.complete(any)).called(1);
    });

    test('Hybrid search with multilingual content', () async {
      // Create mixed language documents
      final docs = [
        Document(
          id: 'en1',
          title: 'English Document',
          content: 'This is a document in English about artificial intelligence and machine learning.',
          embedding: [0.1, 0.2, 0.3],
          metadata: {'language': 'en'},
        ),
        Document(
          id: 'ko1',
          title: 'Korean Document',
          content: 'This document is a Korean document about artificial intelligence and machine learning.',
          embedding: [0.4, 0.5, 0.6],
          metadata: {'language': 'ko'},
        ),
      ];

      // Setup mocks
      when(llmProvider.getEmbeddings('AI and machine learning')).thenAnswer((_) async => [0.1, 0.2, 0.3]);

      when(documentStore.findSimilar(
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenAnswer((_) async => docs);

      when(documentStore.searchByContent(
        any,
        limit: anyNamed('limit'),
      )).thenReturn([docs[0]]); // Only find English doc by keyword

      // Test hybrid search
      final results = await retrievalManager.hybridSearch(
        'AI and machine learning',
        semanticResults: 5,
        keywordResults: 5,
        finalResults: 5,
      );

      // Should return both documents
      expect(results.length, equals(2));
      expect(results.any((doc) => doc.id == 'en1'), isTrue);
      expect(results.any((doc) => doc.id == 'ko1'), isTrue);
    });

    test('Context-aware conversation search', () async {
      // Previous conversation context
      final previousQueries = [
        'Tell me about solar panels',
        'How do they convert sunlight to electricity?'
      ];

      // Setup mocks for query expansion
      final mockExpandResponse = MockLlmResponse();
      when(mockExpandResponse.text).thenReturn('How efficient are solar panels at converting sunlight to electricity');

      // For the first complete call (context expansion)
      when(llmProvider.complete(any)).thenAnswer((_) => Future.value(mockExpandResponse));

      // Mock embeddings for expanded query
      when(llmProvider.getEmbeddings(any)).thenAnswer((_) async => [0.1, 0.2, 0.3]);

      // Mock retrieved documents
      final retrievedDocs = [
        Document(
          id: 'solar_efficiency',
          title: 'Solar Panel Efficiency',
          content: 'Modern solar panels typically convert 15-20% of sunlight into electricity.',
          embedding: [0.1, 0.2, 0.3],
        ),
      ];

      when(documentStore.findSimilar(
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenAnswer((_) async => retrievedDocs);

      when(documentStore.searchByContent(
        any,
        limit: anyNamed('limit'),
      )).thenReturn([]);

      // Test context-aware search
      final results = await retrievalManager.contextAwareSearch(
        'What is their efficiency?',
        previousQueries,
      );

      // Verify expanded query was used for search
      verify(llmProvider.complete(any)).called(1);
      verify(llmProvider.getEmbeddings(any)).called(1);

      expect(results, equals(retrievedDocs));
    });

    test('Time-weighted retrieval prioritizes recent documents', () async {
      // Create documents with different timestamps
      final now = DateTime.now();

      final docs = [
        Document(
          id: 'old',
          title: 'Old Document',
          content: 'Old content about AI',
          embedding: [0.1, 0.2, 0.3],
          updatedAt: now.subtract(Duration(days: 60)),
        ),
        Document(
          id: 'recent',
          title: 'Recent Document',
          content: 'Recent content about AI',
          embedding: [0.4, 0.5, 0.6],
          updatedAt: now.subtract(Duration(days: 2)),
        ),
        Document(
          id: 'medium',
          title: 'Medium Document',
          content: 'Medium-age content about AI',
          embedding: [0.7, 0.8, 0.9],
          updatedAt: now.subtract(Duration(days: 25)),
        ),
      ];

      // Setup mocks
      when(llmProvider.getEmbeddings('What is AI?')).thenAnswer((_) async => [0.1, 0.2, 0.3]);

      when(documentStore.findSimilar(
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenAnswer((_) async => docs);

      // Test time-weighted retrieval
      final results = await retrievalManager.timeWeightedRetrieval(
        'What is AI?',
        recencyWeight: 1.0, // High weight on recency
      );

      // First result should be most recent document
      expect(results.first.id, equals('recent'));

      // Last result should be oldest document
      final ids = results.map((doc) => doc.id).toList();
      expect(ids, equals(['recent', 'medium', 'old']));
    });

    test('Multi-collection search combines results', () async {
      // Create collections
      final collection1Docs = [
        Document(
          id: 'col1_doc1',
          title: 'Collection 1 Document',
          content: 'Content from collection 1 about AI',
          embedding: [0.1, 0.2, 0.3],
          collectionId: 'collection1',
        ),
      ];

      final collection2Docs = [
        Document(
          id: 'col2_doc1',
          title: 'Collection 2 Document',
          content: 'Content from collection 2 about AI',
          embedding: [0.4, 0.5, 0.6],
          collectionId: 'collection2',
        ),
      ];

      // Setup mocks
      when(llmProvider.getEmbeddings('AI across collections')).thenAnswer((_) async => [0.1, 0.2, 0.3]);

      when(documentStore.findSimilarInCollection(
        'collection1',
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenAnswer((_) async => collection1Docs);

      when(documentStore.findSimilarInCollection(
        'collection2',
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenAnswer((_) async => collection2Docs);

      // Test multi-collection search
      final results = await retrievalManager.multiCollectionSearch(
        'AI across collections',
        ['collection1', 'collection2'],
      );

      // Should contain documents from both collections
      expect(results.length, equals(2));
      expect(results.any((doc) => doc.id == 'col1_doc1'), isTrue);
      expect(results.any((doc) => doc.id == 'col2_doc1'), isTrue);
    });
  });

  group('Error Handling and Recovery', () {
    late MockDocumentStore documentStore;
    late MockLlmInterface llmProvider;
    late RetrievalManager retrievalManager;

    setUp(() {
      documentStore = MockDocumentStore();
      llmProvider = MockLlmInterface();
      retrievalManager = RetrievalManager(
        llmProvider: llmProvider,
        documentStore: documentStore,
      );
    });

    test('Handles embedding generation failure gracefully', () async {
      // Setup mock to throw an error
      when(llmProvider.getEmbeddings(any)).thenThrow(Exception('API failure'));

      // Create test document
      final doc = Document(
        id: 'test1',
        title: 'Test Document',
        content: 'Test content',
      );

      // Should not throw but return document without embedding
      when(documentStore.addDocument(any)).thenAnswer((_) async => 'test1');

      // Add document should handle the error
      final id = await retrievalManager.addDocument(doc).catchError((e) {
        // If it fails completely, return empty string
        return '';
      });
      expect(id, isNotEmpty);

      // Verify proper API calls
      verify(llmProvider.getEmbeddings(any)).called(1);
    });

    test('Handles retrieval error with fallback', () async {
      // Setup embedding to work but retrieval to fail
      when(llmProvider.getEmbeddings(any)).thenAnswer((_) async => [0.1, 0.2, 0.3]);
      when(documentStore.findSimilar(
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenThrow(Exception('Database error'));

      // Setup fallback generation
      final mockResponse = MockLlmResponse();
      when(mockResponse.text).thenReturn('I don\'t have specific information about that.');
      when(llmProvider.complete(any)).thenAnswer((_) async => mockResponse);

      // Should not throw but fall back to direct generation
      final result = await retrievalManager.retrieveAndGenerate(
        'Tell me about AI',
      ).catchError((e) {
        return 'Error occurred';
      });

      // Should get a response even with retrieval failure
      expect(result, isNot(equals('Error occurred')));
    });
  });

  group('Performance Optimization Tests', () {
    late MockDocumentStore documentStore;
    late MockLlmInterface llmProvider;
    late RetrievalManager retrievalManager;

    setUp(() {
      documentStore = MockDocumentStore();
      llmProvider = MockLlmInterface();
      retrievalManager = RetrievalManager(
        llmProvider: llmProvider,
        documentStore: documentStore,
      );
    });

    test('Caching improves performance for repeated queries', () async {
      // Setup mocks
      when(llmProvider.getEmbeddings('repeated query')).thenAnswer((_) async => [0.1, 0.2, 0.3]);

      final mockDocs = [
        Document(id: 'doc1', title: 'Doc 1', content: 'Content 1', embedding: [0.1, 0.2, 0.3]),
        Document(id: 'doc2', title: 'Doc 2', content: 'Content 2', embedding: [0.4, 0.5, 0.6]),
      ];

      when(documentStore.findSimilar(
        [0.1, 0.2, 0.3],
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenAnswer((_) async => mockDocs);

      // First query: should call embedding and search
      await retrievalManager.retrieveRelevant('repeated query', useCache: true);

      verify(llmProvider.getEmbeddings('repeated query')).called(1);
      verify(documentStore.findSimilar(
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).called(1);

      // Reset mocks
      reset(llmProvider);
      reset(documentStore);

      // Second query: should use cache
      final second = await retrievalManager.retrieveRelevant('repeated query', useCache: true);
      expect(second, isNotEmpty);

      verifyNever(llmProvider.getEmbeddings(any));
      verifyNever(documentStore.findSimilar(
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      ));

      // Third query with cache disabled
      when(llmProvider.getEmbeddings('repeated query')).thenAnswer((_) async => [0.1, 0.2, 0.3]);
      when(documentStore.findSimilar(
        [0.1, 0.2, 0.3],
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenAnswer((_) async => mockDocs);

      await retrievalManager.retrieveRelevant('repeated query', useCache: false);

      verify(llmProvider.getEmbeddings('repeated query')).called(1);
      verify(documentStore.findSimilar(
        [0.1, 0.2, 0.3],
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).called(1);
    });

    test('Batch processing is efficient for multiple documents', () async {
      // Create batch processor
      final batchProcessor = BatchEmbeddingProcessor(
        llmProvider: llmProvider,
        batchSize: 3,
      );

      // Create 5 documents
      final docs = List.generate(5, (i) =>
          Document(id: 'doc$i', title: 'Doc $i', content: 'Content $i')
      );

      // Setup mock for embeddings
      for (int i = 0; i < 5; i++) {
        when(llmProvider.getEmbeddings('Content $i')).thenAnswer((_) async => [i + 0.1, i + 0.2, i + 0.3]);
      }

      // Process batch
      final processed = await batchProcessor.processDocumentBatch(docs);

      // Should process all documents
      expect(processed.length, equals(5));

      // Should process in batches (2 batches: 3 + 2)
      verify(llmProvider.getEmbeddings('Content 0')).called(1);
      verify(llmProvider.getEmbeddings('Content 1')).called(1);
      verify(llmProvider.getEmbeddings('Content 2')).called(1);
      verify(llmProvider.getEmbeddings('Content 3')).called(1);
      verify(llmProvider.getEmbeddings('Content 4')).called(1);
    });
  });
}