# MCP LLM 

## 🙌 Support This Project

If you find this package useful, consider supporting ongoing development on PayPal.

[![Donate](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/ncp/payment/F7G56QD9LSJ92)  
Support makemind via [PayPal](https://www.paypal.com/ncp/payment/F7G56QD9LSJ92)

---

### 🔗 MCP Dart Package Family

- [`mcp_server`](https://pub.dev/packages/mcp_server): Exposes tools, resources, and prompts to LLMs. Acts as the AI server.
- [`mcp_client`](https://pub.dev/packages/mcp_client): Connects Flutter/Dart apps to MCP servers. Acts as the client interface.
- [`mcp_llm`](https://pub.dev/packages/mcp_llm): Bridges LLMs (Claude, OpenAI, etc.) to MCP clients/servers. Acts as the LLM brain.
- [`flutter_mcp`](https://pub.dev/packages/flutter_mcp): Complete Flutter plugin for MCP integration with platform features.
- [`flutter_mcp_ui_core`](https://pub.dev/packages/flutter_mcp_ui_core): Core models, constants, and utilities for Flutter MCP UI system. 
- [`flutter_mcp_ui_runtime`](https://pub.dev/packages/flutter_mcp_ui_runtime): Comprehensive runtime for building dynamic, reactive UIs through JSON specifications.
- [`flutter_mcp_ui_generator`](https://pub.dev/packages/flutter_mcp_ui_generator): JSON generation toolkit for creating UI definitions with templates and fluent API. 
- [`mcp_flow_runtime`](https://pub.dev/packages/mcp_flow_runtime): Declarative runtime for hardware control and IoT orchestration using MCP Flow DSL.

---

A powerful Dart package for integrating Large Language Models (LLMs) with [Model Context Protocol (MCP)](https://modelcontextprotocol.io/). This package provides comprehensive tools for LLM communication, multi-client support, advanced processing capabilities, and full 2025-03-26 MCP specification compliance.

## ✨ What's New in v1.0.0

🚀 **Major version 1.0.0 release with full 2025-03-26 MCP specification support:**

### 🔐 Phase 1: OAuth 2.1 Authentication Integration
- **OAuth 2.1 Security**: Full PKCE support and token management
- **Secure Authentication**: Complete integration with MCP clients and servers
- **Token Validation**: Advanced token validation and refresh mechanisms

### ⚡ Phase 2: JSON-RPC 2.0 Batch Processing Optimization
- **40-60% Performance Improvement**: Intelligent request batching
- **Configurable Batching**: Customizable batch sizes and timeouts
- **Smart Optimization**: Automatic fallback and retry mechanisms

### 🏥 Phase 3: Enhanced 2025-03-26 Methods
- **Health Monitoring**: Comprehensive `health/check` methods with auto-recovery
- **Capability Management**: Dynamic `capabilities/update` with real-time notifications
- **Lifecycle Management**: Full server lifecycle control (start, stop, pause, resume)
- **Enhanced Error Handling**: Circuit breakers, auto-retry, and intelligent recovery
- **Unified Logging System**: Standard Dart `logging` package with extension methods for backward compatibility

### 🎯 Key Benefits
- **100% Backward Compatible**: Existing code works unchanged
- **Event-Driven Architecture**: Real-time notifications and monitoring
- **Production Ready**: Comprehensive error handling and recovery
- **Performance Optimized**: Significant speed improvements through batching

## Features

### 🔧 Core Features
- **Multiple LLM Provider Support**: Claude, OpenAI, Together AI, and custom providers
- **2025-03-26 MCP Compliance**: Full support for latest MCP specification
- **OAuth 2.1 Authentication**: Secure authentication with PKCE support
- **JSON-RPC 2.0 Batch Processing**: Optimized performance with intelligent batching
- **Multi-Client Management**: Advanced client routing and load balancing

### 🏥 Monitoring & Management
- **Health Monitoring**: Real-time health checks and auto-recovery
- **Capability Management**: Dynamic capability updates and notifications
- **Lifecycle Management**: Complete server lifecycle control
- **Performance Monitoring**: Comprehensive metrics and statistics

### 🔌 Advanced Features
- **Plugin System**: Custom tool plugins and prompt templates
- **RAG Capabilities**: Document store with vector search and retrieval
- **Event Streams**: Real-time capability, lifecycle, and error events
- **Enhanced Error Handling**: Circuit breakers and intelligent retry logic
- **Unified Logging**: Standard Dart logging package with namespace support and extension methods

## Quick Start

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  mcp_llm: ^1.0.3
```

### Basic Usage (2025-03-26)

```dart
import 'package:mcp_llm/mcp_llm.dart';

void main() async {
  // Create enhanced LLM client with 2025-03-26 features
  final llmClient = LlmClient(
    llmProvider: ClaudeProvider(apiKey: 'your-api-key'),
    mcpClients: {
      'tools': myToolsClient,
      'data': myDataClient,
    },
    // Enable 2025-03-26 features
    batchConfig: BatchConfig(maxBatchSize: 10),
    healthConfig: HealthCheckConfig(timeout: Duration(seconds: 5)),
    errorConfig: ErrorHandlingConfig(enableCircuitBreaker: true),
    enableHealthMonitoring: true,
    enableCapabilityManagement: true,
    enableLifecycleManagement: true,
    enableEnhancedErrorHandling: true,
  );

  // Chat with enhanced features
  final response = await llmClient.chat(
    "What's the weather in New York?",
    enableTools: true,
  );

  print(response.text);
  
  // Check feature status
  print('2025-03-26 features: ${llmClient.featureStatus}');
  
  await llmClient.close();
}
```

## 2025-03-26 Enhanced Features

### 🔐 OAuth 2.1 Authentication

```dart
// Enable OAuth 2.1 authentication
final tokenValidator = ApiKeyValidator({
  'your-token': {
    'scopes': ['tools:execute', 'resources:read'],
    'exp': DateTime.now().add(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
    'client_id': 'your-client',
  },
});

// Authentication is automatically handled
final authStatus = llmClient.getClientCapabilities('your-client');
print('OAuth 2.1 enabled: ${authStatus['oauth_2_1']?.enabled}');
```

### ⚡ Batch Processing Optimization

```dart
// Execute multiple operations efficiently
final batchResults = await llmClient.executeBatchTools([
  {'name': 'calculator', 'arguments': {'operation': 'add', 'a': 10, 'b': 20}},
  {'name': 'weather', 'arguments': {'city': 'Tokyo'}},
  {'name': 'translator', 'arguments': {'text': 'Hello', 'target': 'es'}},
]);

// Get performance statistics
final stats = llmClient.getBatchStatistics();
print('Batch efficiency: ${stats['batch_efficiency']}%');
```

### 🏥 Health Monitoring

```dart
// Perform comprehensive health check
final healthReport = await llmClient.performHealthCheck();
print('Overall status: ${healthReport.overallStatus}');
print('Components: ${healthReport.componentResults.length}');

// Check specific client health
final clientHealth = llmClient.getClientHealth('tools-client');
print('Client status: ${clientHealth?.status}');

// Monitor unhealthy clients
final unhealthy = llmClient.unhealthyClients;
if (unhealthy.isNotEmpty) {
  print('Unhealthy clients: $unhealthy');
}
```

### 🔧 Capability Management

```dart
// Update client capabilities dynamically
final updateRequest = CapabilityUpdateRequest(
  clientId: 'tools-client',
  capabilities: [
    McpCapability(
      type: McpCapabilityType.streaming,
      name: 'response_streaming',
      version: '2025-03-26',
      enabled: true,
    ),
  ],
  requestId: llmClient.generateCapabilityRequestId(),
  timestamp: DateTime.now(),
);

final updateResponse = await llmClient.updateClientCapabilities(updateRequest);
print('Update success: ${updateResponse.success}');

// Get all capabilities
final allCapabilities = llmClient.getAllCapabilities();
allCapabilities.forEach((clientId, caps) {
  print('$clientId: ${caps.keys.join(', ')}');
});
```

### 🔄 Server Lifecycle Management

```dart
// Start server
final startResponse = await llmClient.startServer('my-server');
print('Server started: ${startResponse.success}');

// Get server information
final serverInfo = llmClient.getServerInfo('my-server');
print('Server state: ${serverInfo?.state}');
print('Uptime: ${serverInfo?.uptime}');

// Pause and resume
await llmClient.pauseServer('my-server');
await llmClient.resumeServer('my-server');

// Enable auto-restart
llmClient.setServerAutoRestart('my-server', true);
```

### 🛡️ Enhanced Error Handling

```dart
// Execute with intelligent error handling
try {
  final result = await llmClient.executeWithErrorHandling(
    () => someRiskyOperation(),
    clientId: 'tools-client',
    expectedCategory: McpErrorCategory.network,
    context: {'operation': 'data_sync'},
  );
} catch (e) {
  print('Error handled gracefully: $e');
}

// Get error statistics
final errorStats = llmClient.getErrorStatistics();
print('Total errors: ${errorStats['total_errors']}');
print('Circuit breakers: ${errorStats['circuit_breakers']}');

// Monitor error events
llmClient.errorEvents?.listen((error) {
  print('Error detected: ${error.message}');
  print('Recovery actions: ${error.recoveryActions}');
});
```

### 📡 Event Streams

```dart
// Monitor capability changes
llmClient.capabilityEvents?.listen((event) {
  print('Capability ${event.eventType}: ${event.capability.name}');
});

// Monitor lifecycle changes
llmClient.lifecycleEvents?.listen((event) {
  print('Server ${event.serverId}: ${event.fromState} -> ${event.toState}');
});

// Monitor errors
llmClient.errorEvents?.listen((error) {
  print('Error in ${error.clientId}: ${error.message}');
});
```

### 📝 Unified Logging System

The 2025-03-26 update includes a unified logging system using the standard Dart `logging` package:

```dart
import 'package:mcp_llm/src/utils/logger.dart';

// Configure root logger
Logger.root.level = Level.ALL;
Logger.root.onRecord.listen((record) {
  print('[${record.level.name}] ${record.loggerName}: ${record.message}');
});

// Create loggers with namespace
final logger = Logger('mcp_llm.my_component');

// Use standard logging methods
logger.info('Standard logging method');
logger.warning('Warning message');
logger.severe('Error message');

// Backward compatibility with extension methods
logger.debug('Debug message using extension');
logger.error('Error message using extension');
logger.warn('Warning using extension');
logger.trace('Trace message using extension');

// Namespace-based filtering
final mcpLogger = Logger('mcp_llm.batch');
final healthLogger = Logger('mcp_llm.health');
```

## Migration from v0.x to v1.0.0

### ✅ Zero Breaking Changes
v1.0.0 is 100% backward compatible. Your existing code will work unchanged:

```dart
// This v0.x code still works perfectly in v1.0.0
final client = LlmClient(
  llmProvider: ClaudeProvider(apiKey: 'key'),
  mcpClient: myMcpClient,
);
final response = await client.chat("Hello!");
```

### 🚀 Opt-in to New Features
Enable 2025-03-26 features as needed:

```dart
// Add new features gradually
final client = LlmClient(
  llmProvider: ClaudeProvider(apiKey: 'key'),
  mcpClient: myMcpClient,
  // Add new features
  batchConfig: BatchConfig(), // Enable batch processing
  enableHealthMonitoring: true, // Enable health monitoring
  enableEnhancedErrorHandling: true, // Enable error handling
);
```

## Core Concepts

### LLM Providers

```dart
// Multiple provider support
mcpLlm.registerProvider('openai', OpenAiProviderFactory());
mcpLlm.registerProvider('claude', ClaudeProviderFactory());
mcpLlm.registerProvider('together', TogetherProviderFactory());

// Create client with provider
final client = await mcpLlm.createClient(
  providerName: 'claude',
  config: LlmConfiguration(
    apiKey: 'your-api-key',
    model: 'claude-3-5-sonnet',
    options: {
      'temperature': 0.7,
      'maxTokens': 1500,
    },
  ),
);
```

### Multi-Client Management with 2025-03-26 Features

```dart
// Enhanced client management
final client = LlmClient(
  llmProvider: provider,
  mcpClients: {
    'tools': toolsClient,
    'data': dataClient,
    'search': searchClient,
  },
  // 2025-03-26 enhancements
  batchConfig: BatchConfig(maxBatchSize: 15),
  healthConfig: HealthCheckConfig(includeSystemMetrics: true),
);

// Intelligent routing with health awareness
final bestClient = await client.selectHealthyClient(['tools', 'data']);
```

### Plugin System

```dart
class CalculatorPlugin extends BaseToolPlugin {
  CalculatorPlugin() : super(
    name: 'calculator',
    version: '2025-03-26',
    description: 'Advanced calculator with 2025-03-26 features',
    inputSchema: {
      'type': 'object',
      'properties': {
        'operation': {'type': 'string'},
        'a': {'type': 'number'},
        'b': {'type': 'number'},
      },
      'required': ['operation', 'a', 'b']
    },
  );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> args) async {
    // Plugin implementation with error handling
    final operation = args['operation'] as String;
    final a = args['a'] as num;
    final b = args['b'] as num;
    
    // Enhanced error handling in 2025-03-26
    if (operation == 'divide' && b == 0) {
      throw Exception('Division by zero not allowed');
    }
    
    final result = _performCalculation(operation, a, b);
    return LlmCallToolResult([LlmTextContent(text: result.toString())]);
  }
}
```

## Examples

### 📁 Complete Examples Available
- `example/mcp_2025_complete_example.dart` - Full 2025-03-26 feature demonstration
- `example/batch_processing_2025_example.dart` - Batch processing optimization
- `example/logging_example.dart` - Updated logging system with standard Dart logging package
- `example/simple_test_example.dart` - Simple usage example for quick start

### Performance Comparison

```dart
// Before v1.0.0 (sequential)
final start = DateTime.now();
final result1 = await client.executeTool('calc', {'op': 'add', 'a': 1, 'b': 2});
final result2 = await client.executeTool('calc', {'op': 'mul', 'a': 3, 'b': 4});
final result3 = await client.executeTool('weather', {'city': 'NYC'});
final sequential = DateTime.now().difference(start);

// v1.0.0 batch processing
final batchStart = DateTime.now();
final batchResults = await client.executeBatchTools([
  {'name': 'calc', 'arguments': {'op': 'add', 'a': 1, 'b': 2}},
  {'name': 'calc', 'arguments': {'op': 'mul', 'a': 3, 'b': 4}},
  {'name': 'weather', 'arguments': {'city': 'NYC'}},
]);
final batch = DateTime.now().difference(batchStart);

print('Sequential: ${sequential.inMilliseconds}ms');
print('Batch: ${batch.inMilliseconds}ms');
print('Improvement: ${((sequential.inMilliseconds - batch.inMilliseconds) / sequential.inMilliseconds * 100).round()}%');
```

## Comprehensive Statistics

Get detailed insights with v1.0.0:

```dart
// Get comprehensive system status
final systemStatus = {
  'features': llmClient.featureStatus,
  'batch': llmClient.getBatchStatistics(),
  'health': llmClient.getHealthStatistics(),
  'capabilities': llmClient.getCapabilityStatistics(),
  'lifecycle': llmClient.getLifecycleStatistics(),
  'errors': llmClient.getErrorStatistics(),
};

print('System Status: $systemStatus');
```

## Best Practices for v1.0.0

### 🎯 Performance Optimization
```dart
// Enable all performance features
final client = LlmClient(
  llmProvider: provider,
  mcpClients: clients,
  batchConfig: BatchConfig(
    maxBatchSize: 20,           // Larger batches for better throughput
    batchTimeout: Duration(milliseconds: 50), // Lower latency
    preserveOrder: false,       // Allow parallel execution
  ),
  enableHealthMonitoring: true, // Monitor performance
);
```

### 🛡️ Production Reliability
```dart
// Production-ready configuration
final client = LlmClient(
  llmProvider: provider,
  mcpClients: clients,
  errorConfig: ErrorHandlingConfig(
    enableCircuitBreaker: true,
    enableAutoRecovery: true,
    circuitBreakerThreshold: 5,
    maxRetries: {
      McpErrorCategory.network: 3,
      McpErrorCategory.timeout: 2,
    },
  ),
  healthConfig: HealthCheckConfig(
    timeout: Duration(seconds: 10),
    maxRetries: 3,
    checkAuthentication: true,
  ),
);
```

### 📊 Monitoring & Observability
```dart
// Set up comprehensive monitoring
Timer.periodic(Duration(minutes: 5), (timer) {
  final health = await client.performHealthCheck();
  final stats = client.getErrorStatistics();
  
  // Log health status
  logger.info('Health: ${health.overallStatus}');
  logger.info('Errors: ${stats['total_errors']}');
  
  // Alert on issues
  if (health.overallStatus != HealthStatus.healthy) {
    alertingService.send('Health check failed');
  }
});
```

## MCP Integration

### 2025-03-26 Client Integration

```dart
// Create 2025-03-26 compliant MCP client
final mcpClient = mcp.McpClient.createClient(
  name: 'myapp-2025',
  version: '1.0.0',
  capabilities: mcp.ClientCapabilities(
    roots: true,
    rootsListChanged: true,
    sampling: true,
    // 2025-03-26 capabilities
    healthCheck: true,
    batchProcessing: true,
    oauth21: true,
  ),
);

// Enhanced LLM client with full 2025-03-26 support
final llmClient = LlmClient(
  llmProvider: ClaudeProvider(apiKey: 'key'),
  mcpClient: mcpClient,
  // All 2025-03-26 features enabled
  batchConfig: BatchConfig(),
  healthConfig: HealthCheckConfig(),
  errorConfig: ErrorHandlingConfig(),
  enableHealthMonitoring: true,
  enableCapabilityManagement: true,
  enableLifecycleManagement: true,
  enableEnhancedErrorHandling: true,
);
```

## Version History

- **v1.0.0** (2025-03-26): Major release with full 2025-03-26 MCP specification support
  - OAuth 2.1 authentication with PKCE support
  - JSON-RPC 2.0 batch processing optimization (40-60% performance improvement)
  - Health monitoring and auto-recovery
  - Capability management with real-time notifications
  - Server lifecycle management
  - Enhanced error handling with circuit breakers
  - Unified logging system with standard Dart logging package
- **v0.2.3**: Enhanced plugin system and performance improvements
- **v0.2.0**: RAG capabilities and multi-client support
- **v0.1.0**: Initial release with basic LLM integration

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## Support

- 📖 [Documentation](https://github.com/app-appplayer/mcp_llm/wiki)
- 🐛 [Issue Tracker](https://github.com/app-appplayer/mcp_llm/issues)
- 💬 [Discussions](https://github.com/app-appplayer/mcp_llm/discussions)
- ☕ [Support on Patreon](https://www.patreon.com/mcpdevstudio)

## Related Articles

- [Building a Model Context Protocol Server with Dart: Connecting to Claude Desktop](https://dev.to/mcpdevstudio/building-a-model-context-protocol-server-with-dart-connecting-to-claude-desktop-2aad)
- [Building a Model Context Protocol Client with Dart: A Comprehensive Guide](https://dev.to/mcpdevstudio/building-a-model-context-protocol-client-with-dart-a-comprehensive-guide-4fdg)
- [Integrating AI with Flutter: A Comprehensive Guide to mcp_llm](https://dev.to/mcpdevstudio/integrating-ai-with-flutter-a-comprehensive-guide-to-mcpllm-32f8)
- [MCP LLM v1.0.0: Complete 2025-03-26 Specification Guide](https://dev.to/mcpdevstudio/mcp-llm-v1-complete-2025-specification-guide)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

🚀 **Upgrade to v1.0.0 today and experience the power of 2025-03-26 MCP specification!**