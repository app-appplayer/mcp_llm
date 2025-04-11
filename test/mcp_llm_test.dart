import 'package:mcp_llm/mcp_llm.dart';
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'mcp_llm_test.mocks.dart';

@GenerateNiceMocks([
  MockSpec<LlmProviderFactory>(),
  MockSpec<LlmInterface>(),
  MockSpec<LlmRequest>(),
  MockSpec<LlmResponse>(),
  MockSpec<StorageManager>()
])

void main() {
  group('McpLlm', () {
    late McpLlm mcpLlm;
    late MockLlmProviderFactory mockProviderFactory;
    late MockLlmInterface mockProvider;

    setUp(() {
      mockProviderFactory = MockLlmProviderFactory();
      mockProvider = MockLlmInterface();
      when(mockProviderFactory.name).thenReturn('test_provider');
      when(mockProviderFactory.capabilities).thenReturn({
        LlmCapability.completion,
        LlmCapability.streaming,
      });
      when(mockProviderFactory.createProvider(any)).thenReturn(mockProvider);

      mcpLlm = McpLlm();
    });

    test('registerProvider adds provider to registry', () {
      mcpLlm.registerProvider('test_provider', mockProviderFactory);

      expect(mcpLlm.getProvidersWithCapability(LlmCapability.completion), contains('test_provider'));
    });

    test('createClient returns a client with the specified provider', () async {
      mcpLlm.registerProvider('test_provider', mockProviderFactory);

      final client = await mcpLlm.createClient(
        providerName: 'test_provider',
        config: LlmConfiguration(),
      );

      expect(client, isNotNull);
      expect(client.llmProvider, equals(mockProvider));
    });

    test('throws exception when provider not found', () {
      expect(
            () => mcpLlm.createClient(providerName: 'non_existent_provider'),
        throwsStateError,
      );
    });

    test('shutdown closes all clients', () async {
      mcpLlm.registerProvider('test_provider', mockProviderFactory);

      await mcpLlm.createClient(
        providerName: 'test_provider',
        config: LlmConfiguration(),
      );

      await mcpLlm.createClient(
        providerName: 'test_provider',
        clientId: 'client2',
        config: LlmConfiguration(),
      );

      await mcpLlm.shutdown();

      verify(mockProvider.close()).called(2);
    });
  });

  group('LlmClient', () {
    late MockLlmInterface mockProvider;
    late LlmClient client;
    late MockStorageManager mockStorage;

    setUp(() {
      mockProvider = MockLlmInterface();
      mockStorage = MockStorageManager();
      client = LlmClient(
        llmProvider: mockProvider,
        storageManager: mockStorage,
      );
    });

    test('chat sends request to provider and returns response', () async {
      final mockResponse = MockLlmResponse();
      when(mockResponse.text).thenReturn('Test response');
      when(mockResponse.metadata).thenReturn({'key': 'value'});

      when(mockProvider.complete(any)).thenAnswer((_) async => mockResponse);

      final response = await client.chat('Hello, world!');

      verify(mockProvider.complete(any)).called(1);
      expect(response.text, equals('Test response'));
      expect(response.metadata, equals({'key': 'value'}));
    });

    test('chat session adds messages to history', () async {
      final mockResponse = MockLlmResponse();
      when(mockResponse.text).thenReturn('Test response');
      when(mockProvider.complete(any)).thenAnswer((_) async => mockResponse);

      await client.chat('Hello, world!');

      // Session should have 2 messages: user and assistant
      expect(client.chatSession.messages.length, equals(2));
      expect(client.chatSession.messages[0].role, equals('user'));
      expect(client.chatSession.messages[0].content, equals('Hello, world!'));
      expect(client.chatSession.messages[1].role, equals('assistant'));
      expect(client.chatSession.messages[1].content, equals('Test response'));
    });
  });

  group('Provider', () {
    test('LlmProviderFactory creation with proper capabilities', () {
      final factory = MockProviderFactory();

      expect(factory.name, equals('mock'));
      expect(factory.capabilities, contains(LlmCapability.completion));
    });
  });

  group('Storage', () {
    late MemoryStorage storage;

    setUp(() {
      storage = MemoryStorage();
    });

    test('saveString and loadString work correctly', () async {
      await storage.saveString('testKey', 'test value');
      final result = await storage.loadString('testKey');

      expect(result, equals('test value'));
    });

    test('saveObject and loadObject work correctly', () async {
      final testObject = {'name': 'Test', 'value': 123};
      await storage.saveObject('objectKey', testObject);
      final result = await storage.loadObject('objectKey');

      expect(result, equals(testObject));
    });

    test('delete removes an item', () async {
      await storage.saveString('deleteKey', 'delete me');
      expect(await storage.exists('deleteKey'), isTrue);

      final deleted = await storage.delete('deleteKey');
      expect(deleted, isTrue);
      expect(await storage.exists('deleteKey'), isFalse);
    });

    test('clear removes all items', () async {
      await storage.saveString('key1', 'value1');
      await storage.saveString('key2', 'value2');

      await storage.clear();

      expect(await storage.loadString('key1'), isNull);
      expect(await storage.loadString('key2'), isNull);
    });
  });

  group('Embeddings', () {
    test('cosineSimilarity calculates correctly', () {
      final embedding1 = Embedding([1.0, 0.0, 0.0]);
      final embedding2 = Embedding([0.0, 1.0, 0.0]);
      final embedding3 = Embedding([1.0, 1.0, 0.0]);

      expect(embedding1.cosineSimilarity(embedding1), equals(1.0));
      expect(embedding1.cosineSimilarity(embedding2), equals(0.0));
      expect(embedding1.cosineSimilarity(embedding3), closeTo(0.7071, 0.0001));
    });

    test('normalize properly scales vectors', () {
      final embedding = Embedding([3.0, 4.0, 0.0]);
      final normalized = embedding.normalize();

      // Length should be 5, so normalized should be [0.6, 0.8, 0]
      expect(normalized.vector[0], equals(0.6));
      expect(normalized.vector[1], equals(0.8));
      expect(normalized.vector[2], equals(0.0));
    });
  });

  group('Document Store', () {
    late MockStorageManager mockStorage;
    late DocumentStore docStore;

    setUp(() {
      mockStorage = MockStorageManager();
      docStore = DocumentStore(mockStorage);
    });

    test('addDocument stores document properly', () async {
      when(mockStorage.saveObject(any, any)).thenAnswer((_) async {});

      final doc = Document(
        title: 'Test Document',
        content: 'Test content',
      );

      final id = await docStore.addDocument(doc);

      expect(id, isNotEmpty);
      verify(mockStorage.saveObject(any, any)).called(1);
    });
  });
}

/// Mock Provider Factory for testing
class MockProviderFactory implements LlmProviderFactory {
  @override
  String get name => 'mock';

  @override
  Set<LlmCapability> get capabilities => {
    LlmCapability.completion,
    LlmCapability.streaming,
  };

  @override
  LlmInterface createProvider(LlmConfiguration config) {
    return MockLlmProvider();
  }
}

/// Mock Provider Implementation
class MockLlmProvider implements LlmInterface {
  @override
  Future<void> close() async {}

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return LlmResponse(
      text: 'Mock response for: ${request.prompt}',
      metadata: {'provider': 'mock'},
    );
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return List.generate(10, (i) => i / 10);
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {}

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    yield LlmResponseChunk(
      textChunk: 'Mock ',
      isDone: false,
    );

    yield LlmResponseChunk(
      textChunk: 'streaming ',
      isDone: false,
    );

    yield LlmResponseChunk(
      textChunk: 'response',
      isDone: true,
    );
  }

  @override
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) {
    // TODO: implement extractToolCallFromMetadata
    throw UnimplementedError();
  }

  @override
  bool hasToolCallMetadata(Map<String, dynamic> metadata) {
    // TODO: implement hasToolCallMetadata
    throw UnimplementedError();
  }

  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) {
    // TODO: implement standardizeMetadata
    throw UnimplementedError();
  }
}