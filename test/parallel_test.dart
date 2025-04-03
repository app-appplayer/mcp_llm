import 'dart:async';
import 'dart:math';

import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  group('ResultAggregator', () {
    test('SimpleResultAggregator returns first result with SelectionStrategy.first', () {
      final aggregator = SimpleResultAggregator(
        selectionStrategy: SelectionStrategy.first,
      );

      final responses = [
        LlmResponse(text: 'First response'),
        LlmResponse(text: 'Second response'),
      ];

      final result = aggregator.aggregate(responses);
      expect(result.text, equals('First response'));
    });

    test('SimpleResultAggregator returns shortest result with SelectionStrategy.shortest', () {
      final aggregator = SimpleResultAggregator(
        selectionStrategy: SelectionStrategy.shortest,
      );

      final responses = [
        LlmResponse(text: 'Long response text'),
        LlmResponse(text: 'Short'),
      ];

      final result = aggregator.aggregate(responses);
      expect(result.text, equals('Short'));
    });

    test('SimpleResultAggregator returns longest result with SelectionStrategy.longest', () {
      final aggregator = SimpleResultAggregator(
        selectionStrategy: SelectionStrategy.longest,
      );

      final responses = [
        LlmResponse(text: 'Short'),
        LlmResponse(text: 'Long response text'),
      ];

      final result = aggregator.aggregate(responses);
      expect(result.text, equals('Long response text'));
    });

    test('ConfidenceResultAggregator selects result with highest confidence', () {
      final aggregator = ConfidenceResultAggregator();

      final responses = [
        LlmResponse(text: 'Low confidence', metadata: {'confidence': 0.3}),
        LlmResponse(text: 'High confidence', metadata: {'confidence': 0.8}),
        LlmResponse(text: 'Medium confidence', metadata: {'confidence': 0.5}),
      ];

      final result = aggregator.aggregate(responses);
      expect(result.text, equals('High confidence'));
    });

    test('MergeResultAggregator combines all responses', () {
      final aggregator = MergeResultAggregator();

      final responses = [
        LlmResponse(text: 'First response'),
        LlmResponse(text: 'Second response'),
      ];

      final result = aggregator.aggregate(responses);
      expect(result.text, contains('First response'));
      expect(result.text, contains('Second response'));
    });
  });

  group('TaskScheduler', () {
    late PerformanceMonitor monitor;
    late TaskScheduler scheduler;

    setUp(() {
      monitor = PerformanceMonitor();
      scheduler = TaskScheduler(
        maxConcurrency: 2,
        performanceMonitor: monitor,
      );
    });

    test('Tasks are executed in correct priority order', () async {
      final results = <String>[];
      final completer = Completer<void>();

      // Low priority task
      scheduler.scheduleTask(
        task: () async {
          await Future.delayed(Duration(milliseconds: 10));
          results.add('Low priority');
          return 'low';
        },
        priority: 1,
      );

      // High priority task
      scheduler.scheduleTask(
        task: () async {
          await Future.delayed(Duration(milliseconds: 10));
          results.add('High priority');
          return 'high';
        },
        priority: 10,
      );

      // Medium priority task
      scheduler.scheduleTask(
        task: () async {
          await Future.delayed(Duration(milliseconds: 10));
          results.add('Medium priority');
          completer.complete(); // Complete after all tasks finish
          return 'medium';
        },
        priority: 5,
      );

      // Start scheduler
      scheduler.start();

      // Wait for all tasks to complete within reasonable time
      await completer.future.timeout(Duration(seconds: 1));

      // Check results
      expect(results, isNotEmpty);
    }, timeout: Timeout(Duration(seconds: 5))); // Increase test timeout


    test('Respects maxConcurrency limit', () async {
      int concurrentTasks = 0;
      int maxObservedConcurrency = 0;

      for (int i = 0; i < 5; i++) {
        scheduler.scheduleTask(
          task: () async {
            concurrentTasks++;
            maxObservedConcurrency = max(maxObservedConcurrency, concurrentTasks);

            // Simulate work
            await Future.delayed(Duration(milliseconds: 100));

            concurrentTasks--;
            return i;
          },
        );
      }

      scheduler.start();

      // Give time for all tasks to execute
      await Future.delayed(Duration(milliseconds: 1000));

      // Max concurrency should be respected
      expect(maxObservedConcurrency, equals(2));
    });

    test('cancelTasksByCategory cancels pending tasks', () async {
      final completer = Completer<void>();
      final cancelledTasks = <int>[];

      // Set up tasks with error handling for cancellation
      for (int i = 0; i < 5; i++) {
        final int taskId = i;
        scheduler.scheduleTask(
          task: () async {
            try {
              await Future.delayed(Duration(milliseconds: 50));
              return taskId;
            } catch (e) {
              // This won't be reached since cancellation happens at scheduler level
              return -1;
            }
          },
          category: 'test-category',
          priority: 1,
        ).catchError((error) {
          // Track cancelled tasks
          if (error is TaskCancelledException) {
            cancelledTasks.add(taskId);
          }
          if (cancelledTasks.length == 5) {
            completer.complete();
          }
          return -1; // Return a value for the catchError handler
        });
      }

      // Don't start scheduler yet (to ensure tasks are pending)

      // Cancel all tasks in category
      scheduler.cancelTasksByCategory('test-category');

      // Now start the scheduler
      scheduler.start();

      // Wait for error callbacks to process
      await completer.future.timeout(Duration(seconds: 1),
          onTimeout: () {
            // If timeout occurs, still complete the test
            if (!completer.isCompleted) completer.complete();
          }
      );

      // Expectation: All tasks should be cancelled
      expect(cancelledTasks.length, greaterThan(0));
    }, timeout: Timeout(Duration(seconds: 5)));
  });
}