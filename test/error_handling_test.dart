import 'dart:async';
import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_llm/src/utils/error_handler.dart';
import 'package:mcp_llm/src/utils/circuit_breaker.dart';

void main() {
  group('ErrorHandler', () {
    late ErrorHandler handler;
    List<McpLlmError> capturedErrors = [];

    setUp(() {
      handler = ErrorHandler();
      capturedErrors = [];
      handler.registerErrorCallback((error) {
        capturedErrors.add(error);
      });
    });

    test('handleError converts standard exceptions to McpLlmError', () {
      // Test with TimeoutException
      final timeoutError = TimeoutException('Request timed out');
      handler.handleError(timeoutError);

      expect(capturedErrors.length, equals(1));
      expect(capturedErrors[0], isA<TimeoutError>());
      expect(capturedErrors[0].message, contains('timed out'));

      capturedErrors.clear();

      // Test with ArgumentError
      final argError = ArgumentError('Invalid argument', 'param1');
      handler.handleError(argError);

      expect(capturedErrors.length, equals(1));
      expect(capturedErrors[0], isA<ValidationError>());
      expect((capturedErrors[0] as ValidationError).field, equals('param1'));
    });

    test('handleNetworkError creates NetworkError', () {
      handler.handleNetworkError('Failed to connect', statusCode: 404);

      expect(capturedErrors.length, equals(1));
      expect(capturedErrors[0], isA<NetworkError>());
      expect((capturedErrors[0] as NetworkError).statusCode, equals(404));
    });

    test('handleAuthenticationError creates AuthenticationError', () {
      handler.handleAuthenticationError('Invalid API key');

      expect(capturedErrors.length, equals(1));
      expect(capturedErrors[0], isA<AuthenticationError>());
    });

    test('Multiple error callbacks work', () {
      int callCount = 0;
      handler.registerErrorCallback((error) {
        callCount++;
      });

      handler.handleError(Exception('Test error'));

      // The original callback and our new one
      expect(capturedErrors.length, equals(1));
      expect(callCount, equals(1));
    });

    test('Unregistering callback works', () {
      int callCount = 0;
      final callback = (McpLlmError error) {
        callCount++;
      };

      handler.registerErrorCallback(callback);
      handler.handleError(Exception('First error'));
      expect(callCount, equals(1));

      // Unregister and verify no more calls
      handler.unregisterErrorCallback(callback);
      handler.handleError(Exception('Second error'));
      expect(callCount, equals(1)); // Still 1, not increased
    });
  });

  group('CircuitBreaker', () {
    late CircuitBreaker breaker;

    setUp(() {
      breaker = CircuitBreaker(
          name: 'test-breaker',
          settings: CircuitBreakerSettings(
            failureThreshold: 2,
            resetTimeout: Duration(milliseconds: 500),
            halfOpenTimeout: Duration(milliseconds: 200),
            halfOpenSuccessThreshold: 1,
          )
      );
    });

    test('Initial state is closed', () {
      expect(breaker.state, equals(CircuitState.closed));
      expect(breaker.isAllowingRequests, isTrue);
    });

    test('Circuit opens after threshold failures', () async {
      expect(breaker.failureCount, equals(0));

      // First failure
      try {
        await breaker.execute(() async {
          throw Exception('Simulated failure');
        });
      } catch (_) {}

      expect(breaker.failureCount, equals(1));
      expect(breaker.state, equals(CircuitState.closed));

      // Second failure, should trip the circuit
      try {
        await breaker.execute(() async {
          throw Exception('Simulated failure');
        });
      } catch (_) {}

      expect(breaker.state, equals(CircuitState.open));
      expect(breaker.isAllowingRequests, isFalse);
    });

    test('Cannot execute when circuit is open', () async {
      // Force circuit open
      breaker.forceOpen();

      // Attempt to execute should throw CircuitBreakerOpenException
      expect(
              () => breaker.execute(() async => 'Result'),
          throwsA(isA<CircuitBreakerOpenException>())
      );
    });

    test('Circuit transitions to half-open after timeout', () async {
      // Force circuit open
      breaker.forceOpen();
      expect(breaker.state, equals(CircuitState.open));

      // Wait for reset timeout
      await Future.delayed(Duration(milliseconds: 600));

      // Should now be half-open
      expect(breaker.state, equals(CircuitState.halfOpen));
      expect(breaker.isAllowingRequests, isTrue);
    });

    test('Circuit closes after successful test in half-open state', () async {
      // Force circuit to half-open
      breaker.forceOpen();
      await Future.delayed(Duration(milliseconds: 600));
      expect(breaker.state, equals(CircuitState.halfOpen));

      // Execute successful operation
      final result = await breaker.execute(() async => 'Success');

      // Circuit should close
      expect(breaker.state, equals(CircuitState.closed));
      expect(result, equals('Success'));
    });

    test('Circuit reopens after failure in half-open state', () async {
      // Force circuit to half-open
      breaker.forceOpen();
      await Future.delayed(Duration(milliseconds: 600));
      expect(breaker.state, equals(CircuitState.halfOpen));

      // Execute failing operation
      try {
        await breaker.execute(() async {
          throw Exception('Failure in half-open state');
        });
      } catch (_) {}

      // Circuit should open again
      expect(breaker.state, equals(CircuitState.open));
    });

    test('executeStream works with streams', () async {
      final stream = breaker.executeStream(() =>
          Stream.fromIterable([1, 2, 3, 4, 5])
      );

      final results = await stream.toList();
      expect(results, equals([1, 2, 3, 4, 5]));
    });

    test('State change callbacks are triggered', () async {
      CircuitState? oldState;
      CircuitState? newState;

      breaker.onStateChange((from, to) {
        oldState = from;
        newState = to;
      });

      // Force circuit open
      breaker.forceOpen();

      expect(oldState, equals(CircuitState.closed));
      expect(newState, equals(CircuitState.open));
    });
  });
}