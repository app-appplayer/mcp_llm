import '../adapter/mcp_client_manager.dart';
import '../core/models.dart';
import '../utils/logger.dart';

/// Orchestration layer for deferred tool loading
/// Uses internal registry for data management
/// Automatically created when useDeferredLoading=true in LlmClient
class DeferredToolManager {
  final Map<String, LlmToolMetadata> _metadata = {};
  final Map<String, Map<String, dynamic>> _schemas = {};
  final Logger _logger;
  bool _initialized = false;

  DeferredToolManager({
    Logger? logger,
  }) : _logger = logger ?? Logger('DeferredToolManager');

  /// Check if initialized
  bool get isInitialized => _initialized;

  /// Get tool count
  int get count => _schemas.length;

  /// Initialize registry from MCP client manager.
  /// Handles `Map<String, dynamic>` from `McpClientManager.getTools()`.
  Future<void> initialize(McpClientManager clientManager) async {
    if (_initialized) return; // Prevent duplicate initialization

    try {
      final tools = await clientManager.getTools();
      // getTools() returns List<Map<String, dynamic>>
      _cacheFromMaps(tools);
      _initialized = true;
      _logger.info('Cached ${_schemas.length} tools in deferred registry');
    } catch (e) {
      _logger.error('Failed to initialize tool registry: $e');
      rethrow;
    }
  }

  /// Cache tools from Map list (McpClientManager.getTools() result)
  void _cacheFromMaps(List<Map<String, dynamic>> tools) {
    _metadata.clear();
    _schemas.clear();
    for (final tool in tools) {
      final name = tool['name'] as String;
      _metadata[name] = LlmToolMetadata.fromMap(tool);
      _schemas[name] = Map<String, dynamic>.from(tool);
    }
  }

  /// Reset initialization state (for re-initialization)
  void reset() {
    _metadata.clear();
    _schemas.clear();
    _initialized = false;
  }

  /// Get metadata list for LLM context (token-efficient)
  List<Map<String, dynamic>> getMetadataForLlm() {
    return _metadata.values.map((m) => m.toJson()).toList();
  }

  /// Get all metadata objects
  List<LlmToolMetadata> getAllMetadata() => _metadata.values.toList();

  /// Get metadata for specific tool
  LlmToolMetadata? getMetadata(String toolName) => _metadata[toolName];

  /// Get full schema for specific tool
  Map<String, dynamic>? getFullSchema(String toolName) {
    return _schemas[toolName];
  }

  /// Check if tool exists
  bool hasTool(String toolName) => _schemas.containsKey(toolName);

  /// Get all tool names
  List<String> get toolNames => _schemas.keys.toList();

  /// Validate tool call arguments against schema
  ValidationResult validateToolCall(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    final schema = _schemas[toolName];
    if (schema == null) {
      return ValidationResult.invalid('Tool not found: $toolName');
    }

    final inputSchema = schema['inputSchema'] as Map<String, dynamic>?;
    if (inputSchema == null) {
      // No input schema means no required parameters
      return ValidationResult.valid();
    }

    final required = inputSchema['required'] as List<dynamic>? ?? [];

    // Check required parameters
    for (final param in required) {
      if (!arguments.containsKey(param)) {
        return ValidationResult.invalid(
          'Missing required parameter: $param',
        );
      }
    }

    return ValidationResult.valid();
  }

  /// Handle tools/list_changed notification
  void invalidate() {
    reset();
    _logger.info('Tool registry invalidated');
  }
}
