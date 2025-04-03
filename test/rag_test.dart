import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_llm/src/rag/document_chunker.dart';
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'rag_test.mocks.dart';

@GenerateMocks([DocumentStore, LlmInterface, LlmResponse])
void main() {
  group('Embeddings', () {
    test('Embedding vector initialization', () {
      final vector = [1.0, 2.0, 3.0];
      final embedding = Embedding(vector);

      expect(embedding.vector, equals(vector));
      expect(embedding.dimension, equals(3));
    });

    test('Embedding fromJson construction', () {
      final json = [1.0, 2.0, 3.0];
      final embedding = Embedding.fromJson(json);

      expect(embedding.vector, equals(json));
    });

    test('toJson serialization', () {
      final vector = [1.0, 2.0, 3.0];
      final embedding = Embedding(vector);

      expect(embedding.toJson(), equals(vector));
    });

    test('cosineSimilarity calculation', () {
      final e1 = Embedding([1.0, 0.0, 0.0]);
      final e2 = Embedding([0.0, 1.0, 0.0]);
      final e3 = Embedding([1.0, 1.0, 0.0]);

      expect(e1.cosineSimilarity(e1), equals(1.0));
      expect(e1.cosineSimilarity(e2), equals(0.0));
      expect(e1.cosineSimilarity(e3), closeTo(0.7071, 0.001));
    });

    test('normalize creates unit vector', () {
      final e = Embedding([3.0, 4.0]);
      final normalized = e.normalize();

      // Length of [3,4] is 5
      expect(normalized.vector[0], equals(0.6));
      expect(normalized.vector[1], equals(0.8));
    });

    test('binary conversion', () {
      final original = Embedding([1.5, 2.5, 3.5]);
      final binary = original.toBinary();
      final fromBinary = Embedding.fromBinary(binary);

      expect(fromBinary.vector, original.vector);
    });

    test('base64 conversion', () {
      final original = Embedding([1.5, 2.5, 3.5]);
      final base64Str = original.toBase64();
      final fromBase64 = Embedding.fromBase64(base64Str);

      expect(fromBase64.vector, original.vector);
    });
  });

  group('Document Store', () {
    late MockDocumentStore mockStore;
    late Document doc1;
    late Document doc2;

    setUp(() {
      mockStore = MockDocumentStore();

      doc1 = Document(
        id: 'doc1',
        title: 'Test Document 1',
        content: 'This is a test document about AI',
        embedding: [0.1, 0.2, 0.3, 0.4],
        metadata: {'category': 'AI'},
        collectionId: 'collection1',
      );

      doc2 = Document(
        id: 'doc2',
        title: 'Test Document 2',
        content: 'This is another test document about ML',
        embedding: [0.2, 0.3, 0.4, 0.5],
        metadata: {'category': 'ML'},
        collectionId: 'collection1',
      );
    });

    test('Document serialization and deserialization', () {
      final json = doc1.toJson();
      final fromJson = Document.fromJson(json);

      expect(fromJson.id, equals(doc1.id));
      expect(fromJson.title, equals(doc1.title));
      expect(fromJson.content, equals(doc1.content));
      expect(fromJson.embedding, equals(doc1.embedding));
      expect(fromJson.metadata, equals(doc1.metadata));
      expect(fromJson.collectionId, equals(doc1.collectionId));
    });

    test('withEmbedding creates document copy with new embedding', () {
      final newEmbedding = [0.5, 0.6, 0.7, 0.8];
      final newDoc = doc1.withEmbedding(newEmbedding);

      expect(newDoc.id, equals(doc1.id));
      expect(newDoc.embedding, equals(newEmbedding));
      expect(newDoc.title, equals(doc1.title));
    });

    test('withCollectionId creates document copy with new collection', () {
      final newCollection = 'collection2';
      final newDoc = doc1.withCollectionId(newCollection);

      expect(newDoc.id, equals(doc1.id));
      expect(newDoc.collectionId, equals(newCollection));
      expect(newDoc.title, equals(doc1.title));
    });

    test('findSimilar returns documents by similarity', () async {
      when(mockStore.findSimilar(
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenAnswer((_) async => [doc1, doc2]);

      final results = await mockStore.findSimilar(
        [0.1, 0.2, 0.3, 0.4],
        limit: 2,
      );

      expect(results.length, equals(2));
      expect(results[0].id, equals('doc1'));
      expect(results[1].id, equals('doc2'));
    });
  });

  group('RetrievalManager', () {
    late MockDocumentStore mockStore;
    late MockLlmInterface mockLlm;
    late RetrievalManager manager;

    setUp(() {
      mockStore = MockDocumentStore();
      mockLlm = MockLlmInterface();

      manager = RetrievalManager(
        documentStore: mockStore,
        llmProvider: mockLlm,
      );
    });

    test('addDocument generates embeddings for documents without them', () async {
      // Setup mock behavior
      when(mockLlm.getEmbeddings(any)).thenAnswer(
            (_) async => [0.1, 0.2, 0.3],
      );

      when(mockStore.addDocument(any)).thenAnswer(
            (_) async => 'doc1',
      );

      // Document without embeddings
      final doc = Document(
        title: 'Test Doc',
        content: 'Test content',
      );

      // Add document
      final id = await manager.addDocument(doc);

      // Should call getEmbeddings
      verify(mockLlm.getEmbeddings(doc.content)).called(1);

      // Should add document with embeddings
      final docCaptor = verify(mockStore.addDocument(captureAny)).captured.first;
      expect(docCaptor.embedding, equals([0.1, 0.2, 0.3]));

      expect(id, equals('doc1'));
    });

    test('retrieveRelevant finds similar documents', () async {
      // Setup mock behavior
      when(mockLlm.getEmbeddings(any)).thenAnswer(
            (_) async => [0.1, 0.2, 0.3],
      );

      when(mockStore.findSimilar(
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenAnswer((_) async => [
        Document(id: 'doc1', title: 'Doc 1', content: 'Content 1'),
        Document(id: 'doc2', title: 'Doc 2', content: 'Content 2'),
      ]);

      // Retrieve documents
      final docs = await manager.retrieveRelevant(
        'test query',
        topK: 2,
      );

      // Should call getEmbeddings
      verify(mockLlm.getEmbeddings('test query')).called(1);

      // Should call findSimilar
      verify(mockStore.findSimilar(
        any,
        limit: 2,
        minimumScore: null,
      )).called(1);

      expect(docs.length, equals(2));
      expect(docs[0].id, equals('doc1'));
      expect(docs[1].id, equals('doc2'));
    });

    test('retrieveAndGenerate gets documents and generates response', () async {
      // Setup mock behavior
      when(mockLlm.getEmbeddings(any)).thenAnswer(
            (_) async => [0.1, 0.2, 0.3],
      );

      when(mockStore.findSimilar(
        any,
        limit: anyNamed('limit'),
        minimumScore: anyNamed('minimumScore'),
      )).thenAnswer((_) async => [
        Document(id: 'doc1', title: 'Doc 1', content: 'Content 1'),
      ]);

      final mockResponse = MockLlmResponse();
      when(mockResponse.text).thenReturn('Generated response');
      when(mockLlm.complete(any)).thenAnswer(
            (_) async => mockResponse,
      );

      // Execute retrieval and generation
      final response = await manager.retrieveAndGenerate('test query');

      // Verify embedding generation
      verify(mockLlm.getEmbeddings('test query')).called(1);

      // Verify document retrieval
      verify(mockStore.findSimilar(
        any,
        limit: 5, // Default limit
        minimumScore: null,
      )).called(1);

      // Verify response generation
      verify(mockLlm.complete(any)).called(1);

      expect(response, equals('Generated response'));
    });
  });

  group('DocumentChunker', () {
    late DocumentChunker chunker;

    setUp(() {
      chunker = DocumentChunker(
        defaultChunkSize: 100,
        defaultChunkOverlap: 20,
      );
    });

    test('keeps short documents intact', () {
      final content = 'Short content';

      final doc = Document(
        id: 'doc1',
        title: 'Small Document',
        content: content,
      );

      final chunks = chunker.chunkDocument(doc);

      // 짧은 내용은 청크로 나누지 않음
      expect(chunks.length, equals(1));
      expect(chunks[0].content, equals(content));
    });

    test('properly preserves metadata in chunks', () {
      final content = 'A' * 50;

      final doc = Document(
        id: 'doc1',
        title: 'Test Document',
        content: content,
        metadata: {'key': 'value', 'test': true},
      );

      final chunks = chunker.chunkDocument(doc);

      print('Chunk metadata keys: ${chunks[0].metadata.keys.toList()}');
      print('Chunk metadata: ${chunks[0].metadata}');

      expect(chunks[0].metadata.containsKey('key'), isTrue);
      expect(chunks[0].metadata['key'], equals('value'));
    });

    test('produces valid chunks from multiple documents', () {
      final docs = [
        Document(
          id: 'doc1',
          title: 'Doc 1',
          content: 'Document 1 content',
          metadata: {'source': 'test1'},
        ),
        Document(
          id: 'doc2',
          title: 'Doc 2',
          content: 'Document 2 content',
          metadata: {'source': 'test2'},
        )
      ];

      final chunks = chunker.chunkDocuments(docs);

      print('Number of chunks: ${chunks.length}');
      for (int i = 0; i < chunks.length; i++) {
        print('Chunk $i content: ${chunks[i].content}');
        print('Chunk $i metadata: ${chunks[i].metadata}');
      }

      expect(chunks.length, greaterThanOrEqualTo(docs.length));

      final allChunkContent = chunks.map((c) => c.content).join();
      expect(allChunkContent.contains('Document 1'), isTrue);
      expect(allChunkContent.contains('Document 2'), isTrue);

      if (chunks[0].metadata.containsKey('source')) {
        expect(chunks[0].metadata['source'], isNotNull);
      }
    });

    test('handles very large content appropriately', () {
      final paragraphs = List.generate(10, (i) => 'Paragraph $i. ' + 'A' * 50);
      final content = paragraphs.join('\n\n'); // 명확한 단락 구분자

      final doc = Document(
        id: 'largeDoc',
        title: 'Very Large Document',
        content: content,
      );

      final chunks = chunker.chunkDocument(doc);

      expect(chunks.isNotEmpty, isTrue);

      final allContent = chunks.map((c) => c.content).join();
      for (final para in paragraphs) {
        expect(allContent.contains(para.substring(0, 10)), isTrue); // 각 단락의 일부가 포함되어 있는지 확인
      }
    });
  });
}