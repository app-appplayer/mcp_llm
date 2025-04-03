import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_llm/src/rag/document_chunker.dart';
import 'package:test/test.dart';

/// These tests require actual API keys and make real API calls.
/// Run these tests with care as they might incur costs.
///
/// To run these tests, set the appropriate environment variables:
/// - OPENAI_API_KEY
/// - ANTHROPIC_API_KEY
/// - TOGETHER_API_KEY
void main() {
  // Flag to enable/disable integration tests
  final bool runIntegrationTests = true;

  group('Integration Tests', () {
    late McpLlm mcpLlm;

    setUp(() {
      mcpLlm = McpLlm();
      mcpLlm.registerProvider('openai', OpenAiProviderFactory());
      mcpLlm.registerProvider('claude', ClaudeProviderFactory());
      mcpLlm.registerProvider('together', TogetherProviderFactory());
    });

    tearDown(() async {
      await mcpLlm.shutdown();
    });

    test('Basic OpenAI completion integration test', () async {
      if (!runIntegrationTests) {
        print('Skipping OpenAI integration test');
        return;
      }

      // Create LLM client
      final client = await mcpLlm.createClient(
        providerName: 'openai',
        config: LlmConfiguration(
          // API key from environment variable
          model: 'gpt-3.5-turbo',
        ),
      );

      // Send a simple completion request
      final response = await client.chat('What is the capital of France?');

      // Check the response
      expect(response.text, contains('Paris'));
    }, skip: !runIntegrationTests);

    test('OpenAI streaming integration test', () async {
      if (!runIntegrationTests) {
        print('Skipping OpenAI streaming integration test');
        return;
      }

      // Create LLM client
      final client = await mcpLlm.createClient(
        providerName: 'openai',
        config: LlmConfiguration(
          // API key from environment variable
          model: 'gpt-3.5-turbo',
        ),
      );

      // Stream completion
      final chunks = <String>[];
      await for (final chunk in client.streamChat('Count from 1 to 5')) {
        chunks.add(chunk.textChunk);

        if (chunk.isDone) break;
      }

      // Verify streaming chunks
      final combinedText = chunks.join('');
      expect(combinedText, contains('1'));
      expect(combinedText, contains('2'));
      expect(combinedText, contains('3'));
      expect(combinedText, contains('4'));
      expect(combinedText, contains('5'));
    }, skip: !runIntegrationTests);

    test('OpenAI embedding integration test', () async {
      if (!runIntegrationTests) {
        print('Skipping OpenAI embedding integration test');
        return;
      }

      // Create LLM client
      final client = await mcpLlm.createClient(
        providerName: 'openai',
        config: LlmConfiguration(
          // API key from environment variable
          model: 'gpt-3.5-turbo',
        ),
      );

      // Generate embeddings
      final embeddings = await client.llmProvider.getEmbeddings('Hello world');

      // Verify embeddings
      expect(embeddings, isNotEmpty);
      expect(embeddings, isA<List<double>>());
      expect(embeddings.length, greaterThan(100)); // OpenAI embeddings are quite large
    }, skip: !runIntegrationTests);

    test('Claude integration test', () async {
      if (!runIntegrationTests) {
        print('Skipping Claude integration test');
        return;
      }

      // Create LLM client
      final client = await mcpLlm.createClient(
        providerName: 'claude',
        config: LlmConfiguration(
          // API key from environment variable
          model: 'claude-3-haiku-20240307',
        ),
      );

      // Send a simple completion request
      final response = await client.chat('What is the capital of France?');

      // Check the response
      expect(response.text, contains('Paris'));
    }, skip: !runIntegrationTests);

    test('Together integration test', () async {
      if (!runIntegrationTests) {
        print('Skipping Together integration test');
        return;
      }

      // Create LLM client
      final client = await mcpLlm.createClient(
        providerName: 'together',
        config: LlmConfiguration(
          // API key from environment variable
          model: 'mistralai/Mixtral-8x7B-Instruct-v0.1',
        ),
      );

      // Send a simple completion request
      final response = await client.chat('What is the capital of France?');

      // Check the response
      expect(response.text, contains('Paris'));
    }, skip: !runIntegrationTests);

    test('End-to-end RAG workflow', () async {
      if (!runIntegrationTests) {
        print('Skipping RAG integration test');
        return;
      }

      // Create memory storage
      final storage = MemoryStorage();

      // Create document store
      final documentStore = DocumentStore(storage);

      // Create client
      final client = await mcpLlm.createClient(
        providerName: 'openai',
        config: LlmConfiguration(
          // API key from environment variable
          model: 'gpt-4',
        ),
      );

      // Create retrieval manager
      final retrievalManager = RetrievalManager(
        documentStore: documentStore,
        llmProvider: client.llmProvider,
      );

      // Create document chunker
      final chunker = DocumentChunker(
        defaultChunkSize: 500,
        defaultChunkOverlap: 100,
      );

      // Add sample documents
      final documents = [
        Document(
          title: 'Paris Facts',
          content: 'Paris is the capital of France. It is known as the City of Light.',
        ),
        Document(
          title: 'Berlin Facts',
          content: 'Berlin is the capital of Germany. It has a rich history.',
        ),
        Document(
          title: 'Rome Facts',
          content: 'Rome is the capital of Italy. It is often called the Eternal City.',
        ),
      ];

      // Chunk documents
      final chunkedDocs = chunker.chunkDocuments(documents);

      // Add documents with embeddings
      for (final doc in chunkedDocs) {
        await retrievalManager.addDocument(doc);
      }

      // Perform RAG
      final response = await retrievalManager.retrieveAndGenerate(
        'What is the capital of France, and what is it known as?',
      );

      // Check response
      expect(response, contains('Paris'));
      expect(response, contains('City of Light'));
    }, skip: !runIntegrationTests);
  });
}