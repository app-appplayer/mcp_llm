/// Interface for MCP client
abstract class IMcpClient {
  /// Initialize the client
  Future<bool> initialize();

  /// Connect to the server
  ///
  /// [serverAddress] - Server address to connect to
  /// [port] - Server port number
  Future<bool> connect(String serverAddress, int port);

  /// Disconnect from the server
  Future<bool> disconnect();

  /// Send a message to the server
  ///
  /// [message] - Message to be sent
  Future<bool> sendMessage(dynamic message);

  /// Handle incoming message from the server
  ///
  /// [message] - Received message
  void receiveMessage(dynamic message);

  /// Get current client status
  String getStatus();

  /// Check if client is connected to the server
  bool isConnected();

  /// Try to reconnect to the server
  ///
  /// [maxAttempts] - Maximum number of reconnection attempts
  Future<bool> reconnect([int? maxAttempts]);

  /// List available tools on the server
  ///
  /// Returns a list of available tools
  Future<List<Tool>> listTools();

  /// Get details about a specific tool
  ///
  /// [toolId] - Tool identifier
  Future<Map<String, dynamic>> getToolInfo(String toolId);

  /// Execute a tool on the server
  ///
  /// [toolId] - Tool identifier
  /// [params] - Tool parameters
  Future<dynamic> executeTool(String toolId, Map<String, dynamic> params);

  /// Subscribe to a server event
  ///
  /// [eventType] - Type of event to subscribe to
  /// [callback] - Callback function to be called when event occurs
  String subscribe(String eventType, Function callback);

  /// Unsubscribe from a server event
  ///
  /// [subscriptionId] - Subscription identifier returned from subscribe method
  bool unsubscribe(String subscriptionId);

  /// Register a local handler for remote calls
  ///
  /// [handlerId] - Handler identifier
  /// [handler] - Handler function
  void registerHandler(String handlerId, Function handler);

  /// Unregister a local handler
  ///
  /// [handlerId] - Handler identifier
  bool unregisterHandler(String handlerId);
}

/// Factory class for creating MCP client instances
class McpClient {
  /// Create a new MCP client instance
  ///
  /// [config] - Client configuration
  static IMcpClientInstance createClient(McpClientConfig config) {
    return _McpClientInstance(config);
  }
}

/// Configuration for MCP client
class McpClientConfig {
  /// Server address to connect to
  final String serverAddress;

  /// Server port
  final int port;

  /// Client identifier
  final String? clientId;

  /// Connection timeout in milliseconds
  final int connectionTimeout;

  /// Whether to auto-reconnect if connection is lost
  final bool autoReconnect;

  /// Maximum number of reconnection attempts
  final int maxReconnectAttempts;

  /// Delay between reconnection attempts in milliseconds
  final int reconnectDelay;

  /// Constructor for client configuration
  McpClientConfig({
    required this.serverAddress,
    required this.port,
    this.clientId,
    this.connectionTimeout = 30000,
    this.autoReconnect = true,
    this.maxReconnectAttempts = 5,
    this.reconnectDelay = 5000,
  });
}

/// Interface for instances returned by McpClient.createClient
abstract class IMcpClientInstance {
  /// Client instance ID
  String get id;

  /// Client configuration
  McpClientConfig get config;

  /// Connect to server
  ///
  /// [options] - Optional connection parameters
  Future<void> connect([McpClientConnectOptions? options]);

  /// Disconnect from server
  Future<void> disconnect();

  /// Check connection status
  bool isConnected();

  /// Send a message to the server
  ///
  /// [message] - Message to send
  Future<bool> send(McpMessage message);

  /// Get current client status
  McpClientStatus getStatus();

  /// Attempt to reconnect to the server
  ///
  /// [options] - Reconnection options
  Future<bool> reconnect([McpReconnectOptions? options]);

  /// Register event handler for specified event
  ///
  /// [event] - Event name
  /// [handler] - Event handler function
  void on(McpClientEventType event, McpClientEventHandler handler);

  /// Remove event handler for specified event
  ///
  /// [event] - Event name
  /// [handler] - Event handler function to remove
  void off(McpClientEventType event, McpClientEventHandler handler);

  /// List available tools on the server
  Future<List<Tool>> listTools();

  /// Get details about a specific tool
  ///
  /// [toolId] - Tool identifier
  Future<Tool?> getToolInfo(String toolId);

  /// Execute a tool on the server
  ///
  /// [toolId] - Tool identifier
  /// [params] - Tool parameters
  Future<ToolExecutionResult> executeTool(String toolId, Map<String, dynamic> params);

  /// Create a remote procedure call
  ///
  /// [procedure] - Procedure name
  /// [args] - Procedure arguments
  Future<dynamic> callRemoteProcedure(String procedure, List<dynamic> args);

  /// Subscribe to server events
  ///
  /// [eventType] - Type of event to subscribe to
  /// [callback] - Callback function
  String subscribe(String eventType, Function(dynamic) callback);

  /// Unsubscribe from server events
  ///
  /// [subscriptionId] - Subscription identifier
  bool unsubscribe(String subscriptionId);

  /// Register handler for remote calls
  ///
  /// [handlerId] - Handler identifier
  /// [handler] - Handler function
  void registerHandler(String handlerId, Function handler);

  /// Unregister handler for remote calls
  ///
  /// [handlerId] - Handler identifier
  bool unregisterHandler(String handlerId);

  /// Set client capabilities
  ///
  /// [capabilities] - Map of capability names to boolean values
  void setCapabilities(Map<String, bool> capabilities);

  /// Get current client capabilities
  Map<String, bool> getCapabilities();

  /// Ping the server to measure latency
  ///
  /// Returns latency in milliseconds
  Future<int> ping();
}

/// Implementation of MCP client instance
class _McpClientInstance implements IMcpClientInstance {
  @override
  final String id;

  @override
  final McpClientConfig config;

  /// Constructor for client instance
  _McpClientInstance(this.config) : id = DateTime.now().millisecondsSinceEpoch.toString();

  @override
  Future<void> connect([McpClientConnectOptions? options]) async {
    // Implementation goes here
  }

  @override
  Future<void> disconnect() async {
    // Implementation goes here
  }

  @override
  bool isConnected() {
    // Implementation goes here
    return false;
  }

  @override
  Future<bool> send(McpMessage message) async {
    // Implementation goes here
    return false;
  }

  @override
  McpClientStatus getStatus() {
    // Implementation goes here
    return McpClientStatus(
      connected: false,
      connectionState: McpConnectionState.disconnected,
      reconnectAttempts: 0,
      lastConnectedTime: null,
      latency: null,
    );
  }

  @override
  Future<bool> reconnect([McpReconnectOptions? options]) async {
    // Implementation goes here
    return false;
  }

  @override
  void on(McpClientEventType event, McpClientEventHandler handler) {
    // Implementation goes here
  }

  @override
  void off(McpClientEventType event, McpClientEventHandler handler) {
    // Implementation goes here
  }

  @override
  Future<List<Tool>> listTools() async {
    // Implementation goes here
    return [];
  }

  @override
  Future<Tool?> getToolInfo(String toolId) async {
    // Implementation goes here
    return null;
  }

  @override
  Future<ToolExecutionResult> executeTool(String toolId, Map<String, dynamic> params) async {
    // Implementation goes here
    return ToolExecutionResult(
      success: false,
      result: null,
      errorMessage: 'Not implemented',
    );
  }

  @override
  Future<dynamic> callRemoteProcedure(String procedure, List<dynamic> args) async {
    // Implementation goes here
    return null;
  }

  @override
  String subscribe(String eventType, Function(dynamic) callback) {
    // Implementation goes here
    return '';
  }

  @override
  bool unsubscribe(String subscriptionId) {
    // Implementation goes here
    return false;
  }

  @override
  void registerHandler(String handlerId, Function handler) {
    // Implementation goes here
  }

  @override
  bool unregisterHandler(String handlerId) {
    // Implementation goes here
    return false;
  }

  @override
  void setCapabilities(Map<String, bool> capabilities) {
    // Implementation goes here
  }

  @override
  Map<String, bool> getCapabilities() {
    // Implementation goes here
    return {};
  }

  @override
  Future<int> ping() async {
    // Implementation goes here
    return 0;
  }
}

/// Client connection options
class McpClientConnectOptions {
  /// Whether to retry connection if initial attempt fails
  final bool retry;

  /// Maximum number of retry attempts
  final int maxRetries;

  /// Delay between retries in milliseconds
  final int retryDelay;

  /// Constructor for connection options
  McpClientConnectOptions({
    this.retry = true,
    this.maxRetries = 3,
    this.retryDelay = 5000,
  });
}

/// Client reconnection options
class McpReconnectOptions {
  /// Maximum number of reconnection attempts
  final int maxAttempts;

  /// Delay between reconnection attempts in milliseconds
  final int delayMs;

  /// Whether to use exponential backoff for retry delays
  final bool exponentialBackoff;

  /// Constructor for reconnection options
  McpReconnectOptions({
    this.maxAttempts = 5,
    this.delayMs = 5000,
    this.exponentialBackoff = true,
  });
}

/// Client status information
class McpClientStatus {
  /// Whether client is connected
  final bool connected;

  /// Connection state
  final McpConnectionState connectionState;

  /// Number of reconnection attempts
  final int reconnectAttempts;

  /// Last connection time
  final DateTime? lastConnectedTime;

  /// Latency to server in milliseconds
  final int? latency;

  /// Constructor for client status
  McpClientStatus({
    required this.connected,
    required this.connectionState,
    required this.reconnectAttempts,
    this.lastConnectedTime,
    this.latency,
  });
}

/// Connection state enum
enum McpConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Client event types
enum McpClientEventType {
  connect,
  disconnect,
  reconnect,
  reconnecting,
  message,
  error,
  toolExecuted,
  statusChange,
  serverNotification,
  capabilityRequest,
  heartbeat,
}

/// Client event handler function type
typedef McpClientEventHandler = void Function(dynamic data);

/// Tool class
class Tool {
  /// Tool identifier
  final String id;

  /// Tool name
  final String name;

  /// Tool description
  final String description;

  /// Tool version
  final String version;

  /// Tool parameter definitions
  final List<ToolParameter> parameters;

  /// Whether tool requires authentication
  final bool requiresAuth;

  /// Tool category
  final String category;

  /// Tool metadata
  final Map<String, dynamic>? metadata;

  /// List of tools this tool depends on
  final List<String>? dependencies;

  /// Constructor for tool
  Tool({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.parameters,
    this.requiresAuth = false,
    this.category = 'general',
    this.metadata,
    this.dependencies,
  });
}

/// Tool parameter definition
class ToolParameter {
  /// Parameter name
  final String name;

  /// Parameter type
  final String type;

  /// Parameter description
  final String description;

  /// Whether parameter is required
  final bool required;

  /// Default value for optional parameters
  final dynamic defaultValue;

  /// Valid values for enum parameters
  final List<dynamic>? validValues;

  /// Constructor for tool parameter
  ToolParameter({
    required this.name,
    required this.type,
    required this.description,
    this.required = true,
    this.defaultValue,
    this.validValues,
  });
}

/// Tool execution result
class ToolExecutionResult {
  /// Whether execution was successful
  final bool success;

  /// Execution result
  final dynamic result;

  /// Error message if execution failed
  final String? errorMessage;

  /// Execution duration in milliseconds
  final int? executionTime;

  /// Resource usage metrics
  final Map<String, dynamic>? resourceUsage;

  /// Constructor for tool execution result
  ToolExecutionResult({
    required this.success,
    this.result,
    this.errorMessage,
    this.executionTime,
    this.resourceUsage,
  });
}

/// Tools response class
class ToolsResponse {
  /// List of available tools
  final List<Tool> tools;

  /// Total number of tools
  int get count => tools.length;

  /// Response metadata
  final Map<String, dynamic>? metadata;

  /// Constructor for tools response
  ToolsResponse({
    required this.tools,
    this.metadata,
  });

  /// Get tool by ID
  Tool? getToolById(String id) {
    return tools.cast<Tool?>().firstWhere(
          (tool) => tool?.id == id,
      orElse: () => null,
    );
  }

  /// Get tools by category
  List<Tool> getToolsByCategory(String category) {
    return tools.where((tool) => tool.category == category).toList();
  }
}

/// Message structure for communication
class McpMessage {
  /// Unique message ID
  final String id;

  /// Message type
  final String type;

  /// Message payload
  final dynamic payload;

  /// Timestamp when message was created
  final int timestamp;

  /// Optional message metadata
  final Map<String, dynamic>? metadata;

  /// Constructor for message
  McpMessage({
    required this.id,
    required this.type,
    required this.payload,
    int? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;
}