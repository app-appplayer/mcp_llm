import 'dart:async';

import '../../mcp_llm.dart';

/// Circuit breaker state
enum CircuitState {
  closed, // Normal operation
  open, // Blocked
  halfOpen, // Testing
}

/// Circuit breaker settings
class CircuitBreakerSettings {
  final int failureThreshold; // Failure count threshold to open circuit
  final Duration resetTimeout; // Circuit reset time
  final Duration halfOpenTimeout; // Half-open state duration
  final int
      halfOpenSuccessThreshold; // Success count threshold to close circuit

  CircuitBreakerSettings({
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(seconds: 30),
    this.halfOpenTimeout = const Duration(seconds: 5),
    this.halfOpenSuccessThreshold = 2,
  });
}

/// Circuit breaker implementation
class CircuitBreaker {
  final String name;
  final CircuitBreakerSettings settings;
  final Logger _logger = Logger.getLogger('mcp_llm.circuit_breaker');

  CircuitState _state = CircuitState.closed;
  int _failureCount = 0;
  int _successCount = 0;
  DateTime? _lastStateChange;
  Timer? _resetTimer;

  // State change callbacks
  final List<void Function(CircuitState, CircuitState)> _stateChangeCallbacks =
      [];

  CircuitBreaker({
    required this.name,
    CircuitBreakerSettings? settings,
  }) : settings = settings ?? CircuitBreakerSettings() {
    _lastStateChange = DateTime.now();
  }

  /// Current state
  CircuitState get state => _state;

  /// Last state change time
  DateTime? get lastStateChange => _lastStateChange;

  /// Whether circuit allows requests
  bool get isAllowingRequests => _state != CircuitState.open;

  /// Current failure count
  int get failureCount => _failureCount;

  /// Current success count
  int get successCount => _successCount;

  /// Register state change callback
  void onStateChange(void Function(CircuitState, CircuitState) callback) {
    _stateChangeCallbacks.add(callback);
  }

  /// Execute function
  Future<T> execute<T>(Future<T> Function() function) async {
    if (!_canExecute()) {
      throw CircuitBreakerOpenException(
        'Circuit $name is ${_state.toString().split('.').last}',
      );
    }

    try {
      final result = await function();
      _recordSuccess();
      return result;
    } catch (e) {
      _recordFailure(e);
      rethrow;
    }
  }

  /// Execute Stream function
  Stream<T> executeStream<T>(Stream<T> Function() function) {
    if (!_canExecute()) {
      throw CircuitBreakerOpenException(
        'Circuit $name is ${_state.toString().split('.').last}',
      );
    }

    try {
      final stream = function();

      return stream.handleError((error, stackTrace) {
        _recordFailure(error);
        throw error;
      }).map((value) {
        _recordSuccess();
        return value;
      });
    } catch (e) {
      _recordFailure(e);
      rethrow;
    }
  }

  /// Check if execution is allowed
  bool _canExecute() {
    switch (_state) {
      case CircuitState.closed:
        return true;

      case CircuitState.open:
        _checkResetTimeout();
        return false;

      case CircuitState.halfOpen:
        return true;
    }
  }

  /// Check reset timeout
  void _checkResetTimeout() {
    if (_lastStateChange == null) return;

    final elapsed = DateTime.now().difference(_lastStateChange!);
    if (elapsed >= settings.resetTimeout) {
      _transitionTo(CircuitState.halfOpen);
    }
  }

  /// Record success
  void _recordSuccess() {
    if (_state == CircuitState.halfOpen) {
      _successCount++;

      if (_successCount >= settings.halfOpenSuccessThreshold) {
        _transitionTo(CircuitState.closed);
      }
    }
  }

  /// Record failure
  void _recordFailure(dynamic error) {
    switch (_state) {
      case CircuitState.closed:
        _failureCount++;

        if (_failureCount >= settings.failureThreshold) {
          _transitionTo(CircuitState.open);
        }
        break;

      case CircuitState.halfOpen:
        _transitionTo(CircuitState.open);
        break;

      case CircuitState.open:
        // Nothing to do when already open
        break;
    }

    _logger.warning('Circuit $name failure: $error');
  }

  /// Transition to new state
  void _transitionTo(CircuitState newState) {
    if (_state == newState) return;

    final oldState = _state;
    _state = newState;
    _lastStateChange = DateTime.now();

    // State-specific initialization
    switch (newState) {
      case CircuitState.closed:
        _failureCount = 0;
        _successCount = 0;
        _cancelResetTimer();
        break;

      case CircuitState.open:
        _successCount = 0;
        _startResetTimer();
        break;

      case CircuitState.halfOpen:
        _successCount = 0;
        _cancelResetTimer();
        _startHalfOpenTimer();
        break;
    }

    // Call callbacks
    for (final callback in _stateChangeCallbacks) {
      try {
        callback(oldState, newState);
      } catch (e) {
        _logger.error('Error in circuit breaker state change callback: $e');
      }
    }

    _logger.info(
        'Circuit $name transitioned from ${oldState.toString().split('.').last} to ${newState.toString().split('.').last}');
  }

  /// Start reset timer
  void _startResetTimer() {
    _cancelResetTimer();
    _resetTimer = Timer(settings.resetTimeout, () {
      _transitionTo(CircuitState.halfOpen);
    });
  }

  /// Start half-open timer
  void _startHalfOpenTimer() {
    _resetTimer = Timer(settings.halfOpenTimeout, () {
      // If not enough successes in half-open time, open again
      if (_state == CircuitState.halfOpen) {
        _transitionTo(CircuitState.open);
      }
    });
  }

  /// Cancel timer
  void _cancelResetTimer() {
    _resetTimer?.cancel();
    _resetTimer = null;
  }

  /// Force circuit open
  void forceOpen() {
    _transitionTo(CircuitState.open);
  }

  /// Force circuit closed
  void forceClosed() {
    _transitionTo(CircuitState.closed);
  }

  /// Reset circuit state
  void reset() {
    _transitionTo(CircuitState.closed);
  }

  /// Clean up resources
  void dispose() {
    _cancelResetTimer();
    _stateChangeCallbacks.clear();
  }
}

/// Circuit open exception
class CircuitBreakerOpenException implements Exception {
  final String message;

  CircuitBreakerOpenException(this.message);

  @override
  String toString() => 'CircuitBreakerOpenException: $message';
}
