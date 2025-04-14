import 'package:flutter/material.dart';
import 'package:flutter_llm_mcp_server_example/plugins.dart';
import 'package:mcp_server/mcp_server.dart' as mcp;
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LlmServer Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LlmServerDemo(),
    );
  }
}

class LlmServerDemo extends StatefulWidget {
  const LlmServerDemo({super.key});

  @override
  State<LlmServerDemo> createState() => _LlmServerDemoState();
}

class _LlmServerDemoState extends State<LlmServerDemo> {
  final Logger _logger = Logger.getLogger('LlmServerDemo');
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _toolDescriptionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _statusText = 'Server not started';
  String _outputText = '';
  bool _isServerRunning = false;
  bool _isProcessing = false;

  // MCP and LLM components
  mcp.Server? _mcpServer;
  LlmServer? _llmServer;
  McpLlm? _mcpLlm;

  @override
  void initState() {
    super.initState();

    _toolDescriptionController.text = 'Create a weather forecast tool that returns the weather for a given city';
  }

  @override
  void dispose() {
    _promptController.dispose();
    _toolDescriptionController.dispose();
    _scrollController.dispose();
    _stopServer();
    super.dispose();
  }

  // Start the MCP and LLM servers
  Future<void> _startServer() async {
    setState(() {
      _statusText = 'Starting server...';
      _isProcessing = true;
    });

    try {
      // 1. Create server with capabilities
      _mcpServer = mcp.McpServer.createServer(
        name: 'LLM Demo Server',
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

      // 2. Create memory transport (in-memory, no external connection)
      final transport = mcp.McpServer.createSseTransport(
        endpoint: '/sse',
        messagesEndpoint: '/message',
        port: 8999,
        authToken: 'test_token',
      );

      // 3. Connect server to transport
      _mcpServer!.connect(transport);

      // 4. Create McpLlm instance
      _mcpLlm = McpLlm();

      // 5. Register providers
      _registerLlmProviders(_mcpLlm!);

      // 6. Configure API key (replace with your own)
      final llmConfig = LlmConfiguration(
        // For testing, check if we have a valid API key
        apiKey: 'Your-API-Key-Here',
        model: 'gpt-3.5-turbo',
        options: {
          'temperature': 0.7,
          'maxTokens': 1500,
        },
      );

      final pluginManager = PluginManager();

      await pluginManager.registerPlugin(EchoToolPlugin());
      await pluginManager.registerPlugin(CalculatorToolPlugin());

      // 7. Create LlmServer
      _llmServer = await _mcpLlm!.createServer(
        providerName: 'openai', // or 'claude'
        config: llmConfig,
        mcpServer: _mcpServer,
        storageManager: MemoryStorage(),
        pluginManager: pluginManager,
      );

      await _llmServer?.registerCoreLlmPlugins(
        registerCompletionTool: true,
        registerStreamingTool: true,
        registerEmbeddingTool: true,
        registerRetrievalTools: true,
        registerWithServer: true,
      );
      //await _llmServer?.registerPluginsWithServer();

      // 8. Register sample tools
      //await _registerSampleTools();

      // 9. Register LLM tools
      //await _llmServer!.registerLlmTools();

      setState(() {
        _statusText = 'Server running - ${_mcpServer!.name} v${_mcpServer!.version}';
        _isServerRunning = true;
        _isProcessing = false;
        _addToOutput('✅ Server started successfully!');
        _addToOutput('🔧 Sample tools registered');
      });
    } catch (e) {
      setState(() {
        _statusText = 'Error starting server: $e';
        _isProcessing = false;
      });
      _addToOutput('❌ Error: $e');
    }
  }

  // Register LLM providers (OpenAI and Claude)
  void _registerLlmProviders(McpLlm mcpLlm) {
    try {
      mcpLlm.registerProvider('openai', OpenAiProviderFactory());
      _addToOutput('✅ OpenAI provider registered');
    } catch (e) {
      _addToOutput('❌ OpenAI provider registration failed: $e');
    }

    try {
      mcpLlm.registerProvider('claude', ClaudeProviderFactory());
      _addToOutput('✅ Claude provider registered');
    } catch (e) {
      _addToOutput('❌ Claude provider registration failed: $e');
    }
  }

  // Register sample tools
  Future<void> _registerSampleTools() async {
    if (_mcpServer == null) return;

    // 1. Echo tool
    _mcpServer!.addTool(
      name: 'echo',
      description: 'Echoes back the input message',
      inputSchema: {
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
          },
        },
        'required': ['message']
      },
      handler: (args) async {
        final message = args['message'] as String;
        final uppercase = args['uppercase'] as bool? ?? false;

        final result = uppercase ? message.toUpperCase() : message;
        _addToOutput('🔄 Echo tool called: "$message"');

        _logger.debug('Echo tool called: "$message"');
        return mcp.CallToolResult([mcp.TextContent(text: result)]);
      },
    );

    // 2. Simple calculator tool
    _mcpServer!.addTool(
      name: 'calculator',
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
      handler: (args) async {
        final operation = args['operation'] as String;
        final a = (args['a'] as num).toDouble();
        final b = (args['b'] as num).toDouble();

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

        _addToOutput('🔢 Calculator tool: $a $operation $b = $result');
        _logger.debug('Calculator tool called: $a $operation $b = $result');
        return mcp.CallToolResult([mcp.TextContent(text: result.toString())]);
      },
    );

    // Register sample prompt template
    _mcpServer!.addPrompt(
      name: 'greeting',
      description: 'Generate a friendly greeting',
      arguments: [
        mcp.PromptArgument(
          name: 'name',
          description: 'Name of the person to greet',
          required: true,
        ),
        mcp.PromptArgument(
          name: 'formal',
          description: 'Whether to use formal tone',
          required: false,
        ),
      ],
      handler: (args) async {
        final name = args['name'] as String;
        final formal = args['formal'] as bool? ?? false;

        final systemPrompt = formal
            ? 'You are a formal assistant. Use proper titles and formal language.'
            : 'You are a friendly assistant. Use casual, warm language.';

        final messages = [
          mcp.Message(
            role: 'system',
            content: mcp.TextContent(text: systemPrompt),
          ),
          mcp.Message(
            role: 'user',
            content: mcp.TextContent(text: 'Generate a greeting for $name.'),
          ),
        ];

        _addToOutput('👋 Greeting prompt called for: $name (formal: $formal)');

        return mcp.GetPromptResult(
          description: 'Greeting for $name',
          messages: messages,
        );
      },
    );
  }

  // Stop the server
  void _stopServer() async {
    if (_llmServer != null) {
      await _llmServer!.close();
      _llmServer = null;
    }

    if (_mcpLlm != null) {
      await _mcpLlm!.shutdown();
      _mcpLlm = null;
    }

    _mcpServer = null;

    setState(() {
      _statusText = 'Server stopped';
      _isServerRunning = false;
    });

    _addToOutput('🛑 Server stopped');
  }

  // Send a query to the LLM server
  Future<void> _processQuery() async {
    if (!_isServerRunning || _llmServer == null) {
      _addToOutput('❌ Server not running');
      return;
    }

    final query = _promptController.text.trim();
    if (query.isEmpty) {
      _addToOutput('❌ Please enter a query');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      _addToOutput('\n🔎 Processing query: "$query"');

      // Call processQuery on LlmServer
      final response = await _llmServer!.processQuery(
        query: query,
        useLocalTools: true,
        systemPrompt: 'You are a helpful assistant with access to tools. Use them when appropriate.',
      );

      // Check for direct tool response
      if (response.containsKey('directToolResponse') && response['directToolResponse'] == true) {
        _addToOutput('🛠️ Tool Results:');
        if (response.containsKey('toolResults')) {
          final toolResults = response['toolResults'] as Map<String, dynamic>;
          for (final entry in toolResults.entries) {
            _addToOutput('  ${entry.key}: ${entry.value}');
          }
        }

        if (response.containsKey('initialResponse') && response['initialResponse'].isNotEmpty) {
          _addToOutput('\n🤖 Initial Response:');
          _addToOutput(response['initialResponse'] as String);
        }
      } else if (response.containsKey('combinedResponse')) {
        // Combined response (with tool results included)
        _addToOutput('🤖 Response (with tool results):');
        _addToOutput(response['combinedResponse'] as String);
      } else if (response.containsKey('response')) {
        // Regular response
        _addToOutput('🤖 Response:');
        _addToOutput(response['response'] as String);
      } else if (response.containsKey('error')) {
        // Error response
        _addToOutput('❌ Error: ${response['error']}');
      }
    } catch (e) {
      _addToOutput('❌ Error processing query: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });

      // Clear the input field
      _promptController.clear();
    }
  }

  // Generate and register a new tool based on description
  Future<void> _generateTool() async {
    if (!_isServerRunning || _llmServer == null) {
      _addToOutput('❌ Server not running');
      return;
    }

    final description = _toolDescriptionController.text.trim();
    if (description.isEmpty) {
      _addToOutput('❌ Please enter a tool description');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      _addToOutput('\n🔨 Generating tool from description: "$description"');

      final success = await _llmServer!.generateAndRegisterTool(
        description,
        registerWithServer: true,
      );

      if (success) {
        _addToOutput('✅ Tool generated and registered successfully');
        // List available tools
        final tools = await _llmServer!.serverManager?.getTools() ?? [];
        _addToOutput('Available tools (${tools.length}):');
        for (final tool in tools) {
          _addToOutput('  - ${tool['name']}: ${tool['description']}');
        }
      } else {
        _addToOutput('❌ Failed to generate tool');
      }
    } catch (e) {
      _addToOutput('❌ Error generating tool: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Add text to the output area with scroll to bottom
  void _addToOutput(String text) {
    setState(() {
      _outputText += '\n$text';
    });

    // Scroll to bottom after update
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('LLM Server Demo'),
        actions: [
          // Server status indicator
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Chip(
              label: Text(_isServerRunning ? 'Running' : 'Stopped'),
              backgroundColor: _isServerRunning
                  ? Colors.green.shade100
                  : Colors.red.shade100,
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Server control buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isServerRunning || _isProcessing ? null : _startServer,
                    child: const Text('Start Server'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: !_isServerRunning || _isProcessing ? null : _stopServer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade100,
                    ),
                    child: const Text('Stop Server'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            Text(_statusText, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Tool generation section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Generate New Tool',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _toolDescriptionController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Describe the tool you want to generate...',
                        labelText: 'Tool Description',
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _isServerRunning && !_isProcessing ? _generateTool : null,
                      child: const Text('Generate Tool'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Query input
            TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter your query...',
                labelText: 'Query',
              ),
              onSubmitted: (_) => _processQuery(),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isServerRunning && !_isProcessing ? _processQuery : null,
              child: _isProcessing
                  ? const CircularProgressIndicator()
                  : const Text('Send Query'),
            ),

            const SizedBox(height: 16),

            // Output area
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Text(_outputText),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}