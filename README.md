# MCP Llm

[![Support on Patreon](https://img.shields.io/badge/Support%20on-Patreon-orange?logo=patreon)](https://www.patreon.com/mcpdevstudio)

---

A Dart plugin for integrating Large Language Models (LLMs) with [Model Context Protocol (MCP)](https://modelcontextprotocol.io/). This plugin provides tools for LLM communication, multi-client support, parallel processing, and Retrieval Augmented Generation (RAG) capabilities.

## Features

- **Multiple LLM provider support**:
  - Abstract interface for different LLM providers
  - Support for Claude, OpenAI, Together AI, and more
  - Runtime provider selection and switching
  - Parallel inference across multiple providers

- **Multi-client support**:
  - Manage multiple MCP clients
  - Query-based routing and load balancing
  - Fan-out queries across clients

- **Plugin system**:
  - Custom tool plugins
  - Custom prompt templates
  - Embeddings plugins

- **RAG capabilities**:
  - Document store with vector search
  - Embedding management
  - Retrieval and reranking

- **Advanced features**:
  - Task scheduling with priorities
  - Client connection pooling
  - Performance monitoring

## Getting Started

### Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  mcp_llm: ^0.2.2
```

Or install via command line:

```bash
dart pub add mcp_llm
```

### Basic Usage

```dart
import 'package:mcp_llm/mcp_llm.dart';

void main() async {
  // Logging
  final logger = Logger.getLogger('mcp_llm.main');

  // Create a new McpLlm instance
  final mcpLlm = McpLlm();

  // Register provider
  mcpLlm.registerProvider('claude', ClaudeProviderFactory());

  // Create a client with Claude provider
  final client = await mcpLlm.createClient(
    providerName: 'claude',
    config: LlmConfiguration(
      apiKey: 'your-claude-api-key',
      model: 'claude-3-5-sonnet',
    ),
  );

  // Send a chat message
  final response = await client.chat(
    "What's the weather in New York?",
    enableTools: true,
  );

  logger.info(response.text);

  // Clean up
  await mcpLlm.shutdown();
}
```

## Core Concepts

### LLM Providers

The library supports multiple LLM providers through the provider factory system:

```dart
// Register providers
mcpLlm.registerProvider('openai', OpenAiProviderFactory());
mcpLlm.registerProvider('claude', ClaudeProviderFactory());
mcpLlm.registerProvider('together', TogetherProviderFactory());

// Configure provider
final config = LlmConfiguration(
  apiKey: 'your-api-key',
  model: 'claude-3-5-sonnet',
  options: {
    'temperature': 0.7,
    'maxTokens': 1500,
  },
);

// Create a client with the provider
final client = await mcpLlm.createClient(
  providerName: 'claude',
  config: config,
);

// Send query
final response = await client.chat("What's the meaning of life?");
logger.info(response.text);
```

### Multi-Client Management

The library supports managing multiple LLM clients with intelligent routing:

```dart
// Create clients with different specialties
await mcpLlm.createClient(
  providerName: 'claude',
  clientId: 'writing',
  routingProperties: {
    'specialties': ['writing', 'creativity'],
    'keywords': ['write', 'create', 'generate'],
  },
);

await mcpLlm.createClient(
  providerName: 'openai',
  clientId: 'coding',
  routingProperties: {
    'specialties': ['coding', 'technical'],
    'keywords': ['code', 'program', 'function'],
  },
);

// The system automatically routes to appropriate client
final client = mcpLlm.selectClient("Write a short story about robots");
final response = await client.chat("Write a short story about robots");
```

### Parallel Processing

Execute requests across multiple LLM providers and aggregate results:

```dart
final response = await mcpLlm.executeParallel(
  "Suggest five names for a tech startup focused on sustainability",
  providerNames: ['claude', 'openai', 'together'],
  aggregator: ResultAggregator(),
);
```

### RAG (Retrieval Augmented Generation)

Integrate document retrieval with LLM generation:

```dart
// Create document store
final storageManager = MemoryStorage();
final documentStore = DocumentStore(storageManager);

// Create retrieval manager
final retrievalManager = mcpLlm.createRetrievalManager(
  providerName: 'openai',
  documentStore: documentStore,
);

// Add documents
await retrievalManager.addDocument(Document(
  title: 'Climate Change Overview',
  content: 'Climate change refers to...',
));

// Create client with retrieval manager
final client = await mcpLlm.createClient(
  providerName: 'openai',
  retrievalManager: retrievalManager,
);

// Perform RAG query
final answer = await client.retrieveAndGenerate(
  "What are the main causes of climate change?",
  topK: 3,
);
```

## Logging

The package includes a built-in logging utility:

```dart
// Get logger
final logger = Logger.getLogger('mcp_llm.test');

// Set log level
logger.setLevel(LogLevel.debug);

// Log messages at different levels
logger.debug('Debugging information');
logger.info('Important information');
logger.warning('Warning message');
logger.error('Error message');
```

## Examples

Check out the [example](https://github.com/app-appplayer/mcp_llm/tree/main/example) directory for complete sample applications.

## Additional Features

### Plugin System

MCP LLM provides a flexible plugin system to extend functionality. The most common type of plugin is a tool plugin, which allows the LLM to perform actions.

#### Plugin Architecture

The plugin system is based on these key components:

- `LlmPlugin`: Base interface for all plugins
- `BaseToolPlugin`: Base class for implementing tool plugins
- `PluginManager`: Manages registration and execution of plugins

#### Creating Tool Plugins

Tool plugins extend the `BaseToolPlugin` class and implement the `onExecute` method:

```dart
import 'package:mcp_llm/mcp_llm.dart';

class EchoToolPlugin extends BaseToolPlugin {
  EchoToolPlugin() : super(
    name: 'echo',              // Tool name
    version: '1.0.0',          // Tool version 
    description: 'Echoes back the input message with optional transformation',
    inputSchema: {             // JSON Schema for input validation
      'type': 'object',
      'properties': {
        'message': {
          'type': 'string',
          'description': 'Message to echo back'
        },
        'uppercase': {
          'type': 'boolean',
          'description': 'Whether to convert to uppercase',
          'default': false
        }
      },
      'required': ['message']  // Required parameters
    },
  );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> arguments) async {
    final message = arguments['message'] as String;
    final uppercase = arguments['uppercase'] as bool? ?? false;

    final result = uppercase ? message.toUpperCase() : message;

    Logger.getLogger('LlmServerDemo').debug(message);
    return LlmCallToolResult([
      LlmTextContent(text: result),
    ]);
  }
}
```

#### Example Calculator Plugin

```dart
class CalculatorToolPlugin extends BaseToolPlugin {
  CalculatorToolPlugin() : super(
    name: 'calculator',
    version: '1.0.0',
    description: 'Performs basic arithmetic operations',
    inputSchema: {
      'type': 'object',
      'properties': {
        'operation': {
          'type': 'string',
          'description': 'The operation to perform (add, subtract, multiply, divide)',
          'enum': ['add', 'subtract', 'multiply', 'divide']
        },
        'a': {
          'type': 'number',
          'description': 'First number'
        },
        'b': {
          'type': 'number',
          'description': 'Second number'
        }
      },
      'required': ['operation', 'a', 'b']
    },
  );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> arguments) async {
    final operation = arguments['operation'] as String;
    final a = (arguments['a'] as num).toDouble();
    final b = (arguments['b'] as num).toDouble();

    double result;
    switch (operation) {
      case 'add':
        result = a + b;
        break;
      case 'subtract':
        result = a - b;
        break;
      case 'multiply':
        result = a * b;
        break;
      case 'divide':
        if (b == 0) {
          throw Exception('Division by zero');
        }
        result = a / b;
        break;
      default:
        throw Exception('Unknown operation: $operation');
    }

    Logger.getLogger('LlmServerDemo').debug('$result');
    return LlmCallToolResult([
      LlmTextContent(text: result.toString()),
    ]);
  }
}
```

#### Registering and Using Plugins

```dart
// Create plugin manager
final pluginManager = PluginManager();

// Register plugins
await pluginManager.registerPlugin(EchoToolPlugin());
await pluginManager.registerPlugin(CalculatorToolPlugin());

// Create client with plugin manager
final client = await mcpLlm.createClient(
  providerName: 'claude',
  pluginManager: pluginManager,
);

// Enable tools when chatting
final response = await client.chat(
  "What is 42 + 17?",
  enableTools: true,  // Important: tools must be enabled
);
```

For server-side use, you can register plugins with the MCP server:

```dart
// Register core LLM plugins with the server
await llmServer.registerCoreLlmPlugins(
  registerCompletionTool: true,
  registerStreamingTool: true,
  registerEmbeddingTool: true,
  registerRetrievalTools: true,
  registerWithServer: true,
);
```

### Performance Monitoring

Track and optimize LLM usage:

```dart
// Enable performance monitoring
mcpLlm.enablePerformanceMonitoring();

// Get performance metrics
final metrics = mcpLlm.getPerformanceMetrics();
logger.info("Total requests: ${metrics['total_requests']}");
logger.info("Success rate: ${metrics['success_rate']}");

// Reset metrics
mcpLlm.resetPerformanceMetrics();

// Disable monitoring
mcpLlm.disablePerformanceMonitoring();
```

## MCP Integration

This package works with both `mcp_client` and `mcp_server`:

### Client Integration

```dart
// Create MCP client
final mcpClient = mcp.McpClient.createClient(
  name: 'myapp',
  version: '1.0.0',
  capabilities: mcp.ClientCapabilities(
    roots: true,
    rootsListChanged: true,
    sampling: true,
  ),
);

// Create LLM client
final llmClient = await mcpLlm.createClient(
  providerName: 'claude',
  config: LlmConfiguration(
    apiKey: 'your-api-key',
    model: 'claude-3-haiku-20240307',
    retryOnFailure: true,
    maxRetries: 3,
    options: {
      'max_tokens': 4096,
      'default_temperature': 0.7
    }
  ),
  mcpClient: mcpClient,
);

// Create transport
final transport = await mcp.McpClient.createSseTransport(
  serverUrl: 'http://localhost:8999/sse',
  headers: {
    'Authorization': 'Bearer your_token',
  },
);

// Connect to server
await mcpClient.connectWithRetry(
  transport,
  maxRetries: 3,
  delay: const Duration(seconds: 1),
);
```

### Server Integration

```dart
// Create MCP server
final mcpServer = mcp.McpServer.createServer(
  name: 'llm-service',
  version: '1.0.0',
  capabilities: mcp.ServerCapabilities(
    tools: true,
    toolsListChanged: true,
    resources: true,
    resourcesListChanged: true,
    prompts: true,
    promptsListChanged: true,
  ),
);

// Create plugin manager and register plugins
final pluginManager = PluginManager();
await pluginManager.registerPlugin(EchoToolPlugin());
await pluginManager.registerPlugin(CalculatorToolPlugin());

// Create LLM server
final llmServer = await mcpLlm.createServer(
  providerName: 'openai',
  config: LlmConfiguration(
    apiKey: 'your-api-key',
    model: 'gpt-3.5-turbo',
  ),
  mcpServer: mcpServer,
  storageManager: MemoryStorage(),
  pluginManager: pluginManager,
);

// Create transport
final transport = mcp.McpServer.createSseTransport(
  endpoint: '/sse',
  messagesEndpoint: '/message',
  port: 8999,
  authToken: 'your_token',
);

// Connect server to transport
mcpServer.connect(transport);

// Register core LLM plugins
await llmServer.registerCoreLlmPlugins(
  registerCompletionTool: true,
  registerStreamingTool: true,
  registerEmbeddingTool: true,
  registerRetrievalTools: true,
  registerWithServer: true,
);
```

### Multi-Client/Server Support

You can connect multiple MCP clients or servers:

```dart
// Multiple clients approach
final llmClient = await mcpLlm.createClient(
  providerName: 'claude',
  mcpClients: {
    'search': searchMcpClient,
    'database': dbMcpClient,
    'filestore': fileMcpClient
  }
);

// Adding a client later
await mcpLlm.addMcpClientToLlmClient('client_id', 'new_tool', newMcpClient);

// Setting the default MCP client
await mcpLlm.setDefaultMcpClient('client_id', 'database');

// Getting a list of MCP client IDs
final mcpIds = mcpLlm.getMcpClientIds('client_id');

// Similar functions exist for servers
final llmServer = await mcpLlm.createServer(
  providerName: 'openai',
  mcpServers: {
    'main': mainMcpServer,
    'backup': backupMcpServer,
  }
);

await mcpLlm.addMcpServerToLlmServer('server_id', 'new_server', newMcpServer);
await mcpLlm.setDefaultMcpServer('server_id', 'main');
final mcpServerIds = mcpLlm.getMcpServerIds('server_id');
```

### Streaming Responses

For handling streaming responses from the LLM:

```dart
// Subscribe to stream
final responseStream = llmClient.streamChat(
  "Tell me a story about robots",
  enableTools: true,
);

// Response chunk collection buffer
final responseBuffer = StringBuffer();

// Process stream
await for (final chunk in responseStream) {
  // Add chunk text
  responseBuffer.write(chunk.textChunk);
  final currentResponse = responseBuffer.toString();
  
  // Update UI with current response
  print('Current response: $currentResponse');
  
  // Check for tool processing
  if (chunk.metadata.containsKey('processing_tools')) {
    print('Processing tool calls...');
  }
  
  // Check stream completion
  if (chunk.isDone) {
    print('Stream response completed');
  }
}
```

## Issues and Feedback

Please file any issues, bugs, or feature requests in our [issue tracker](https://github.com/app-appplayer/mcp_llm/issues).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.