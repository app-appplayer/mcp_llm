import '../core/models.dart';
import 'plugin_interface.dart';
import '../utils/logger.dart';
import 'dart:io';
import 'dart:convert';

/// Base implementation of a resource plugin
abstract class BaseResourcePlugin implements ResourcePlugin {
  @override
  final String name;

  @override
  final String version;

  @override
  final String description;

  /// Resource URI
  final String uri;

  /// Resource MIME type
  final String? mimeType;

  /// Resource URI template
  final String? uriTemplate;

  /// Logger instance
  final Logger _logger = Logger('mcp_llm.resource_plugin');

  /// Plugin configuration
  Map<String, dynamic> _config = {};

  /// Plugin initialization state
  bool _isInitialized = false;

  BaseResourcePlugin({
    required this.name,
    required this.version,
    required this.description,
    required this.uri,
    this.mimeType,
    this.uriTemplate,
  });

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _config = Map<String, dynamic>.from(config);
    _isInitialized = true;

    await onInitialize(config);

    _logger.debug('Initialized resource plugin: $name v$version');
  }

  /// Hook for plugin-specific initialization logic
  Future<void> onInitialize(Map<String, dynamic> config) async {
    // Override in subclass if needed
  }

  @override
  Future<void> shutdown() async {
    await onShutdown();
    _isInitialized = false;

    _logger.debug('Shut down resource plugin: $name');
  }

  /// Hook for plugin-specific shutdown logic
  Future<void> onShutdown() async {
    // Override in subclass if needed
  }

  @override
  LlmResource getResourceDefinition() {
    _checkInitialized();

    return LlmResource(
      name: name,
      description: description,
      uri: uri,
      mimeType: mimeType,
      uriTemplate: uriTemplate,
    );
  }

  @override
  Future<LlmReadResourceResult> read(Map<String, dynamic> parameters) async {
    _checkInitialized();

    try {
      _logger.debug('Reading resource plugin: $name with parameters: $parameters');

      // Execute the resource read
      final result = await onRead(parameters);

      _logger.debug('Resource plugin read completed: $name');
      return result;
    } catch (e, stackTrace) {
      _logger.error('Error reading resource plugin $name: $e');
      _logger.debug('Stack trace: $stackTrace');

      return LlmReadResourceResult(
        content: 'Error reading resource: $e',
        mimeType: 'text/plain',
        contents: [LlmTextContent(text: 'Error reading resource: $e')],
      );
    }
  }

  /// Hook for plugin-specific read logic
  Future<LlmReadResourceResult> onRead(Map<String, dynamic> parameters);

  /// Check if the plugin is initialized
  void _checkInitialized() {
    if (!_isInitialized) {
      throw StateError('Resource plugin $name is not initialized');
    }
  }

  /// Get a configured value with fallback
  T getConfigValue<T>(String key, T defaultValue) {
    return _config.containsKey(key) ? _config[key] as T : defaultValue;
  }
}

/// A file resource plugin implementation that serves local files
class FileResourcePlugin extends BaseResourcePlugin {
  /// Base directory for file serving
  final String baseDirectory;

  /// Whether to allow serving files outside the base directory
  final bool allowOutsideBaseDir;

  /// File extensions and their corresponding MIME types
  final Map<String, String> _extensionMimeTypes = {
    '.txt': 'text/plain',
    '.md': 'text/markdown',
    '.html': 'text/html',
    '.htm': 'text/html',
    '.json': 'application/json',
    '.js': 'application/javascript',
    '.css': 'text/css',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.pdf': 'application/pdf',
    '.csv': 'text/csv',
    '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  };

  FileResourcePlugin({
    required super.name,
    required super.description,
    required this.baseDirectory,
    required super.uri,
    String? mimeType,
    super.uriTemplate,
    this.allowOutsideBaseDir = false,
    super.version = '1.0.0',
  }) : super(
    mimeType: mimeType ?? 'application/octet-stream',
  );

  @override
  Future<LlmReadResourceResult> onRead(Map<String, dynamic> parameters) async {
    // Get the file path parameter
    String filePath = parameters['path'] as String? ?? '';

    // If empty file path, use the URI for direct access
    if (filePath.isEmpty) {
      filePath = uri;
    }

    // Normalize file path
    if (!filePath.startsWith('/') && !filePath.contains(':\\')) {
      filePath = '$baseDirectory/$filePath';
    } else if (!allowOutsideBaseDir && !_isWithinBaseDirectory(filePath)) {
      throw SecurityException('Access denied: File is outside of base directory');
    }

    // Check if file exists
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File not found: $filePath');
    }

    // Determine MIME type
    String detectedMimeType = _detectMimeType(filePath);

    // Read file content based on MIME type
    if (detectedMimeType.startsWith('text/') ||
        detectedMimeType == 'application/json' ||
        detectedMimeType == 'application/javascript') {
      // Text content
      final content = await file.readAsString();
      return LlmReadResourceResult(
        content: content,
        mimeType: detectedMimeType,
        contents: [LlmTextContent(text: content)],
      );
    } else {
      // Binary content (convert to base64)
      final bytes = await file.readAsBytes();
      final base64Content = base64Encode(bytes);
      return LlmReadResourceResult(
        content: base64Content,
        mimeType: detectedMimeType,
        contents: [LlmTextContent(text: 'Binary content (base64 encoded)')],
      );
    }
  }

  /// Check if a file path is within the base directory
  bool _isWithinBaseDirectory(String filePath) {
    final directory = Directory(baseDirectory);
    final normalizedBasePath = directory.absolute.path;
    final normalizedFilePath = File(filePath).absolute.path;
    return normalizedFilePath.startsWith(normalizedBasePath);
  }

  /// Detect MIME type based on file extension
  String _detectMimeType(String filePath) {
    final extension = filePath.lastIndexOf('.') != -1
        ? filePath.substring(filePath.lastIndexOf('.'))
        : '';

    return _extensionMimeTypes[extension.toLowerCase()] ?? (mimeType ?? 'application/octet-stream');
  }
}

/// A sample resource plugin that provides documentation or help information
class DocumentationResourcePlugin extends BaseResourcePlugin {
  /// The documentation content
  final Map<String, String> _sections;

  DocumentationResourcePlugin({
    required super.name,
    required super.description,
    required Map<String, String> sections,
    super.uriTemplate,
    super.version = '1.0.0',
  }) : _sections = sections,
        super(
        uri: 'docs://$name',
        mimeType: 'text/markdown',
      );

  @override
  Future<LlmReadResourceResult> onRead(Map<String, dynamic> parameters) async {
    // Get the section parameter
    String sectionName = parameters['section'] as String? ?? 'index';

    // If section doesn't exist, try to use 'index'
    if (!_sections.containsKey(sectionName)) {
      if (sectionName != 'index' && _sections.containsKey('index')) {
        // Return index with a note about the missing section
        final indexContent = _sections['index']!;
        final content = 'Section "$sectionName" not found. Here\'s the index instead:\n\n$indexContent';
        return LlmReadResourceResult(
          content: content,
          mimeType: mimeType ?? 'text/markdown',
          contents: [LlmTextContent(text: content)],
        );
      } else {
        // No index either, list available sections
        final availableSections = _sections.keys.toList().join(', ');
        final content = 'Section "$sectionName" not found. Available sections: $availableSections';
        return LlmReadResourceResult(
          content: content,
          mimeType: 'text/plain',
          contents: [LlmTextContent(text: content)],
        );
      }
    }

    // Return the requested section
    final content = _sections[sectionName]!;
    return LlmReadResourceResult(
      content: content,
      mimeType: mimeType ?? 'text/markdown',
      contents: [LlmTextContent(text: content)],
    );
  }
}


/// Exception thrown for security-related issues
class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}