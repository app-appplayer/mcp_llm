// test_llm_client.dart
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:mcp_llm/mcp_llm.dart' hide LogLevel, Logger;
import 'package:mcp_client/mcp_client.dart';

final Logger _logger = Logger.getLogger('test_llm_client');

// Global variables
late IOSink logSink;
late File detailedLogFile;

void main(List<String> arguments) async {
  Logger.getLogger('mcp_llm.client').setLevel(LogLevel.debug);
  // Parse command line arguments
  final int port = int.tryParse(getArgValue(arguments, '--port') ?? '8999') ?? 8999;
  final String authToken = getArgValue(arguments, '--auth-token') ?? 'test_token';
  final String llmProvider = getArgValue(arguments, '--llm-provider') ?? 'echo';
  final double? temperature = double.tryParse(getArgValue(arguments, '--temperature') ?? '0.7');
  final int? maxTokens = int.tryParse(getArgValue(arguments, '--max-tokens') ?? '2000');
  final int maxRetries = int.tryParse(getArgValue(arguments, '--max-retries') ?? '5') ?? 5;

  // Setup logging
  setupLogging();

  logInfo("=== LLM Client Test Starting ===");
  logInfo("Time: ${DateTime.now().toIso8601String()}");
  logInfo("Port: $port");
  logInfo("Auth Token: $authToken");
  logInfo("LLM Provider: $llmProvider");
  logInfo("Max Retries: $maxRetries");
  if (temperature != null) logInfo("Temperature: $temperature");
  if (maxTokens != null) logInfo("Max Tokens: $maxTokens");

  // LLM configuration
  final llmConfig = LlmConfiguration(
    apiKey: "test_api_key",
    model: llmProvider,
    options: {
      'temperature': temperature,
      'maxTokens': maxTokens,
    },
  );

  try {
    await startLlmClient(
      port: port,
      authToken: authToken,
      llmConfig: llmConfig,
      maxRetries: maxRetries,
    );
    logInfo("=== LLM Client Test Completed ===");
  } catch (e, stackTrace) {
    logError("Error during LLM client test", e, stackTrace);
  } finally {
    await logSink.flush();
    await logSink.close();
  }
}

/// Start and run the LLM client
Future<void> startLlmClient({
  required int port,
  required String authToken,
  required LlmConfiguration llmConfig,
  required int maxRetries,
}) async {
  logInfo("Setting up LLM client (server port: $port)");

  // Create MCP client
  final client = McpClient.createClient(
    name: 'LLM-SSE-Auth Test Client',
    version: '1.0.0',
    capabilities: ClientCapabilities(
      roots: true,
      rootsListChanged: true,
      sampling: true,
    ),
  );

  // Create MCP LLM instance
  final mcpLlm = McpLlm();

  // Register LLM providers
  registerLlmProviders(mcpLlm);

  // Set up SSE transport with auth token
  logInfo("Setting up client SSE transport (using auth token)");
  logInfo("Connection URL: http://localhost:$port/sse");
  final headers = {'Authorization': 'Bearer $authToken'};
  logInfo("Headers: $headers");

  final transport = await McpClient.createSseTransport(
    serverUrl: 'http://localhost:$port/sse',
    headers: headers,
  );

  // Wait a bit before connecting
  logInfo("Transport created, waiting before connection...");
  await Future.delayed(Duration(seconds: 1));

  // Create LLM client
  final llmClient = await mcpLlm.createClient(
    providerName: llmConfig.model ?? 'echo',
    config: llmConfig,
    mcpClient: client,
    storageManager: MemoryStorage(),
  );

  // Create second client for multi-client management
  final llmClient2 = await mcpLlm.createClient(
    providerName: llmConfig.model ?? 'echo',
    clientId: 'client2',
    config: llmConfig,
    routingProperties: {
      'specialties': ['coding', 'technical'],
      'keywords': ['code', 'program', 'develop', 'algorithm'],
    },
  );

  try {
    // Register notification handlers
    registerClientHandlers(client);

    // Connect to server
    logInfo("Connecting to MCP server (max retries: $maxRetries)...");

    // Connect with longer delay between retries
    await client.connectWithRetry(
        transport,
        maxRetries: maxRetries,
        delay: Duration(seconds: 2)
    );

    logInfo("Successfully connected to server!");

    // Wait for initialization to complete
    await Future.delayed(Duration(milliseconds: 500));

    // Run test cases
    await runClientTests(client, llmClient, llmClient2, mcpLlm);

  } catch (e, stackTrace) {
    logError("Error during client test", e, stackTrace);

    // Diagnostic information
    logInfo("Connection failure diagnostics...");
    try {
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse('http://localhost:$port/health'));
      headers.forEach((key, value) {
        request.headers.add(key, value);
      });

      final response = await request.close();
      logInfo("Server health check response: ${response.statusCode}");
    } catch (e) {
      logInfo("Server health check failed: $e");
    }

    rethrow;
  } finally {
    // Close connection
    logInfo("Closing client connection...");
    client.disconnect();
    logInfo("Connection closed!");

    // Shutdown MCP LLM
    await mcpLlm.shutdown();
  }
}

/// Register client event handlers
void registerClientHandlers(Client client) {
  // Tools list changed notification
  client.onToolsListChanged(() {
    logInfo("Notification: Tools list changed");
  });

  // Resources list changed notification
  client.onResourcesListChanged(() {
    logInfo("Notification: Resources list changed");
  });

  // Prompts list changed notification
  client.onPromptsListChanged(() {
    logInfo("Notification: Prompts list changed");
  });

  // Server log reception
  client.onLogging((level, message, logger, data) {
    logInfo("Server log [${level.name}]: $message");
  });
}

/// Register LLM providers
void registerLlmProviders(McpLlm mcpLlm) {
  // Register mock Echo provider (for testing)
  mcpLlm.registerProvider('echo', MockProviderFactory());

  // Register real providers
  // Note: API keys needed for actual use
  try {
    mcpLlm.registerProvider('claude', ClaudeProviderFactory());
    logInfo("Claude provider registered");
  } catch (e) {
    logInfo("Claude provider registration failed: $e");
  }

  try {
    mcpLlm.registerProvider('openai', OpenAiProviderFactory());
    logInfo("OpenAI provider registered");
  } catch (e) {
    logInfo("OpenAI provider registration failed: $e");
  }
}

/// Run client tests
Future<void> runClientTests(Client client, LlmClient llmClient, LlmClient llmClient2, McpLlm mcpLlm) async {
  // Test case 1: List available tools
  logInfo("\n--- Test 1: List Available Tools ---");
  final tools = await client.listTools();
  if (tools.isEmpty) {
    logInfo("No tools available");
  } else {
    for (final tool in tools) {
      logInfo("Tool: ${tool.name} - ${tool.description}");
    }
  }

  // Test case 2: List available resources
  logInfo("\n--- Test 2: List Available Resources ---");
  final resources = await client.listResources();
  if (resources.isEmpty) {
    logInfo("No resources available");
  } else {
    for (final resource in resources) {
      logInfo("Resource: ${resource.name} (${resource.uri})");
    }
  }

  // Test case 3: LLM completion
  logInfo("\n--- Test 3: LLM Completion ---");
  try {
    final response = await llmClient.chat(
      "Hello! Who are you?",
      enableTools: true,
    );

    logInfo("LLM Response: ${response.text}");
    logInfo("Metadata: ${response.metadata}");
  } catch (e) {
    logInfo("LLM completion error: $e");
  }

  // Test case 4: Echo tool call
  logInfo("\n--- Test 4: Echo Tool Call ---");
  if (tools.any((tool) => tool.name == 'echo')) {
    try {
      // Basic echo test
      var result = await client.callTool('echo', {'message': 'Hello, MCP!'});
      logInfo("Echo tool result (basic): ${formatContent(result.content)}");

      // Uppercase transformation test
      result = await client.callTool('echo', {'message': 'Hello, MCP!', 'uppercase': true});
      logInfo("Echo tool result (uppercase): ${formatContent(result.content)}");
    } catch (e) {
      logInfo("Echo tool call error: $e");
    }
  } else {
    logInfo("Echo tool not found");
  }

  // Test case 5: Resource reading
  logInfo("\n--- Test 5: Resource Reading ---");
  if (resources.any((resource) => resource.uri == 'test://sample')) {
    try {
      final resourceResult = await client.readResource('test://sample');

      if (resourceResult.contents.isNotEmpty) {
        final contentInfo = resourceResult.contents.map((content) =>
        content.text ?? content.uri).join(", ");
        logInfo("Resource content: $contentInfo");
      } else {
        logInfo("No content returned from resource");
      }
    } catch (e) {
      logInfo("Resource reading error: $e");
    }
  } else {
    logInfo("test://sample resource not found");
  }

  // Test case 6: Prompt test
  logInfo("\n--- Test 6: Prompt Template Test ---");
  try {
    final prompts = await client.listPrompts();
    logInfo("Available prompts: ${prompts.map((p) => p.name).join(', ')}");

    if (prompts.any((prompt) => prompt.name == 'greeting')) {
      final promptResult = await client.getPrompt('greeting', {'name': 'Tester', 'formal': true});

      logInfo("Prompt description: ${promptResult.description}");
      logInfo("Prompt messages:");

      for (final message in promptResult.messages) {
        logInfo("- ${message.role}: ${message.content is TextContent ? (message.content as TextContent).text : jsonEncode(message.content)}");
      }
    }
  } catch (e) {
    logInfo("Prompt test error: $e");
  }

  // Test case 7: Multi-client management
  logInfo("\n--- Test 7: Multi-Client Management ---");
  try {
    // Client routing test
    final selectedClient = mcpLlm.selectClient("Write a function to calculate Fibonacci sequence in JavaScript.");
    logInfo("Selected client for coding query: ${selectedClient == llmClient2 ? 'client2' : 'client1'}");

    // Fan-out query test
    final fanOutResults = await mcpLlm.fanOutQuery("What time is it now?");
    logInfo("Fan-out query sent to ${fanOutResults.length} clients");
  } catch (e) {
    logInfo("Multi-client test error: $e");
  }

  // Test case 8: Server status
  logInfo("\n--- Test 8: Server Status Test ---");
  try {
    final health = await client.healthCheck();
    logInfo("Server status:");
    logInfo("- Running: ${health.isRunning}");
    logInfo("- Connected sessions: ${health.connectedSessions}");
    logInfo("- Registered tools: ${health.registeredTools}");
    logInfo("- Registered resources: ${health.registeredResources}");
    logInfo("- Registered prompts: ${health.registeredPrompts}");
    logInfo("- Uptime: ${health.uptime.inSeconds} seconds");
  } catch (e) {
    logInfo("Server status check error: $e");
  }

  // Test summary
  logInfo("\n=== Client Test Summary ===");
  logInfo("8 test cases completed");
  logInfo("Client test completed successfully!");
}

/// Content formatting helper function
String formatContent(List<Content> contents) {
  if (contents.isEmpty) return "No content";

  return contents.map((content) {
    if (content is TextContent) {
      return content.text;
    } else {
      return content.toString();
    }
  }).join(", ");
}

/// Mock LLM provider factory
class MockProviderFactory implements LlmProviderFactory {
  @override
  String get name => 'echo';

  @override
  Set<LlmCapability> get capabilities => {
    LlmCapability.completion,
    LlmCapability.streaming,
    LlmCapability.toolUse,
  };

  @override
  LlmInterface createProvider(LlmConfiguration config) {
    return MockLlmProvider();
  }
}

/// Mock LLM provider
class MockLlmProvider implements LlmInterface {
  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    // Simulate processing delay
    await Future.delayed(Duration(milliseconds: 300));

    // Simple echo response
    return LlmResponse(
      text: "Echo response: ${request.prompt}",
      metadata: {
        'model': 'mock-echo-model',
        'processingTime': '300ms',
      },
    );
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    // Split response into chunks
    final words = "Echo streaming response: ${request.prompt}".split(' ');

    for (int i = 0; i < words.length; i++) {
      // Simulate streaming delay
      await Future.delayed(Duration(milliseconds: 50));

      yield LlmResponseChunk(
        textChunk: "${words[i]}${i < words.length - 1 ? ' ' : ''}",
        isDone: i == words.length - 1,
        metadata: {'chunk': i + 1, 'totalChunks': words.length},
      );
    }
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    // Simple mock embedding (10-dimensional)
    return List.generate(10, (index) => index / 10.0);
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {
    // Simulate initialization
    await Future.delayed(Duration(milliseconds: 200));
  }

  @override
  Future<void> close() async {
    // Simulate cleanup
    await Future.delayed(Duration(milliseconds: 100));
  }
}

/// Argument value extraction helper function
String? getArgValue(List<String> args, String argName) {
  for (int i = 0; i < args.length - 1; i++) {
    if (args[i] == argName) {
      return args[i + 1];
    }
  }
  return null;
}

/// Logging setup
void setupLogging() {
  // Basic logging configuration
  _logger.configure(level: LogLevel.debug, includeTimestamp: true, useColor: true);

  // Detailed log file creation
  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  detailedLogFile = File('llm_client_$timestamp.log');
  logSink = detailedLogFile.openWrite(mode: FileMode.append);

  logInfo("Log file created: ${detailedLogFile.path}");
}

/// Info logging function
void logInfo(String message) {
  // Log to console
  _logger.info(message);

  // Log to file
  final timestamp = DateTime.now().toIso8601String();
  logSink.writeln("$timestamp INFO: $message");
}

/// Debug logging function
void logDebug(String message) {
  // Log to console
  _logger.debug(message);

  // Log to file
  final timestamp = DateTime.now().toIso8601String();
  logSink.writeln("$timestamp DEBUG: $message");
}

/// Error logging function
void logError(String message, [Object? error, StackTrace? stackTrace]) {
  // Log to console
  _logger.error(message);

  // Log to file
  final timestamp = DateTime.now().toIso8601String();
  logSink.writeln("$timestamp ERROR: $message");

  if (error != null) {
    logSink.writeln("$timestamp ERROR DETAIL: $error");
  }

  if (stackTrace != null) {
    logSink.writeln("$timestamp STACK TRACE: $stackTrace");
  }
}