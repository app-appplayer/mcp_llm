import 'dart:io';
import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

/// Weather tool plugin for testing tool calling
class WeatherToolPlugin extends ToolPlugin {
  @override
  String get name => 'get_weather';

  @override
  String get version => '1.0.0';

  @override
  String get description => 'Get weather information for a location';

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}

  @override
  Future<void> shutdown() async {}

  @override
  LlmTool getToolDefinition() {
    return LlmTool(
      name: 'get_weather',
      description: 'Get weather information for a specific city',
      inputSchema: {
        'type': 'object',
        'properties': {
          'city': {
            'type': 'string',
            'description': 'City name to get weather for',
          },
        },
        'required': ['city'],
      },
    );
  }

  @override
  Future<LlmCallToolResult> execute(Map<String, dynamic> arguments) async {
    final city = arguments['city'] as String? ?? 'Unknown';
    return LlmCallToolResult(
      [LlmTextContent(text: 'Weather in $city: Sunny, 25°C')],
    );
  }
}

void main() {
  // Check API keys at top level for skip conditions
  final groqApiKey = Platform.environment['GROQ_API_KEY'] ?? '';
  final mistralApiKey = Platform.environment['MISTRAL_API_KEY'] ?? '';
  final geminiApiKey = Platform.environment['GEMINI_API_KEY'] ?? '';
  final vertexAccessToken = Platform.environment['VERTEX_ACCESS_TOKEN'] ?? '';
  final vertexProjectId = Platform.environment['VERTEX_PROJECT_ID'] ?? '';
  final cohereApiKey = Platform.environment['COHERE_API_KEY'] ?? '';
  final awsAccessKeyId = Platform.environment['AWS_ACCESS_KEY_ID'] ?? '';
  final awsSecretAccessKey = Platform.environment['AWS_SECRET_ACCESS_KEY'] ?? '';
  final awsRegion = Platform.environment['AWS_REGION'] ?? 'us-east-1';

  final hasGroqKey = groqApiKey.isNotEmpty;
  final hasMistralKey = mistralApiKey.isNotEmpty;
  final hasGeminiKey = geminiApiKey.isNotEmpty;
  final hasVertexCredentials = vertexAccessToken.isNotEmpty && vertexProjectId.isNotEmpty;
  final hasCohereKey = cohereApiKey.isNotEmpty;
  final hasAwsCredentials = awsAccessKeyId.isNotEmpty && awsSecretAccessKey.isNotEmpty;
  final hasAnyKey = hasGroqKey || hasMistralKey || hasGeminiKey || hasCohereKey || hasAwsCredentials;

  group('Cloud Providers Integration Tests', () {
    // ==================== GROQ TESTS ====================
    group('Groq Provider', () {
      test('basic chat completion', () async {
        final mcpLlm = McpLlm();
        mcpLlm.registerProvider('groq', GroqProviderFactory());

        final client = await mcpLlm.createClient(
          providerName: 'groq',
          config: LlmConfiguration(
            apiKey: groqApiKey,
            model: 'llama-3.1-8b-instant',
          ),
        );

        final response = await client.chat('Say "Hello from Groq!" and nothing else.');
        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
        expect(response.text.toLowerCase(), contains('hello'));
      }, skip: !hasGroqKey ? 'GROQ_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('streaming completion', () async {
        final provider = GroqProvider(
          apiKey: groqApiKey,
          model: 'llama-3.1-8b-instant',
          config: LlmConfiguration(apiKey: groqApiKey),
        );

        final request = LlmRequest(prompt: 'Count from 1 to 5.');

        final chunks = <String>[];
        await for (final chunk in provider.streamComplete(request)) {
          if (chunk.textChunk.isNotEmpty) {
            chunks.add(chunk.textChunk);
          }
        }

        expect(chunks, isNotEmpty);
        final fullText = chunks.join('');
        expect(fullText, isNotEmpty);
      }, skip: !hasGroqKey ? 'GROQ_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('tool calling', () async {
        final mcpLlm = McpLlm();
        mcpLlm.registerProvider('groq', GroqProviderFactory());

        final client = await mcpLlm.createClient(
          providerName: 'groq',
          config: LlmConfiguration(
            apiKey: groqApiKey,
            model: 'llama-3.1-70b-versatile',
          ),
        );

        await client.pluginManager.registerPlugin(WeatherToolPlugin());

        final response = await client.chat(
          'What is the weather in Tokyo? Use the get_weather tool.',
          enableTools: false,
          enablePlugins: true,
        );

        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
      }, skip: !hasGroqKey ? 'GROQ_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 60)));
    });

    // ==================== MISTRAL TESTS ====================
    group('Mistral Provider', () {
      test('basic chat completion', () async {
        final mcpLlm = McpLlm();
        mcpLlm.registerProvider('mistral', MistralProviderFactory());

        final client = await mcpLlm.createClient(
          providerName: 'mistral',
          config: LlmConfiguration(
            apiKey: mistralApiKey,
            model: 'mistral-small-latest',
          ),
        );

        final response = await client.chat('Say "Hello from Mistral!" and nothing else.');
        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
        expect(response.text.toLowerCase(), contains('hello'));
      }, skip: !hasMistralKey ? 'MISTRAL_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('streaming completion', () async {
        final provider = MistralProvider(
          apiKey: mistralApiKey,
          model: 'mistral-small-latest',
          config: LlmConfiguration(apiKey: mistralApiKey),
        );

        final request = LlmRequest(prompt: 'Count from 1 to 5.');

        final chunks = <String>[];
        await for (final chunk in provider.streamComplete(request)) {
          if (chunk.textChunk.isNotEmpty) {
            chunks.add(chunk.textChunk);
          }
        }

        expect(chunks, isNotEmpty);
      }, skip: !hasMistralKey ? 'MISTRAL_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('embeddings', () async {
        final provider = MistralProvider(
          apiKey: mistralApiKey,
          model: 'mistral-small-latest',
          config: LlmConfiguration(apiKey: mistralApiKey),
        );

        final embeddings = await provider.getEmbeddings('Hello, world!');
        expect(embeddings, isNotNull);
        expect(embeddings, isNotEmpty);
        expect(embeddings.length, greaterThan(100));
      }, skip: !hasMistralKey ? 'MISTRAL_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('tool calling', () async {
        final mcpLlm = McpLlm();
        mcpLlm.registerProvider('mistral', MistralProviderFactory());

        final client = await mcpLlm.createClient(
          providerName: 'mistral',
          config: LlmConfiguration(
            apiKey: mistralApiKey,
            model: 'mistral-large-latest',
          ),
        );

        await client.pluginManager.registerPlugin(WeatherToolPlugin());

        final response = await client.chat(
          'What is the weather in Paris? Use the get_weather tool.',
          enableTools: false,
          enablePlugins: true,
        );

        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
      }, skip: !hasMistralKey ? 'MISTRAL_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 60)));
    });

    // ==================== GEMINI TESTS ====================
    group('Gemini Provider', () {
      test('basic chat completion', () async {
        final mcpLlm = McpLlm();
        mcpLlm.registerProvider('gemini', GeminiProviderFactory());

        final client = await mcpLlm.createClient(
          providerName: 'gemini',
          config: LlmConfiguration(
            apiKey: geminiApiKey,
            model: 'gemini-1.5-flash-latest',
          ),
        );

        final response = await client.chat('Say "Hello from Gemini!" and nothing else.');
        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
        expect(response.text.toLowerCase(), contains('hello'));
      }, skip: !hasGeminiKey ? 'GEMINI_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('streaming completion', () async {
        final provider = GeminiProvider(
          apiKey: geminiApiKey,
          model: 'gemini-1.5-flash-latest',
          config: LlmConfiguration(apiKey: geminiApiKey),
        );

        final request = LlmRequest(prompt: 'Count from 1 to 5.');

        final chunks = <String>[];
        await for (final chunk in provider.streamComplete(request)) {
          if (chunk.textChunk.isNotEmpty) {
            chunks.add(chunk.textChunk);
          }
        }

        expect(chunks, isNotEmpty);
      }, skip: !hasGeminiKey ? 'GEMINI_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('embeddings', () async {
        final provider = GeminiProvider(
          apiKey: geminiApiKey,
          model: 'gemini-1.5-flash-latest',
          config: LlmConfiguration(apiKey: geminiApiKey),
        );

        final embeddings = await provider.getEmbeddings('Hello, world!');
        expect(embeddings, isNotNull);
        expect(embeddings, isNotEmpty);
        expect(embeddings.length, greaterThan(100));
      }, skip: !hasGeminiKey ? 'GEMINI_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('tool calling', () async {
        final mcpLlm = McpLlm();
        mcpLlm.registerProvider('gemini', GeminiProviderFactory());

        final client = await mcpLlm.createClient(
          providerName: 'gemini',
          config: LlmConfiguration(
            apiKey: geminiApiKey,
            model: 'gemini-1.5-pro-latest',
          ),
        );

        await client.pluginManager.registerPlugin(WeatherToolPlugin());

        final response = await client.chat(
          'What is the weather in Seoul? Use the get_weather tool.',
          enableTools: false,
          enablePlugins: true,
        );

        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
      }, skip: !hasGeminiKey ? 'GEMINI_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 60)));
    });

    // ==================== VERTEX AI TESTS ====================
    group('Vertex AI Provider', () {
      test('basic chat completion', () async {
        final mcpLlm = McpLlm();
        mcpLlm.registerProvider('vertex_ai', VertexAiProviderFactory());

        final client = await mcpLlm.createClient(
          providerName: 'vertex_ai',
          config: LlmConfiguration(
            apiKey: vertexAccessToken,
            model: 'gemini-1.5-flash-001',
            options: {
              'project_id': vertexProjectId,
              'location': 'us-central1',
            },
          ),
        );

        final response = await client.chat('Say "Hello from Vertex AI!" and nothing else.');
        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
        expect(response.text.toLowerCase(), contains('hello'));
      }, skip: !hasVertexCredentials ? 'Vertex AI credentials not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('streaming completion', () async {
        final provider = VertexAiProvider(
          accessToken: vertexAccessToken,
          projectId: vertexProjectId,
          location: 'us-central1',
          model: 'gemini-1.5-flash-001',
          config: LlmConfiguration(apiKey: vertexAccessToken),
        );

        final request = LlmRequest(prompt: 'Count from 1 to 5.');

        final chunks = <String>[];
        await for (final chunk in provider.streamComplete(request)) {
          if (chunk.textChunk.isNotEmpty) {
            chunks.add(chunk.textChunk);
          }
        }

        expect(chunks, isNotEmpty);
      }, skip: !hasVertexCredentials ? 'Vertex AI credentials not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('embeddings', () async {
        final provider = VertexAiProvider(
          accessToken: vertexAccessToken,
          projectId: vertexProjectId,
          location: 'us-central1',
          model: 'gemini-1.5-flash-001',
          config: LlmConfiguration(apiKey: vertexAccessToken),
        );

        final embeddings = await provider.getEmbeddings('Hello, world!');
        expect(embeddings, isNotNull);
        expect(embeddings, isNotEmpty);
      }, skip: !hasVertexCredentials ? 'Vertex AI credentials not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('tool calling', () async {
        final mcpLlm = McpLlm();
        mcpLlm.registerProvider('vertex_ai', VertexAiProviderFactory());

        final client = await mcpLlm.createClient(
          providerName: 'vertex_ai',
          config: LlmConfiguration(
            apiKey: vertexAccessToken,
            model: 'gemini-1.5-pro-001',
            options: {
              'project_id': vertexProjectId,
              'location': 'us-central1',
            },
          ),
        );

        await client.pluginManager.registerPlugin(WeatherToolPlugin());

        final response = await client.chat(
          'What is the weather in London? Use the get_weather tool.',
          enableTools: false,
          enablePlugins: true,
        );

        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
      }, skip: !hasVertexCredentials ? 'Vertex AI credentials not available' : null, timeout: const Timeout(Duration(seconds: 60)));
    });

    // ==================== COHERE TESTS ====================
    group('Cohere Provider', () {
      test('basic chat completion', () async {
        final mcpLlm = McpLlm();
        mcpLlm.registerProvider('cohere', CohereProviderFactory());

        final client = await mcpLlm.createClient(
          providerName: 'cohere',
          config: LlmConfiguration(
            apiKey: cohereApiKey,
            model: 'command-r',
          ),
        );

        final response = await client.chat('Say "Hello from Cohere!" and nothing else.');
        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
        expect(response.text.toLowerCase(), contains('hello'));
      }, skip: !hasCohereKey ? 'COHERE_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('streaming completion', () async {
        final provider = CohereProvider(
          apiKey: cohereApiKey,
          model: 'command-r',
          config: LlmConfiguration(apiKey: cohereApiKey),
        );

        final request = LlmRequest(prompt: 'Count from 1 to 5.');

        final chunks = <String>[];
        await for (final chunk in provider.streamComplete(request)) {
          if (chunk.textChunk.isNotEmpty) {
            chunks.add(chunk.textChunk);
          }
        }

        expect(chunks, isNotEmpty);
      }, skip: !hasCohereKey ? 'COHERE_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('embeddings', () async {
        final provider = CohereProvider(
          apiKey: cohereApiKey,
          model: 'command-r',
          config: LlmConfiguration(apiKey: cohereApiKey),
        );

        final embeddings = await provider.getEmbeddings('Hello, world!');
        expect(embeddings, isNotNull);
        expect(embeddings, isNotEmpty);
        expect(embeddings.length, greaterThan(100));
      }, skip: !hasCohereKey ? 'COHERE_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('tool calling', () async {
        final mcpLlm = McpLlm();
        mcpLlm.registerProvider('cohere', CohereProviderFactory());

        final client = await mcpLlm.createClient(
          providerName: 'cohere',
          config: LlmConfiguration(
            apiKey: cohereApiKey,
            model: 'command-r-plus',
          ),
        );

        await client.pluginManager.registerPlugin(WeatherToolPlugin());

        final response = await client.chat(
          'What is the weather in New York? Use the get_weather tool.',
          enableTools: false,
          enablePlugins: true,
        );

        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
      }, skip: !hasCohereKey ? 'COHERE_API_KEY not available' : null, timeout: const Timeout(Duration(seconds: 60)));
    });

    // ==================== BEDROCK TESTS ====================
    group('Bedrock Provider', () {
      test('basic chat completion with Claude', () async {
        final mcpLlm = McpLlm();
        mcpLlm.registerProvider('bedrock', BedrockProviderFactory());

        final client = await mcpLlm.createClient(
          providerName: 'bedrock',
          config: LlmConfiguration(
            model: 'anthropic.claude-3-haiku-20240307-v1:0',
            options: {
              'access_key_id': awsAccessKeyId,
              'secret_access_key': awsSecretAccessKey,
              'region': awsRegion,
            },
          ),
        );

        final response = await client.chat('Say "Hello from Bedrock!" and nothing else.');
        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
        expect(response.text.toLowerCase(), contains('hello'));
      }, skip: !hasAwsCredentials ? 'AWS credentials not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('streaming completion with Claude', () async {
        final provider = BedrockProvider(
          accessKeyId: awsAccessKeyId,
          secretAccessKey: awsSecretAccessKey,
          region: awsRegion,
          model: 'anthropic.claude-3-haiku-20240307-v1:0',
          config: LlmConfiguration(),
        );

        final request = LlmRequest(prompt: 'Count from 1 to 5.');

        final chunks = <String>[];
        await for (final chunk in provider.streamComplete(request)) {
          if (chunk.textChunk.isNotEmpty) {
            chunks.add(chunk.textChunk);
          }
        }

        expect(chunks, isNotEmpty);
      }, skip: !hasAwsCredentials ? 'AWS credentials not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('embeddings with Titan', () async {
        final provider = BedrockProvider(
          accessKeyId: awsAccessKeyId,
          secretAccessKey: awsSecretAccessKey,
          region: awsRegion,
          model: 'anthropic.claude-3-haiku-20240307-v1:0',
          config: LlmConfiguration(),
        );

        final embeddings = await provider.getEmbeddings('Hello, world!');
        expect(embeddings, isNotNull);
        expect(embeddings, isNotEmpty);
      }, skip: !hasAwsCredentials ? 'AWS credentials not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('basic chat completion with Llama', () async {
        final provider = BedrockProvider(
          accessKeyId: awsAccessKeyId,
          secretAccessKey: awsSecretAccessKey,
          region: awsRegion,
          model: 'meta.llama3-8b-instruct-v1:0',
          config: LlmConfiguration(),
        );

        final request = LlmRequest(prompt: 'Say "Hello from Llama!" and nothing else.');

        final response = await provider.complete(request);
        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
      }, skip: !hasAwsCredentials ? 'AWS credentials not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('basic chat completion with Mistral on Bedrock', () async {
        final provider = BedrockProvider(
          accessKeyId: awsAccessKeyId,
          secretAccessKey: awsSecretAccessKey,
          region: awsRegion,
          model: 'mistral.mistral-7b-instruct-v0:2',
          config: LlmConfiguration(),
        );

        final request = LlmRequest(prompt: 'Say "Hello from Mistral!" and nothing else.');

        final response = await provider.complete(request);
        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
      }, skip: !hasAwsCredentials ? 'AWS credentials not available' : null, timeout: const Timeout(Duration(seconds: 30)));

      test('tool calling with Claude on Bedrock', () async {
        final mcpLlm = McpLlm();
        mcpLlm.registerProvider('bedrock', BedrockProviderFactory());

        final client = await mcpLlm.createClient(
          providerName: 'bedrock',
          config: LlmConfiguration(
            model: 'anthropic.claude-3-sonnet-20240229-v1:0',
            options: {
              'access_key_id': awsAccessKeyId,
              'secret_access_key': awsSecretAccessKey,
              'region': awsRegion,
            },
          ),
        );

        await client.pluginManager.registerPlugin(WeatherToolPlugin());

        final response = await client.chat(
          'What is the weather in Berlin? Use the get_weather tool.',
          enableTools: false,
          enablePlugins: true,
        );

        expect(response, isNotNull);
        expect(response.text, isNotEmpty);
      }, skip: !hasAwsCredentials ? 'AWS credentials not available' : null, timeout: const Timeout(Duration(seconds: 60)));
    });

    // ==================== CROSS-PROVIDER TESTS ====================
    group('Cross-Provider Tests', () {
      test('same prompt across multiple providers', () async {
        final results = <String, String>{};
        const prompt = 'What is 2 + 2? Answer with just the number.';

        if (hasGroqKey) {
          try {
            final provider = GroqProvider(
              apiKey: groqApiKey,
              model: 'llama-3.1-8b-instant',
              config: LlmConfiguration(apiKey: groqApiKey),
            );
            final response = await provider.complete(LlmRequest(prompt: prompt));
            results['groq'] = response.text;
          } catch (e) {
            results['groq'] = 'Error: $e';
          }
        }

        if (hasMistralKey) {
          try {
            final provider = MistralProvider(
              apiKey: mistralApiKey,
              model: 'mistral-small-latest',
              config: LlmConfiguration(apiKey: mistralApiKey),
            );
            final response = await provider.complete(LlmRequest(prompt: prompt));
            results['mistral'] = response.text;
          } catch (e) {
            results['mistral'] = 'Error: $e';
          }
        }

        if (hasGeminiKey) {
          try {
            final provider = GeminiProvider(
              apiKey: geminiApiKey,
              model: 'gemini-1.5-flash-latest',
              config: LlmConfiguration(apiKey: geminiApiKey),
            );
            final response = await provider.complete(LlmRequest(prompt: prompt));
            results['gemini'] = response.text;
          } catch (e) {
            results['gemini'] = 'Error: $e';
          }
        }

        if (hasCohereKey) {
          try {
            final provider = CohereProvider(
              apiKey: cohereApiKey,
              model: 'command-r',
              config: LlmConfiguration(apiKey: cohereApiKey),
            );
            final response = await provider.complete(LlmRequest(prompt: prompt));
            results['cohere'] = response.text;
          } catch (e) {
            results['cohere'] = 'Error: $e';
          }
        }

        expect(results, isNotEmpty);

        for (final entry in results.entries) {
          expect(entry.value.contains('4'), isTrue,
              reason: '${entry.key} should return 4 for 2+2');
        }
      }, skip: !hasAnyKey ? 'No API keys available' : null, timeout: const Timeout(Duration(seconds: 60)));

      test('embedding dimension comparison', () async {
        final dimensions = <String, int>{};

        if (hasMistralKey) {
          try {
            final provider = MistralProvider(
              apiKey: mistralApiKey,
              model: 'mistral-small-latest',
              config: LlmConfiguration(apiKey: mistralApiKey),
            );
            final embeddings = await provider.getEmbeddings('test');
            dimensions['mistral'] = embeddings.length;
          } catch (_) {}
        }

        if (hasGeminiKey) {
          try {
            final provider = GeminiProvider(
              apiKey: geminiApiKey,
              model: 'gemini-1.5-flash-latest',
              config: LlmConfiguration(apiKey: geminiApiKey),
            );
            final embeddings = await provider.getEmbeddings('test');
            dimensions['gemini'] = embeddings.length;
          } catch (_) {}
        }

        if (hasCohereKey) {
          try {
            final provider = CohereProvider(
              apiKey: cohereApiKey,
              model: 'command-r',
              config: LlmConfiguration(apiKey: cohereApiKey),
            );
            final embeddings = await provider.getEmbeddings('test');
            dimensions['cohere'] = embeddings.length;
          } catch (_) {}
        }

        expect(dimensions, isNotEmpty);

        for (final entry in dimensions.entries) {
          expect(entry.value, greaterThan(100),
              reason: '${entry.key} should have >100 dimensions');
        }
      }, skip: !(hasMistralKey || hasGeminiKey || hasCohereKey) ? 'No embedding API keys available' : null, timeout: const Timeout(Duration(seconds: 60)));
    });
  });
}
