import 'dart:async';
import 'dart:math';
import '../utils/logger.dart';
import '../core/models.dart';

/// Error severity levels
enum ErrorSeverity {
  low,
  medium,
  high,
  critical,
}

/// Error handling strategy
enum ErrorHandlingStrategy {
  ignore,
  log,
  retry,
  fallback,
  escalate,
  circuitBreaker,
  autoRecover,
}

/// Enhanced MCP error extension with additional fields
class McpEnhancedErrorExt extends McpEnhancedError {
  final String id;
  final ErrorSeverity severity;
  final String code;
  final String? details;
  final Exception? originalException;
  final List<String> recoveryActions;

  McpEnhancedErrorExt({
    required this.id,
    required super.clientId,
    required super.category,
    required super.message,
    required super.context,
    required super.timestamp,
    super.stackTrace,
    required this.severity,
    required this.code,
    this.details,
    this.originalException,
    this.recoveryActions = const [],
  });

  @override
  Map<String, dynamic> toJson() {
    final baseJson = super.toJson();
    return {
      ...baseJson,
      'id': id,
      'severity': severity.name,
      'code': code,
      'details': details,
      'recoveryActions': recoveryActions,
    };
  }

  factory McpEnhancedErrorExt.fromException(
    Exception exception, {
    String? clientId,
    Map<String, dynamic> context = const {},
  }) {
    final message = exception.toString();
    final category = _categorizeError(message);
    final severity = _determineSeverity(category, message);
    
    return McpEnhancedErrorExt(
      id: _generateErrorId(),
      clientId: clientId ?? 'system',
      category: category,
      message: message,
      context: context,
      timestamp: DateTime.now(),
      severity: severity,
      code: _generateErrorCode(category),
      originalException: exception,
      recoveryActions: _suggestRecoveryActions(category),
    );
  }

  static String _generateErrorId() {
    return 'err_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(9999)}';
  }

  static final _random = Random();

  static McpErrorCategory _categorizeError(String message) {
    final lowerMessage = message.toLowerCase();
    
    if (lowerMessage.contains('auth') || lowerMessage.contains('token') || lowerMessage.contains('oauth')) {
      return McpErrorCategory.authentication;
    } else if (lowerMessage.contains('permission') || lowerMessage.contains('forbidden')) {
      return McpErrorCategory.permission;
    } else if (lowerMessage.contains('timeout') || lowerMessage.contains('deadline')) {
      return McpErrorCategory.timeout;
    } else if (lowerMessage.contains('network') || lowerMessage.contains('connection')) {
      return McpErrorCategory.network;
    } else if (lowerMessage.contains('validation') || lowerMessage.contains('invalid')) {
      return McpErrorCategory.validation;
    } else if (lowerMessage.contains('batch') || lowerMessage.contains('jsonrpc')) {
      return McpErrorCategory.batch;
    } else {
      return McpErrorCategory.unknown;
    }
  }

  static ErrorSeverity _determineSeverity(McpErrorCategory category, String message) {
    switch (category) {
      case McpErrorCategory.authentication:
      case McpErrorCategory.permission:
        return ErrorSeverity.high;
      case McpErrorCategory.network:
      case McpErrorCategory.timeout:
        return ErrorSeverity.medium;
      case McpErrorCategory.validation:
        return ErrorSeverity.low;
      default:
        return ErrorSeverity.medium;
    }
  }

  static String _generateErrorCode(McpErrorCategory category) {
    final codes = {
      McpErrorCategory.authentication: 'AUTH_ERROR',
      McpErrorCategory.permission: 'PERMISSION_ERROR',
      McpErrorCategory.network: 'NETWORK_ERROR',
      McpErrorCategory.timeout: 'TIMEOUT_ERROR',
      McpErrorCategory.validation: 'VALIDATION_ERROR',
      McpErrorCategory.batch: 'BATCH_ERROR',
      McpErrorCategory.unknown: 'UNKNOWN_ERROR',
    };
    
    return codes[category] ?? 'UNKNOWN_ERROR';
  }

  static List<String> _suggestRecoveryActions(McpErrorCategory category) {
    switch (category) {
      case McpErrorCategory.authentication:
        return ['Refresh authentication token', 'Re-authenticate with OAuth 2.1', 'Check API credentials'];
      case McpErrorCategory.permission:
        return ['Check user permissions', 'Verify scope access', 'Request elevated privileges'];
      case McpErrorCategory.network:
        return ['Retry request', 'Check network connectivity', 'Use fallback endpoint'];
      case McpErrorCategory.timeout:
        return ['Increase timeout duration', 'Retry with exponential backoff', 'Check server load'];
      case McpErrorCategory.validation:
        return ['Validate input parameters', 'Check request format', 'Review API documentation'];
      case McpErrorCategory.batch:
        return ['Reduce batch size', 'Retry individual requests', 'Check batch format'];
      default:
        return ['Contact support', 'Check logs', 'Retry operation'];
    }
  }
}

/// Error handling configuration
class ErrorHandlingConfig {
  final Map<McpErrorCategory, ErrorHandlingStrategy> strategies;
  final Map<McpErrorCategory, int> maxRetries;
  final Map<McpErrorCategory, Duration> retryDelays;
  final bool enableCircuitBreaker;
  final Duration circuitBreakerTimeout;
  final int circuitBreakerThreshold;
  final bool enableAutoRecovery;
  final Duration autoRecoveryInterval;

  const ErrorHandlingConfig({
    this.strategies = const {},
    this.maxRetries = const {},
    this.retryDelays = const {},
    this.enableCircuitBreaker = true,
    this.circuitBreakerTimeout = const Duration(minutes: 5),
    this.circuitBreakerThreshold = 5,
    this.enableAutoRecovery = true,
    this.autoRecoveryInterval = const Duration(seconds: 30),
  });

  ErrorHandlingStrategy getStrategy(McpErrorCategory category) {
    return strategies[category] ?? _getDefaultStrategy(category);
  }

  int getMaxRetries(McpErrorCategory category) {
    return maxRetries[category] ?? _getDefaultMaxRetries(category);
  }

  Duration getRetryDelay(McpErrorCategory category) {
    return retryDelays[category] ?? _getDefaultRetryDelay(category);
  }

  ErrorHandlingStrategy _getDefaultStrategy(McpErrorCategory category) {
    switch (category) {
      case McpErrorCategory.authentication:
        return ErrorHandlingStrategy.retry;
      case McpErrorCategory.network:
      case McpErrorCategory.timeout:
        return ErrorHandlingStrategy.circuitBreaker;
      case McpErrorCategory.validation:
        return ErrorHandlingStrategy.log;
      case McpErrorCategory.unknown:
        return ErrorHandlingStrategy.escalate;
      default:
        return ErrorHandlingStrategy.retry;
    }
  }

  int _getDefaultMaxRetries(McpErrorCategory category) {
    switch (category) {
      case McpErrorCategory.authentication:
        return 2;
      case McpErrorCategory.network:
      case McpErrorCategory.timeout:
        return 3;
      case McpErrorCategory.validation:
        return 0;
      default:
        return 1;
    }
  }

  Duration _getDefaultRetryDelay(McpErrorCategory category) {
    switch (category) {
      case McpErrorCategory.authentication:
        return Duration(seconds: 2);
      case McpErrorCategory.network:
      case McpErrorCategory.timeout:
        return Duration(seconds: 1);
      default:
        return Duration(milliseconds: 500);
    }
  }
}

/// Circuit breaker state
enum CircuitState {
  closed,
  open,
  halfOpen,
}

/// Circuit breaker for error handling
class ErrorCircuitBreaker {
  final String name;
  final int threshold;
  final Duration timeout;
  
  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  DateTime? _nextAttemptTime;

  ErrorCircuitBreaker({
    required this.name,
    required this.threshold,
    required this.timeout,
  });

  bool get isClosed => _state == CircuitState.closed;
  bool get isOpen => _state == CircuitState.open;
  bool get isHalfOpen => _state == CircuitState.halfOpen;

  Future<T> execute<T>(Future<T> Function() operation) async {
    if (_shouldReject()) {
      throw Exception('Circuit breaker $name is open');
    }

    try {
      final result = await operation();
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure();
      rethrow;
    }
  }

  bool _shouldReject() {
    switch (_state) {
      case CircuitState.closed:
        return false;
      case CircuitState.open:
        if (_nextAttemptTime != null && DateTime.now().isAfter(_nextAttemptTime!)) {
          _state = CircuitState.halfOpen;
          return false;
        }
        return true;
      case CircuitState.halfOpen:
        return false;
    }
  }

  void _onSuccess() {
    _failureCount = 0;
    _state = CircuitState.closed;
  }

  void _onFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();

    if (_failureCount >= threshold) {
      _state = CircuitState.open;
      _nextAttemptTime = DateTime.now().add(timeout);
    }
  }

  Map<String, dynamic> getStatus() {
    return {
      'name': name,
      'state': _state.name,
      'failure_count': _failureCount,
      'last_failure': _lastFailureTime?.toIso8601String(),
      'next_attempt': _nextAttemptTime?.toIso8601String(),
    };
  }
}

/// Enhanced Error Handler for 2025-03-26 MCP specification
class EnhancedErrorHandler {
  final ErrorHandlingConfig config;
  final Logger _logger = Logger('mcp_llm.enhanced_error_handler');
  
  final Map<String, List<McpEnhancedErrorExt>> _errorHistory = {};
  final Map<McpErrorCategory, ErrorCircuitBreaker> _circuitBreakers = {};
  final Map<String, int> _retryAttempts = {};
  
  // Error statistics
  final Map<McpErrorCategory, int> _errorCounts = {};
  final Map<String, int> _clientErrorCounts = {};
  
  // Auto-recovery tracking
  Timer? _autoRecoveryTimer;
  final Set<String> _clientsInRecovery = {};
  
  // Event stream for error notifications
  final StreamController<McpEnhancedErrorExt> _errorController = StreamController<McpEnhancedErrorExt>.broadcast();
  Stream<McpEnhancedErrorExt> get errors => _errorController.stream;

  EnhancedErrorHandler({
    this.config = const ErrorHandlingConfig(),
  }) {
    _initializeCircuitBreakers();
    _startAutoRecovery();
  }

  /// Initialize circuit breakers for error categories
  void _initializeCircuitBreakers() {
    if (config.enableCircuitBreaker) {
      for (final category in McpErrorCategory.values) {
        if (config.getStrategy(category) == ErrorHandlingStrategy.circuitBreaker) {
          _circuitBreakers[category] = ErrorCircuitBreaker(
            name: category.name,
            threshold: config.circuitBreakerThreshold,
            timeout: config.circuitBreakerTimeout,
          );
        }
      }
    }
  }

  /// Start auto-recovery process
  void _startAutoRecovery() {
    if (config.enableAutoRecovery) {
      _autoRecoveryTimer = Timer.periodic(config.autoRecoveryInterval, (_) {
        _performAutoRecovery();
      });
    }
  }

  /// Handle error with enhanced processing
  Future<T> handleError<T>(
    Future<T> Function() operation, {
    String? clientId,
    McpErrorCategory? expectedCategory,
    Map<String, dynamic> context = const {},
  }) async {
    
    try {
      // Check circuit breaker if applicable
      if (expectedCategory != null && _circuitBreakers.containsKey(expectedCategory)) {
        return await _circuitBreakers[expectedCategory]!.execute(operation);
      }
      
      return await operation();
      
    } catch (e) {
      final enhancedError = _processError(e, clientId: clientId, context: context);
      
      // Store error in history
      _addToErrorHistory(enhancedError);
      
      // Update statistics
      _updateErrorStatistics(enhancedError);
      
      // Emit error event
      _errorController.add(enhancedError);
      
      // Apply error handling strategy
      return await _applyErrorHandlingStrategy(enhancedError, operation);
    }
  }

  /// Process and enhance error
  McpEnhancedErrorExt _processError(
    dynamic error, {
    String? clientId,
    Map<String, dynamic> context = const {},
  }) {
    if (error is McpEnhancedErrorExt) {
      return error;
    }
    
    Exception exception;
    if (error is Exception) {
      exception = error;
    } else {
      exception = Exception(error.toString());
    }
    
    return McpEnhancedErrorExt.fromException(
      exception,
      clientId: clientId,
      context: {
        ...context,
        'handler_version': '2025-03-26',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Apply error handling strategy
  Future<T> _applyErrorHandlingStrategy<T>(
    McpEnhancedErrorExt error,
    Future<T> Function() operation,
  ) async {
    final strategy = config.getStrategy(error.category);
    
    switch (strategy) {
      case ErrorHandlingStrategy.ignore:
        _logger.debug('Ignoring error: ${error.message}');
        throw error.originalException ?? Exception(error.message);
        
      case ErrorHandlingStrategy.log:
        _logger.error('Logged error: ${error.message}');
        throw error.originalException ?? Exception(error.message);
        
      case ErrorHandlingStrategy.retry:
        return await _retryOperation(error, operation);
        
      case ErrorHandlingStrategy.fallback:
        return await _executeWithFallback(error, operation);
        
      case ErrorHandlingStrategy.escalate:
        await _escalateError(error);
        throw error.originalException ?? Exception(error.message);
        
      case ErrorHandlingStrategy.circuitBreaker:
        // Circuit breaker already handled in handleError
        throw error.originalException ?? Exception(error.message);
        
      case ErrorHandlingStrategy.autoRecover:
        await _triggerAutoRecovery(error);
        throw error.originalException ?? Exception(error.message);
    }
  }

  /// Retry operation with exponential backoff
  Future<T> _retryOperation<T>(
    McpEnhancedErrorExt error,
    Future<T> Function() operation,
  ) async {
    final maxRetries = config.getMaxRetries(error.category);
    final baseDelay = config.getRetryDelay(error.category);
    final retryKey = '${error.clientId}_${error.category.name}';
    
    final currentAttempts = _retryAttempts[retryKey] ?? 0;
    
    if (currentAttempts >= maxRetries) {
      _logger.error('Max retries exceeded for ${error.category.name}: ${error.message}');
      _retryAttempts.remove(retryKey);
      throw error.originalException ?? Exception(error.message);
    }
    
    _retryAttempts[retryKey] = currentAttempts + 1;
    
    // Exponential backoff
    final delay = Duration(
      milliseconds: baseDelay.inMilliseconds * (1 << currentAttempts),
    );
    
    _logger.info('Retrying operation (attempt ${currentAttempts + 1}/$maxRetries) after ${delay.inMilliseconds}ms');
    await Future.delayed(delay);
    
    try {
      final result = await operation();
      _retryAttempts.remove(retryKey); // Reset on success
      return result;
    } catch (e) {
      // Will be handled by the outer handleError call
      rethrow;
    }
  }

  /// Execute with fallback mechanism
  Future<T> _executeWithFallback<T>(
    McpEnhancedErrorExt error,
    Future<T> Function() operation,
  ) async {
    _logger.warning('Attempting fallback for error: ${error.message}');
    
    // Implement fallback logic based on error category
    switch (error.category) {
      case McpErrorCategory.network:
        // Try alternative endpoint or cached data
        break;
      case McpErrorCategory.authentication:
        // Try to refresh token automatically
        break;
      case McpErrorCategory.timeout:
        // Try alternative resource or default value
        break;
      default:
        break;
    }
    
    // For now, just throw the original error
    throw error.originalException ?? Exception(error.message);
  }

  /// Escalate error to higher level
  Future<void> _escalateError(McpEnhancedErrorExt error) async {
    _logger.error('CRITICAL - Escalating error: ${error.message}');
    
    // Send to monitoring system
    // Alert administrators
    // Create incident ticket
    
    await Future.delayed(Duration(milliseconds: 100)); // Simulate escalation
  }

  /// Trigger auto-recovery for client
  Future<void> _triggerAutoRecovery(McpEnhancedErrorExt error) async {
    if (!_clientsInRecovery.contains(error.clientId)) {
      _clientsInRecovery.add(error.clientId);
      _logger.info('Triggering auto-recovery for client: ${error.clientId}');
      
      // Implement recovery actions based on error category
      await _executeRecoveryActions(error);
      
      // Remove from recovery set after delay
      Timer(Duration(minutes: 5), () {
        _clientsInRecovery.remove(error.clientId);
      });
    }
  }

  /// Execute recovery actions
  Future<void> _executeRecoveryActions(McpEnhancedErrorExt error) async {
    for (final action in error.recoveryActions) {
      try {
        _logger.info('Executing recovery action: $action');
        await _performRecoveryAction(action, error);
      } catch (e) {
        _logger.error('Recovery action failed: $action - $e');
      }
    }
  }

  /// Perform specific recovery action
  Future<void> _performRecoveryAction(String action, McpEnhancedErrorExt error) async {
    switch (action.toLowerCase()) {
      case 'refresh authentication token':
        // Implement token refresh
        break;
      case 'restart server':
        // Implement server restart
        break;
      case 'check network connectivity':
        // Implement network check
        break;
      default:
        _logger.debug('Unknown recovery action: $action');
    }
    
    await Future.delayed(Duration(milliseconds: 100)); // Simulate action
  }

  /// Perform periodic auto-recovery
  void _performAutoRecovery() {
    // Check for clients that might need recovery
    for (final clientId in _clientErrorCounts.keys) {
      final errorCount = _clientErrorCounts[clientId] ?? 0;
      if (errorCount > 10 && !_clientsInRecovery.contains(clientId)) {
        _logger.info('Triggering scheduled auto-recovery for client: $clientId');
        // Trigger recovery for high-error clients
      }
    }
    
    // Reset some counters periodically
    _resetPeriodicCounters();
  }

  /// Reset periodic counters
  void _resetPeriodicCounters() {
    // Reset retry attempts for old entries
    final now = DateTime.now();
    
    // This is simplified - in real implementation, you'd track timestamps
    if (now.minute == 0) { // Reset hourly
      _retryAttempts.clear();
    }
  }

  /// Add error to history
  void _addToErrorHistory(McpEnhancedErrorExt error) {
    final clientId = error.clientId;
    _errorHistory[clientId] ??= [];
    _errorHistory[clientId]!.add(error);
    
    // Keep only recent errors
    const maxHistorySize = 1000;
    if (_errorHistory[clientId]!.length > maxHistorySize) {
      _errorHistory[clientId]!.removeAt(0);
    }
  }

  /// Update error statistics
  void _updateErrorStatistics(McpEnhancedErrorExt error) {
    _errorCounts[error.category] = (_errorCounts[error.category] ?? 0) + 1;
    _clientErrorCounts[error.clientId] = (_clientErrorCounts[error.clientId] ?? 0) + 1;
  }


  /// Get error statistics
  Map<String, dynamic> getErrorStatistics() {
    final totalErrors = _errorCounts.values.fold(0, (a, b) => a + b);
    
    return {
      'total_errors': totalErrors,
      'errors_by_category': Map.from(_errorCounts),
      'errors_by_client': Map.from(_clientErrorCounts),
      'circuit_breakers': _circuitBreakers.map((key, cb) => MapEntry(key.name, cb.getStatus())),
      'clients_in_recovery': _clientsInRecovery.length,
      'active_retries': _retryAttempts.length,
    };
  }

  /// Get error history for client
  List<McpEnhancedErrorExt> getErrorHistory(String clientId) {
    return List.unmodifiable(_errorHistory[clientId] ?? []);
  }

  /// Get all error history
  Map<String, List<McpEnhancedErrorExt>> getAllErrorHistory() {
    return Map.unmodifiable(_errorHistory);
  }

  /// Clear error history
  void clearErrorHistory([String? clientId]) {
    if (clientId != null) {
      _errorHistory.remove(clientId);
    } else {
      _errorHistory.clear();
    }
  }

  /// Dispose of error handler resources
  void dispose() {
    _autoRecoveryTimer?.cancel();
    _errorController.close();
    _errorHistory.clear();
    _circuitBreakers.clear();
    _retryAttempts.clear();
    _errorCounts.clear();
    _clientErrorCounts.clear();
    _clientsInRecovery.clear();
    _logger.info('Enhanced error handler disposed');
  }
}