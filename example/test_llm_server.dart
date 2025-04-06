// test_llm_server.dart
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:mcp_llm/mcp_llm.dart' hide LogLevel, Logger;
import 'package:mcp_server/mcp_server.dart';

final Logger _logger = Logger.getLogger('test_llm_server');

// Global variables
late IOSink logSink;
late File detailedLogFile;

void main(List<String> arguments) async {
  // Parse command line arguments
  final int port = int.tryParse(getArgValue(arguments, '--port') ?? '8999') ?? 8999;
  final String authToken = getArgValue(arguments, '--auth-token') ?? 'test_token';
  final String llmProvider = getArgValue(arguments, '--llm-provider') ?? 'echo';
  final double? temperature = double.tryParse(getArgValue(arguments, '--temperature') ?? '0.7');
  final int? maxTokens = int.tryParse(getArgValue(arguments, '--max-tokens') ?? '2000');

  // Setup logging
  setupLogging();

  logInfo("=== LLM Server Test Starting ===");
  logInfo("Time: ${DateTime.now().toIso8601String()}");
  logInfo("Port: $port");
  logInfo("Auth Token: $authToken");
  logInfo("LLM Provider: $llmProvider");
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
    // Start LLM server
    logInfo("Starting LLM server...");
    final llmServer = await startLlmServer(
      port: port,
      authToken: authToken,
      llmConfig: llmConfig,
    );

    logInfo("Server started successfully!");
    logInfo("Press Ctrl+C to stop the server...");

    // Keep the server running until interrupted
    final completer = Completer<void>();
    ProcessSignal.sigint.watch().listen((_) {
      logInfo("\nReceived interrupt signal. Shutting down server...");
      completer.complete();
    });

    await completer.future;
    logInfo("Server shutdown initiated...");

  } catch (e, stackTrace) {
    logError("Error during LLM server test", e, stackTrace);
  } finally {
    await logSink.flush();
    await logSink.close();
  }
}

/// Start and run the LLM server
Future<LlmServer> startLlmServer({
  required int port,
  required String authToken,
  required LlmConfiguration llmConfig,
}) async {
  logInfo("Setting up LLM server (port: $port, authentication: enabled)");

  // Create MCP server
  final server = McpServer.createServer(
    name: 'LLM-SSE-Auth Test Server',
    version: '1.0.0',
    capabilities: ServerCapabilities(
      tools: true,
      toolsListChanged: true,
      resources: true,
      resourcesListChanged: true,
      prompts: true,
      promptsListChanged: true,
      sampling: true,
    ),
  );

  // Create MCP LLM instance
  final mcpLlm = McpLlm();

  // Register LLM providers
  registerLlmProviders(mcpLlm);

  // Create and configure LLM server
  logInfo("Creating LLM server (model: ${llmConfig.model})");
  final llmServer = await mcpLlm.createServer(
    providerName: llmConfig.model ?? 'echo',
    config: llmConfig,
    mcpServer: server,
    storageManager: MemoryStorage(),
  );

  // Register LLM tools
  await llmServer.registerLlmTools();

  // Register additional server resources and tools
  registerServerTools(server);
  registerServerResources(server);
  registerServerPrompts(server, llmConfig);

  // Create SSE transport with authentication token
  logInfo("Setting up SSE transport (authentication enabled)");
  final transport = McpServer.createSseTransport(
    endpoint: '/sse',
    messagesEndpoint: '/message',
    port: port,
    fallbackPorts: [port + 1, port + 2], // Fallback ports if primary is unavailable
    authToken: authToken,
  );

  // Server-transport connection
  server.connect(transport);

  // Send initial log message
  server.sendLog(McpLogLevel.info, 'LLM-SSE-Auth Test Server started successfully');

  // Log server running information
  logInfo("SSE server running at:");
  logInfo("- SSE endpoint:     http://localhost:$port/sse");
  logInfo("- Message endpoint: http://localhost:$port/message");
  logInfo("- Auth token: $authToken");

  // Log detailed server info
  final serverInfo = {
    'name': server.name,
    'version': server.version,
    'capabilities': server.capabilities.toJson(),
    'llmModel': llmConfig.model,
    'llmOptions': llmConfig.options,
  };

  logInfo("Server info: ${jsonEncode(serverInfo)}");
  return llmServer;
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

/// Register server tools
void registerServerTools(Server server) {
  // Echo tool
  server.addTool(
    name: 'echo',
    description: 'Returns input with optional transformations',
    inputSchema: {
      'type': 'object',
      'properties': {
        'message': {
          'type': 'string',
          'description': 'Message to return'
        },
        'uppercase': {
          'type': 'boolean',
          'description': 'Whether to convert to uppercase',
          'default': false
        },
        'repeat': {
          'type': 'integer',
          'description': 'Number of times to repeat the message',
          'default': 1
        }
      },
      'required': ['message']
    },
    handler: (args) async {
      final message = args['message'] as String;
      final uppercase = args['uppercase'] as bool? ?? false;
      final repeat = args['repeat'] as int? ?? 1;

      String result = uppercase ? message.toUpperCase() : message;
      if (repeat > 1) {
        result = List.filled(repeat, result).join(' ');
      }

      logInfo("Echo tool called: $message (uppercase: $uppercase, repeat: $repeat)");
      return CallToolResult([TextContent(text: result)]);
    },
  );

  // Server info tool
// Add a tool to retrieve comprehensive server information
  server.addTool(
    name: 'server-info',
    description: 'Get comprehensive server information',
    inputSchema: {
      'type': 'object',
      'properties': {
        'detailLevel': {
          'type': 'string',
          'description': 'Level of detail (basic, full)',
          'enum': ['basic', 'full'],
          'default': 'basic'
        }
      }
    },
    handler: (args) async {
      final detailLevel = args['detailLevel'] as String? ?? 'basic';

      // Retrieve server health
      final serverHealth = server.getHealth();

      // Prepare server information
      final serverInfo = {
        'running': serverHealth.isRunning,
        'connectedSessions': serverHealth.connectedSessions,
        'registeredTools': serverHealth.registeredTools,
        'registeredResources': serverHealth.registeredResources,
        'registeredPrompts': serverHealth.registeredPrompts,
        'startTime': serverHealth.startTime.toIso8601String(),
        'uptimeSeconds': serverHealth.uptime.inSeconds,
      };

      // Add additional details for full information
      if (detailLevel == 'full') {
        serverInfo.addAll({
          'metrics': serverHealth.metrics,
        });
      }

      return CallToolResult([
        TextContent(text: jsonEncode(serverInfo))
      ]);
    },
  );

  logInfo("Server tools registered: echo, server-info");
}

/// Register server resources
void registerServerResources(Server server) {
  // Sample test resource
  server.addResource(
      uri: 'test://sample',
      name: 'Sample Test Resource',
      description: 'Sample resource for testing',
      mimeType: 'text/plain',
      handler: (uri, params) async {
        logInfo("Resource accessed: test://sample");
        return ReadResourceResult(
          content: 'This is sample resource content for testing purposes.',
          mimeType: 'text/plain',
          contents: [
            ResourceContent(
              uri: 'test://sample',
              text: 'This is sample resource content for testing purposes.',
            )
          ],
        );
      }
  );

  // JSON data resource
  server.addResource(
      uri: 'test://data',
      name: 'Test JSON Data',
      description: 'JSON data resource for testing',
      mimeType: 'application/json',
      handler: (uri, params) async {
        final data = {
          'items': [
            {'id': 1, 'name': 'Item 1', 'value': 10.5},
            {'id': 2, 'name': 'Item 2', 'value': 20.3},
            {'id': 3, 'name': 'Item 3', 'value': 15.7},
          ],
          'metadata': {
            'count': 3,
            'createdAt': DateTime.now().toIso8601String(),
          }
        };

        logInfo("Resource accessed: test://data");
        return ReadResourceResult(
          content: jsonEncode(data),
          mimeType: 'application/json',
          contents: [
            ResourceContent(
              uri: 'test://data',
              text: jsonEncode(data),
            )
          ],
        );
      }
  );

  logInfo("Server resources registered: test://sample, test://data");
}

/// Register server prompts
void registerServerPrompts(Server server, LlmConfiguration llmConfig) {
  // Greeting prompt
  server.addPrompt(
    name: 'greeting',
    description: 'Generate a greeting for a user',
    arguments: [
      PromptArgument(
        name: 'name',
        description: 'Name of the person to greet',
        required: true,
      ),
      PromptArgument(
        name: 'formal',
        description: 'Whether to use formal greeting style',
        required: false,
      ),
    ],
    handler: (args) async {
      final name = args['name'] as String;
      final formal = args['formal'] as bool? ?? false;

      final String systemPrompt = formal
          ? 'You are a formal assistant. Treat the user with respect and formality.'
          : 'You are a friendly assistant. Speak in a warm and casual tone.';

      final messages = [
        Message(
          role: 'system',
          content: TextContent(text: systemPrompt),
        ),
        Message(
          role: 'user',
          content: TextContent(text: 'Greet ${name} please.'),
        ),
      ];

      logInfo("Greeting prompt generated: name=$name, formal=$formal");
      return GetPromptResult(
        description: '${formal ? 'Formal' : 'Friendly'} greeting for $name',
        messages: messages,
      );
    },
  );

  logInfo("Server prompts registered: greeting");
}

/// Enhanced mock LLM provider factory
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

/// Enhanced mock LLM provider (with detailed logging)
class MockLlmProvider implements LlmInterface {
  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    // Simulate processing delay
    await Future.delayed(Duration(milliseconds: 300));

    // Simple echo response
    final response = "Echo response: ${request.prompt}";

    // Add metadata
    final metadata = {
      'model': 'mock-echo-model',
      'processingTime': '300ms',
    };

    logInfo("LLM response generated: ${response.substring(0, min(50, response.length))}...");
    return LlmResponse(
      text: response,
      metadata: metadata,
    );
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    // Streaming simulation
    final words = "Echo streaming response: ${request.prompt}".split(' ');

    for (int i = 0; i < words.length; i++) {
      // Simulate per-word delay
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

  // Min helper function
  int min(int a, int b) => a < b ? a : b;
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
  detailedLogFile = File('llm_server_$timestamp.log');
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