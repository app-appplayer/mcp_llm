import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;
import 'package:mcp_llm/mcp_llm.dart';

import 'chat_message.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MCP LLM Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MCPHomePage(),
    );
  }
}

class MCPHomePage extends StatefulWidget {
  const MCPHomePage({super.key});

  @override
  State<MCPHomePage> createState() => _MCPHomePageState();
}

class _MCPHomePageState extends State<MCPHomePage> {
  final McpLlm _mcpLlm = McpLlm();
  final Logger _logger = Logger.getLogger('MyApp');
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();

  final String _clientId = 'client1';
  late LlmClient _llmClient;
  late mcp.Client _mcpClient;
  final List<ChatMessage> _messages = [];
  bool _isConnected = false;
  bool _isStreaming = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _connectToLLM() async {
    try {
      // 1. Register LLM providers
      _mcpLlm.registerProvider('openai', OpenAiProviderFactory());
      _mcpLlm.registerProvider('claude', ClaudeProviderFactory());

      // 2. Create MCP client
      _mcpClient = mcp.McpClient.createClient(
        name: 'Demo Client',
        version: '1.0.0',
        capabilities: mcp.ClientCapabilities(
          roots: true,
          rootsListChanged: true,
          sampling: true,
        ),
      );

      // 3. Create transport with proper encoding headers
      final transport = await mcp.McpClient.createSseTransport(
        serverUrl: 'http://localhost:8999/sse',
        headers: {
          'Authorization': 'Bearer test_token',
        },
      );

      // 4. Connect to server
      await _mcpClient.connectWithRetry(
        transport,
        maxRetries: 3,
        delay: const Duration(seconds: 1),
      );

      // 5. Create LLM client with proper encoding configuration
      _llmClient = await _mcpLlm.createClient(
        providerName: 'openai',
        //providerName: 'claude',
        config: LlmConfiguration(
            // For testing, check if we have a valid API key
            apiKey: 'Your-API-Key-Here',
            model: 'gpt-3.5-turbo',
            retryOnFailure: true,
            maxRetries: 3,
            options: {
              'max_tokens': 4096,
              'default_temperature': 0.7
            }
        ),
        mcpClient: _mcpClient,
        clientId: _clientId,
      );

      // Setup event handlers - using available methods
      _setupEventHandlers();

      setState(() {
        _isConnected = _mcpClient.isConnected;
      });

      if (_isConnected) {
        // 6. List available tools
        final tools = await _mcpClient.listTools();
        _logger.debug('Number of available tools: ${tools.length}');
        for (var tool in tools) {
          final json = tool.toJson();
          _logger.debug(jsonEncode(json));
        }
        _showSuccessSnackBar('Connection successful');
      } else {
        _showErrorSnackBar('Connection failed');
      }
    } catch (e) {
      _logger.error('Error while connecting: $e');
      _showErrorSnackBar('Connection failed: $e');
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _messageFocusNode.requestFocus();
    });
  }

  void _setupEventHandlers() {
    // Tool list changed event handler (available method)
    _mcpClient.onToolsListChanged(() {
      _logger.debug('Tool list has changed');
    });

    // Resource list changed event handler
    _mcpClient.onResourcesListChanged(() {
      _logger.debug('Resource list has changed');
    });

    // Prompt list changed event handler
    _mcpClient.onPromptsListChanged(() {
      _logger.debug('Prompt list has changed');
    });

    // Logging event handler
    _mcpClient.onLogging((level, message, logger, data) {
      _logger.debug('Server log [${level.name}]: $message');
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text;
    if (message.isEmpty) return;

    // Add user message to UI
    setState(() {
      _messages.add(ChatMessage(
        role: MessageRole.user,
        content: message,
      ));
      _isStreaming = true;
    });
    _scrollToBottom();

    try {
      // Handle message encoding
      _logger.debug('Message to send: $message');
      // Use streamChat to send message (tools enabled)
      // Subscribe to stream
      final responseStream = _llmClient.streamChat(
        message,
        enableTools: true,
      );

      // Response chunk collection buffer
      final responseBuffer = StringBuffer();

      // Variables for receiving data from stream and updating UI
      String currentResponse = '';
      int assistantMessageIndex = -1;

      // Receive data from stream and update UI
      await for (final chunk in responseStream) {
        // Log chunk data
        //_logger.debug('Received response chunk: ${chunk.textChunk}');

        // Add chunk text
        responseBuffer.write(chunk.textChunk);
        currentResponse = responseBuffer.toString();

        // Update UI - add message on first chunk, replace existing message afterwards
        setState(() {
          if (assistantMessageIndex == -1) {
            // If it's the first chunk, add a new message
            _messages.add(ChatMessage(
              role: MessageRole.assistant,
              content: currentResponse,
            ));
            assistantMessageIndex = _messages.length - 1;
            _scrollToBottom();
          } else {
            // For subsequent chunks, replace the message object
            _messages[assistantMessageIndex] = ChatMessage(
              role: MessageRole.assistant,
              content: currentResponse,
            );
            _scrollToBottom();
          }
        });

        // Tool call processing logging
        if (chunk.metadata.containsKey('processing_tools')) {
          _logger.debug('Processing tool calls...');
        }

        // Check stream completion
        if (chunk.isDone) {
          _logger.debug('Stream response completed');
        }
      }

      setState(() {
        _isStreaming = false;
      });

      _messageController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messageFocusNode.requestFocus();
      });
    } catch (e) {
      setState(() {
        _isStreaming = false;
      });
      _showErrorSnackBar('Message send failed: $e');
      _logger.error('Error occurred while sending message: $e');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messageFocusNode.requestFocus();
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _scrollToBottom() {
    // Add slight delay to ensure UI update before scrolling
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP LLM Demo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: _isConnected ? null : _connectToLLM,
              child: Text(_isConnected ? 'Connected' : 'Connect LLM'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ListTile(
                  title: Text(message.content),
                  subtitle: Text(message.role.toString()),
                  // Show loading indicator if last message is from assistant and streaming
                  trailing: (index == _messages.length - 1 &&
                      message.role == mcp.MessageRole.assistant &&
                      _isStreaming)
                      ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : null,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocusNode,
                    decoration: const InputDecoration(
                      hintText: 'Enter a message',
                    ),
                    enabled: _isConnected && !_isStreaming,
                    onSubmitted: (_isConnected && !_isStreaming)
                        ? (_) => _sendMessage()
                        : null,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: (_isConnected && !_isStreaming) ? _sendMessage : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Clean up resources
    _messageFocusNode.dispose();
    _scrollController.dispose();
    if (_isConnected) {
      _mcpClient.disconnect();
      _mcpLlm.shutdown();
    }
    super.dispose();
  }
}