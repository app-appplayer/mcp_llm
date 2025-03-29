# MCP Llm

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
  mcp_llm: ^0.0.1
```

Or install via command line:

```bash
dart pub add mcp_llm
```

### Basic Usage

```dart
import 'package:mcp_llm/mcp_llm.dart';

void main() async {
  // Get MCPLlm instance
  final mcpLlm = MCPLlm.instance;
  
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
  
  print(response.text);
  
  // Clean up
  await mcpLlm.shutdown();
}
```

## Core Concepts

### LLM Providers

The `LlmInterface` provides a standardized way to interact with different LLM providers:

```dart
final provider = ClaudeProvider(
  apiKey: 'your-api-key',
  model: 'claude-3-5-sonnet',
);

final response = await provider.complete(LlmRequest(
  prompt: "What's the meaning of life?",
  parameters: {'temperature': 0.7},
));

print(response.text);
```

### Multi-Client Management

The `MultiClientManager` handles multiple LLM clients with intelligent routing:

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
  aggregator: MergeResultAggregator(),
);
```

### RAG (Retrieval Augmented Generation)

Integrate document retrieval with LLM generation:

```dart
// Create document store
final storageManager = PersistentStorage('path/to/storage');
final documentStore = DocumentStore(storageManager);
final retrievalManager = RetrievalManager(
  documentStore: documentStore,
  llmProvider: provider,
);

// Add documents
await retrievalManager.addDocument(Document(
  title: 'Climate Change Overview',
  content: 'Climate change refers to...',
));

// Perform RAG query
final answer = await retrievalManager.retrieveAndGenerate(
  "What are the main causes of climate change?",
  topK: 3,
);
```

## Examples

Check out the [example](https://github.com/app-appplayer/mcp_llm/tree/main/example) directory for complete sample applications.

## Additional Features

### Plugin System

Extend functionality with custom plugins:

```dart
// Create a custom tool plugin
final weatherPlugin = WeatherToolPlugin();
await mcpLlm.registerPlugin(weatherPlugin, {'api_key': 'weather-api-key'});

// The plugin is automatically available for tool use
final response = await client.chat(
  "What's the weather in Tokyo?",
  enablePlugins: true,
);
```

### Performance Monitoring

Track and optimize LLM usage:

```dart
// Enable performance monitoring
mcpLlm.enablePerformanceMonitoring();

// Get performance metrics
final metrics = mcpLlm.getPerformanceMetrics();
print("Total requests: ${metrics['total_requests']}");
print("Success rate: ${metrics['success_rate']}");
```

## MCP Integration

This package works with both `mcp_client` and `mcp_server`:

```dart
// Client integration
final mcpClient = McpClient.createClient(
  name: 'myapp',
  version: '1.0.0',
);
final transport = McpClient.createStdioTransport();
mcpClient.connect(transport);

final llmClient = await mcpLlm.createClient(
  providerName: 'claude',
  mcpClient: mcpClient,
);

// Server integration
final mcpServer = McpServer.createServer(
  name: 'llm-service',
  version: '1.0.0',
  capabilities: ServerCapabilities(tools: true),
);

final llmServer = await mcpLlm.createServer(
  providerName: 'claude',
  mcpServer: mcpServer,
);

await llmServer.registerLlmTools();
```

## Issues and Feedback

Please file any issues, bugs, or feature requests in our [issue tracker](https://github.com/app-appplayer/mcp_llm/issues).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
