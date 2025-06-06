// test/integration_test.dart
@Tags(['integration'])
library;

import 'dart:io';
import 'dart:math';
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
  // Check if API keys are available
  final String? openAiKey = Platform.environment['OPENAI_API_KEY'];
  final String? claudeKey = Platform.environment['ANTHROPIC_API_KEY'];
  final String? togetherKey = Platform.environment['TOGETHER_API_KEY'];

  final bool hasOpenAiKey = openAiKey != null && openAiKey.isNotEmpty;
  final bool hasClaudeKey = claudeKey != null && claudeKey.isNotEmpty;
  final bool hasTogetherKey = togetherKey != null && togetherKey.isNotEmpty;

  // Print available keys for test configuration
  print('Available API keys for testing:');
  print('OpenAI API Key: ${hasOpenAiKey ? 'Available ✓' : 'Missing ✗'}');
  print('Claude API Key: ${hasClaudeKey ? 'Available ✓' : 'Missing ✗'}');
  print('Together API Key: ${hasTogetherKey ? 'Available ✓' : 'Missing ✗'}');

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

    test(
      'Basic OpenAI completion integration test',
          () async {
        // Create LLM client with explicit API key
        final client = await mcpLlm.createClient(
          providerName: 'openai',
          config: LlmConfiguration(
            apiKey: openAiKey,
            model: 'gpt-3.5-turbo',
          ),
        );

        // Send a simple completion request
        final response = await client.chat('What is the capital of France?');

        // Check the response
        expect(response.text, contains('Paris'));
      },
      skip: !hasOpenAiKey ? 'OpenAI API key not available' : false,
      tags: ['openai'],
    );

    test(
      'OpenAI streaming integration test',
          () async {
        // Create LLM client with explicit API key
        final client = await mcpLlm.createClient(
          providerName: 'openai',
          config: LlmConfiguration(
            apiKey: openAiKey,
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
      },
      skip: !hasOpenAiKey ? 'OpenAI API key not available' : false,
      tags: ['openai', 'streaming'],
    );

    test(
      'OpenAI embedding integration test',
          () async {
        // Create LLM client with explicit API key
        final client = await mcpLlm.createClient(
          providerName: 'openai',
          config: LlmConfiguration(
            apiKey: openAiKey,
            model: 'gpt-3.5-turbo',
          ),
        );

        // Generate embeddings
        final embeddings = await client.llmProvider.getEmbeddings('Hello world');

        // Verify embeddings
        expect(embeddings, isNotEmpty);
        expect(embeddings, isA<List<double>>());
        expect(embeddings.length, greaterThan(100)); // OpenAI embeddings are quite large
      },
      skip: !hasOpenAiKey ? 'OpenAI API key not available' : false,
      tags: ['openai', 'embeddings'],
    );

    test(
      'Claude integration test',
          () async {
          final client = await mcpLlm.createClient(
            providerName: 'claude',
            config: LlmConfiguration(
              apiKey: claudeKey,
              model: 'claude-3-haiku-20240307',
            ),
          );

          // Send a simple completion request
          final response = await client.chat('What is the capital of France?');

          // Check the response
          expect(response.text, contains('Paris'));
      },
      skip: !hasClaudeKey ? 'Claude API key not available' : false,
      tags: ['claude'],
    );

    test(
      'Together integration test',
          () async {
        // Create LLM client with explicit API key
        final client = await mcpLlm.createClient(
          providerName: 'together',
          config: LlmConfiguration(
            apiKey: togetherKey,
            model: 'mistralai/Mixtral-8x7B-Instruct-v0.1',
          ),
        );

        // Send a simple completion request
        final response = await client.chat('What is the capital of France?');

        // Check the response
        expect(response.text, contains('Paris'));
      },
      skip: !hasTogetherKey ? 'Together API key not available' : false,
      tags: ['together'],
    );

    test(
      'End-to-end RAG workflow',
          () async {
        // Create memory storage
        final storage = MemoryStorage();

        // Create document store
        final documentStore = DocumentStore(storage);

        // Create client with explicit API key
        final client = await mcpLlm.createClient(
          providerName: 'openai',
          config: LlmConfiguration(
            apiKey: openAiKey,
            model: 'gpt-4',
          ),
        );

        // Create retrieval manager
        final retrievalManager = RetrievalManager.withDocumentStore(
          llmProvider: client.llmProvider,
          documentStore: documentStore,
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
      },
      skip: !hasOpenAiKey ? 'OpenAI API key not available' : false,
      tags: ['openai', 'rag'],
    );
  });
}

Future<String> callClaudeWithRetry({
  required LlmClient client,
  required String prompt,
  int maxAttempts = 3,
  Duration initialDelay = const Duration(seconds: 2),
}) async {
  for (int attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      final response = await client.chat(prompt);
      return response.text;
    } catch (e) {
      if (attempt == maxAttempts - 1) {
        rethrow;
      }
      final delay = initialDelay * pow(2, attempt).toInt();
      print('Claude call failed (attempt ${attempt + 1})... retrying in ${delay.inSeconds}s');
      await Future.delayed(delay);
    }
  }
  return 'Error: Claude failed after $maxAttempts attempts';
}