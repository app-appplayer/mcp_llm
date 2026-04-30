import '../../mcp_llm.dart';

abstract class CallToolResult {
  List<LLmContent> get content;
  bool get isStreaming;
  bool? get isError;
  Map<String, dynamic> toJson();
}

abstract class ReadResourceResult {
  String get content;
  String get mimeType;
  List<LLmContent> get contents;
  Map<String, dynamic> toJson();
}

abstract class GetPromptResult {
  String get description;
  List<LlmMessage> get messages;
  Map<String, dynamic> toJson();
}

/// Type definition for tool handler functions with cancellation and progress reporting
typedef ToolHandler = Future<dynamic> Function(Map<String, dynamic> arguments);

/// Type definition for resource handler functions
typedef ResourceHandler = Future<dynamic> Function(String uri, Map<String, dynamic> params);

/// Type definition for prompt handler functions
typedef PromptHandler = Future<dynamic> Function(Map<String, dynamic> arguments);

/// Adapter for interfacing with MCP server instances
/// This adapter handles the conversion between the MCP Server
/// and LLM-related functionality
class LlmServerAdapter {
  final dynamic _mcpServer;
  final Logger _logger = Logger('mcp_llm.server_adapter');

  LlmServerAdapter(this._mcpServer) {
    if (_mcpServer == null) {
      _logger.warning('Provided server is null - adapter functionality will be limited');
    }
  }

  /// Check if server is available
  bool get hasServer => _mcpServer != null;

  /// Register a tool with the server
  Future<bool> registerTool({
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema,
    required ToolHandler handler
  }) async {
    if (!hasServer) {
      _logger.error('Cannot register tool: MCP server is not available');
      return false;
    }

    try {
      // Register with wrapped handler
      await _mcpServer.addTool(
        name: name,
        description: description,
        inputSchema: inputSchema,
        handler: handler,
      );
      _logger.info('Successfully registered tool: $name');
      return true;
    } catch (e) {
      _logger.error('Failed to register tool "$name": $e');
      return false;
    }
  }

  /// Register a prompt with the server
  Future<bool> registerPrompt({
    required String name,
    required String description,
    required List<dynamic> arguments,
    required PromptHandler handler,
  }) async {
    if (!hasServer) {
      _logger.error('Cannot register prompt: MCP server is not available');
      return false;
    }

    // Normalise each argument to a spec-shaped map so we can route through
    // mcp_server's `addPromptMap` sibling. The typed entry point would
    // refuse `List<dynamic>` at runtime (List is invariant in Dart), and
    // we don't want this adapter to depend on mcp_server's `PromptArgument`
    // type just to satisfy a typed signature.
    final argsMaps = <Map<String, dynamic>>[];
    for (final arg in arguments) {
      if (arg is Map<String, dynamic>) {
        argsMaps.add(arg);
      } else {
        try {
          final j = (arg as dynamic).toJson();
          argsMaps.add(j is Map<String, dynamic>
              ? j
              : Map<String, dynamic>.from(j as Map));
        } catch (e) {
          _logger.error(
              'Prompt argument is not a Map and has no toJson(): $arg ($e)');
          return false;
        }
      }
    }
    try {
      // Prefer the Map-based sibling (added in mcp_server 2.0+).
      await _mcpServer.addPromptMap(
        name: name,
        description: description,
        arguments: argsMaps,
        handler: handler,
      );
      _logger.info('Successfully registered prompt: $name');
      return true;
    } catch (e) {
      _logger.error('Failed to register prompt "$name": $e');
      return false;
    }
  }

  /// Register a resource with the server
  Future<bool> registerResource({
    required String uri,
    required String name,
    required String description,
    required String mimeType,
    required ResourceHandler handler,
  }) async {
    if (!hasServer) {
      _logger.error('Cannot register resource: MCP server is not available');
      return false;
    }

    try {
      // Call addResource with named parameters
      await _mcpServer.addResource(
        uri: uri,
        name: name,
        description: description,
        mimeType: mimeType,
        handler: handler,
      );
      _logger.info('Successfully registered resource: $uri ($name)');
      return true;
    } catch (e) {
      _logger.error('Failed to register resource "$uri": $e');
      return false;
    }
  }

  /// Execute a tool directly through the server
  Future<dynamic> executeTool(String toolName, Map<String, dynamic> args) async {
    if (!hasServer) {
      _logger.error('Cannot execute tool: MCP server is not available');
      throw StateError('MCP server is not available');
    }

    try {
      _logger.debug('Executing tool directly: $toolName');
      final result = await _mcpServer.executeTool(
        name: toolName,
        args: args,
      );
      return result;
    } catch (e) {
      _logger.error('Failed to execute tool "$toolName": $e');
      throw Exception('Failed to execute tool "$toolName": $e');
    }
  }

  /// Get prompt directly from the server
  Future<dynamic> getPrompt(String promptName, Map<String, dynamic> args) async {
    if (!hasServer) {
      _logger.error('Cannot get prompt: MCP server is not available');
      throw StateError('MCP server is not available');
    }

    try {
      _logger.debug('Getting prompt directly: $promptName');
      final result = await _mcpServer.getPrompt(
        name: promptName,
        args: args,
      );
      return result;
    } catch (e) {
      _logger.error('Failed to get prompt "$promptName": $e');
      throw Exception('Failed to get prompt "$promptName": $e');
    }
  }

  /// Read resource directly from the server
  Future<dynamic> readResource(String resourceUri, [Map<String, dynamic>? params]) async {
    if (!hasServer) {
      _logger.error('Cannot read resource: MCP server is not available');
      throw StateError('MCP server is not available');
    }

    try {
      _logger.debug('Reading resource directly: $resourceUri');
      final result = await _mcpServer.readResource(
        uri: resourceUri,
        parameters: params,
      );
      return result;
    } catch (e) {
      _logger.error('Failed to read resource "$resourceUri": $e');
      throw Exception('Failed to read resource "$resourceUri": $e');
    }
  }

  /// List all registered tools on the server
  Future<List<Map<String, dynamic>>> getTools() async {
    if (!hasServer) {
      _logger.error('Cannot list tools: MCP server is not available');
      return [];
    }

    try {
      final tools = await _mcpServer.getTools();
      return _normalizeToolsList(tools);
    } catch (e) {
      _logger.error('Failed to list tools: $e');
      return [];
    }
  }

  /// List all registered prompts on the server
  Future<List<Map<String, dynamic>>> getPrompts() async {
    if (!hasServer) {
      _logger.error('Cannot list prompts: MCP server is not available');
      return [];
    }

    try {
      final prompts = await _mcpServer.getPrompts();
      return _normalizePromptsList(prompts);
    } catch (e) {
      _logger.error('Failed to list prompts: $e');
      return [];
    }
  }

  /// List all registered resources on the server
  Future<List<Map<String, dynamic>>> getResources() async {
    if (!hasServer) {
      _logger.error('Cannot list resources: MCP server is not available');
      return [];
    }

    try {
      final resources = await _mcpServer.getResources();
      return _normalizeResourcesList(resources);
    } catch (e) {
      _logger.error('Failed to list resources: $e');
      return [];
    }
  }

  /// Get server status information
  Map<String, dynamic> getServerStatus() {
    if (!hasServer) {
      return {'running': false, 'error': 'MCP server is not available'};
    }

    try {
      final status = _mcpServer.getHealth();
      return _normalizeServerStatus(status);
    } catch (e) {
      _logger.error('Error getting server status: $e');
      return {'running': false, 'error': e.toString()};
    }
  }

  /// Helper method to normalize tools list format
  List<Map<String, dynamic>> _normalizeToolsList(List<dynamic> tools) {
    return tools.map<Map<String, dynamic>>((tool) {
      if (tool is Map<String, dynamic>) {
        return tool;
      } else {
        try {
          // Try toJson for non-Map objects
          return tool.toJson();
        } catch (e) {
          // Fallback to constructing a basic map
          return {
            'name': tool.name.toString(),
            'description': tool.description?.toString() ?? '',
            'inputSchema': tool.schema ?? {},
          };
        }
      }
    }).toList();
  }

  /// Helper method to normalize prompts list format
  List<Map<String, dynamic>> _normalizePromptsList(List<dynamic> prompts) {
    return prompts.map<Map<String, dynamic>>((prompt) {
      if (prompt is Map<String, dynamic>) {
        return prompt;
      } else {
        try {
          // Try toJson for non-Map objects
          return prompt.toJson();
        } catch (e) {
          // Fallback to constructing a basic map
          return {
            'name': prompt.name.toString(),
            'description': prompt.description?.toString() ?? '',
            'arguments': prompt.arguments ?? [],
          };
        }
      }
    }).toList();
  }

  /// Helper method to normalize resources list format
  List<Map<String, dynamic>> _normalizeResourcesList(List<dynamic> resources) {
    return resources.map<Map<String, dynamic>>((resource) {
      if (resource is Map<String, dynamic>) {
        return resource;
      } else {
        try {
          // Try toJson for non-Map objects
          return resource.toJson();
        } catch (e) {
          // Fallback to constructing a basic map
          return {
            'name': resource.name.toString(),
            'description': resource.description?.toString() ?? '',
            'uri': resource.uri?.toString() ?? '',
            'mimeType': resource.mimeType?.toString() ?? 'text/plain',
          };
        }
      }
    }).toList();
  }

  // === MCP 2.0 surface — server-initiated outbound + new APIs ===

  /// Server-initiated request: ask the connected client's LLM to
  /// generate a completion (spec `sampling/createMessage`). Returns the
  /// spec `CreateMessageResult` map.
  ///
  /// [params] follows the spec shape — `messages`, `maxTokens` (required)
  /// plus optional `modelPreferences`, `systemPrompt`, `includeContext`,
  /// `temperature`, `stopSequences`, `metadata`. Spec 2025-11-25 also
  /// allows `tools` / `toolChoice`.
  Future<Map<String, dynamic>> requestSampling(
    String sessionId,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!hasServer) {
      throw StateError('MCP server is not available');
    }
    final result = await _mcpServer.requestClientSampling(
      sessionId,
      params,
      timeout: timeout,
    );
    return result is Map<String, dynamic>
        ? result
        : Map<String, dynamic>.from(result as Map);
  }

  /// Server-initiated request: ask the connected client to elicit input
  /// from the user (spec 2025-06-18+ `elicitation/create`). Returns
  /// `{ action, content? }` per spec.
  Future<Map<String, dynamic>> requestElicitation(
    String sessionId,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    if (!hasServer) {
      throw StateError('MCP server is not available');
    }
    final result = await _mcpServer.requestClientElicitation(
      sessionId,
      params,
      timeout: timeout,
    );
    return result is Map<String, dynamic>
        ? result
        : Map<String, dynamic>.from(result as Map);
  }

  /// Server-initiated request: ask the connected client for its current
  /// roots (spec `roots/list`). Returns the raw list of root maps.
  Future<List<dynamic>> requestRoots(
    String sessionId, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!hasServer) {
      throw StateError('MCP server is not available');
    }
    final list = await _mcpServer.requestClientRoots(sessionId, timeout: timeout);
    if (list is List) return list;
    return const <dynamic>[];
  }

  /// Register a `completion/complete` handler for argument autocompletion
  /// (spec). [refType] is `'prompt'` or `'resource'`; [refKey] is the
  /// prompt name or resource template URI; pass `'*'` for a wildcard.
  Future<bool> registerCompletion({
    required String refType,
    required String refKey,
    required Future<Map<String, dynamic>> Function(
      Map<String, dynamic> ref,
      Map<String, dynamic> argument,
      Map<String, dynamic>? context,
    ) handler,
  }) async {
    if (!hasServer) return false;
    try {
      _mcpServer.addCompletion(
        refType: refType,
        refKey: refKey,
        handler: handler,
      );
      return true;
    } catch (e) {
      _logger.warning('Underlying server does not support addCompletion: $e');
      return false;
    }
  }

  /// Register a tool with structured output support (spec 2025-06-18+).
  /// Pairs an [outputSchema] with the tool so clients can validate the
  /// `structuredContent` field of the result.
  Future<bool> registerStructuredTool({
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema,
    required Map<String, dynamic> outputSchema,
    required ToolHandler handler,
    String? title,
    List<Map<String, dynamic>>? icons,
    Map<String, dynamic>? meta,
  }) async {
    if (!hasServer) return false;
    try {
      await _mcpServer.addTool(
        name: name,
        description: description,
        inputSchema: inputSchema,
        outputSchema: outputSchema,
        title: title,
        icons: icons,
        meta: meta,
        handler: handler,
      );
      return true;
    } catch (e) {
      _logger.warning(
          'Underlying server does not accept structured-tool kwargs: $e');
      // Fallback to the legacy-shape registerTool.
      return registerTool(
        name: name,
        description: description,
        inputSchema: inputSchema,
        handler: handler,
      );
    }
  }

  /// Configure the OAuth Protected Resource metadata served at
  /// `/.well-known/oauth-protected-resource` (spec 2025-06-18+ /
  /// RFC 9728).
  void configureProtectedResource({
    required String resource,
    required List<String> authorizationServers,
    List<String>? scopesSupported,
    List<String>? bearerMethodsSupported,
    String? resourceDocumentation,
  }) {
    if (!hasServer) return;
    try {
      _mcpServer.configureProtectedResource(
        resource: resource,
        authorizationServers: authorizationServers,
        scopesSupported: scopesSupported,
        bearerMethodsSupported: bearerMethodsSupported,
        resourceDocumentation: resourceDocumentation,
      );
    } catch (e) {
      _logger.warning(
          'Underlying server does not support configureProtectedResource: $e');
    }
  }

  /// Helper method to normalize server status
  Map<String, dynamic> _normalizeServerStatus(dynamic status) {
    if (status == null) {
      return {'running': false};
    }

    if (status is Map<String, dynamic>) {
      return status;
    }

    // Try to extract common fields from status object
    try {
      return {
        'running': status.isRunning ?? true,
        'connectedSessions': status.connectedSessions ?? 0,
        'registeredTools': status.registeredTools ?? 0,
        'registeredResources': status.registeredResources ?? 0,
        'registeredPrompts': status.registeredPrompts ?? 0,
        'uptime': status.uptime?.inSeconds ?? 0,
      };
    } catch (e) {
      // Simple fallback
      return {'running': true};
    }
  }
}
