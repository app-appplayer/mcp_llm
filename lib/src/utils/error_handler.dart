import 'dart:async';

import '../../mcp_llm.dart';

/// Error types for MCPLlm
enum ErrorType {
  network,
  authentication,
  permission,
  validation,
  resourceNotFound,
  timeout,
  provider,
  client,
  server,
  unknown,
}

/// Base class for MCPLlm errors
class McpLlmError extends Error {
  /// Error message
  final String message;

  /// Error type
  final ErrorType type;

  /// Original error, if any
  final dynamic originalError;

  /// Stack trace, if available
  @override
  final StackTrace? stackTrace;

  McpLlmError(
      this.message, {
        this.type = ErrorType.unknown,
        this.originalError,
        this.stackTrace,
      });

  @override
  String toString() => 'McpLlmError(${type.name}): $message';
}

/// Network-related errors (API calls, connectivity)
class NetworkError extends McpLlmError {
  /// HTTP status code, if applicable
  final int? statusCode;

  NetworkError(
      super.message, {
        this.statusCode,
        super.originalError,
        super.stackTrace,
      }) : super(
    type: ErrorType.network,
  );

  @override
  String toString() => 'NetworkError: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}

/// Authentication errors (API keys, tokens)
class AuthenticationError extends McpLlmError {
  AuthenticationError(
      super.message, {
        super.originalError,
        super.stackTrace,
      }) : super(
    type: ErrorType.authentication,
  );
}

/// Permission errors (access denied)
class PermissionError extends McpLlmError {
  PermissionError(
      super.message, {
        super.originalError,
        super.stackTrace,
      }) : super(
    type: ErrorType.permission,
  );
}

/// Validation errors (invalid inputs)
class ValidationError extends McpLlmError {
  /// Field that failed validation, if applicable
  final String? field;

  ValidationError(
      super.message, {
        this.field,
        super.originalError,
        super.stackTrace,
      }) : super(
    type: ErrorType.validation,
  );

  @override
  String toString() => 'ValidationError: $message${field != null ? ' (Field: $field)' : ''}';
}

/// Resource not found errors
class ResourceNotFoundError extends McpLlmError {
  /// ID of the resource that wasn't found
  final String? resourceId;

  /// Type of resource that wasn't found
  final String? resourceType;

  ResourceNotFoundError(
      super.message, {
        this.resourceId,
        this.resourceType,
        super.originalError,
        super.stackTrace,
      }) : super(
    type: ErrorType.resourceNotFound,
  );

  @override
  String toString() => 'ResourceNotFoundError: $message${resourceType != null ? ' (Type: $resourceType)' : ''}${resourceId != null ? ' (ID: $resourceId)' : ''}';
}

/// Timeout errors
class TimeoutError extends McpLlmError {
  /// Duration after which the operation timed out
  final Duration? duration;

  TimeoutError(
      super.message, {
        this.duration,
        super.originalError,
        super.stackTrace,
      }) : super(
    type: ErrorType.timeout,
  );

  @override
  String toString() => 'TimeoutError: $message${duration != null ? ' (Duration: ${duration?.inSeconds}s)' : ''}';
}

/// Provider-specific errors
class ProviderError extends McpLlmError {
  /// Name of the provider that raised the error
  final String providerName;

  ProviderError(
      super.message, {
        required this.providerName,
        super.originalError,
        super.stackTrace,
      }) : super(
    type: ErrorType.provider,
  );

  @override
  String toString() => 'ProviderError($providerName): $message';
}

/// Error handler for MCPLlm
class ErrorHandler {
  final Logger _logger = Logger('mcp_llm.error_handler');

  ErrorHandler();

  /// Error callbacks
  final List<void Function(McpLlmError)> _errorCallbacks = [];

  /// Register an error callback
  void registerErrorCallback(void Function(McpLlmError) callback) {
    _errorCallbacks.add(callback);
  }

  /// Unregister an error callback
  void unregisterErrorCallback(void Function(McpLlmError) callback) {
    _errorCallbacks.remove(callback);
  }

  /// Handle an error
  void handleError(dynamic error, {StackTrace? stackTrace}) {
    final mcpError = _convertToMcpLlmError(error, stackTrace);

    // Log the error
    _logger.error(mcpError.toString());
    if (mcpError.stackTrace != null) {
      _logger.debug('Stack trace: ${mcpError.stackTrace}');
    }

    // Invoke callbacks
    for (final callback in _errorCallbacks) {
      try {
        callback(mcpError);
      } catch (e) {
        _logger.error('Error in error callback: $e');
      }
    }
  }

  /// Convert an error to a McpLlmError
  McpLlmError _convertToMcpLlmError(dynamic error, StackTrace? stackTrace) {
    // If it's already a McpLlmError, return it
    if (error is McpLlmError) {
      return error;
    }

    // Handle common error types
    if (error is TimeoutException) {
      return TimeoutError(
        error.message ?? 'Operation timed out',
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    if (error is FormatException) {
      return ValidationError(
        'Invalid format: ${error.message}',
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    if (error is ArgumentError) {
      return ValidationError(
        'Invalid argument: ${error.message}',
        field: error.name,
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    if (error is StateError) {
      return McpLlmError(
        'Invalid state: ${error.message}',
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    // Default to generic error
    return McpLlmError(
      error.toString(),
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  /// Create and handle a network error
  void handleNetworkError(String message, {
    int? statusCode,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    final error = NetworkError(
      message,
      statusCode: statusCode,
      originalError: originalError,
      stackTrace: stackTrace,
    );

    handleError(error);
  }

  /// Create and handle an authentication error
  void handleAuthenticationError(String message, {
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    final error = AuthenticationError(
      message,
      originalError: originalError,
      stackTrace: stackTrace,
    );

    handleError(error);
  }

  /// Create and handle a permission error
  void handlePermissionError(String message, {
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    final error = PermissionError(
      message,
      originalError: originalError,
      stackTrace: stackTrace,
    );

    handleError(error);
  }

  /// Create and handle a validation error
  void handleValidationError(String message, {
    String? field,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    final error = ValidationError(
      message,
      field: field,
      originalError: originalError,
      stackTrace: stackTrace,
    );

    handleError(error);
  }

  /// Create and handle a resource not found error
  void handleResourceNotFoundError(String message, {
    String? resourceId,
    String? resourceType,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    final error = ResourceNotFoundError(
      message,
      resourceId: resourceId,
      resourceType: resourceType,
      originalError: originalError,
      stackTrace: stackTrace,
    );

    handleError(error);
  }

  /// Create and handle a timeout error
  void handleTimeoutError(String message, {
    Duration? duration,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    final error = TimeoutError(
      message,
      duration: duration,
      originalError: originalError,
      stackTrace: stackTrace,
    );

    handleError(error);
  }

  /// Create and handle a provider error
  void handleProviderError(String message, {
    required String providerName,
    dynamic originalError,
    StackTrace? stackTrace,
  }) {
    final error = ProviderError(
      message,
      providerName: providerName,
      originalError: originalError,
      stackTrace: stackTrace,
    );

    handleError(error);
  }
}