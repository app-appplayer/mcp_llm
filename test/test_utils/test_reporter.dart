import 'dart:async';
import 'package:test/test.dart';

/// Test result reporter to summarize test runs
class TestReporter {
  int _passed = 0;
  int _failed = 0;
  int _skipped = 0;

  final List<String> _failedTests = [];
  final List<String> _skippedTests = [];

  /// Create a new test reporter
  TestReporter() {
    // Register listener for test events
    tearDown(() {
      final testName = currentTestCase;
      if (testName == null) return;

      final result = currentTestCaseResult;
      if (result == 'success') {
        _passed++;
      } else if (result == 'failure') {
        _failed++;
        _failedTests.add(testName);
      } else if (result == 'skipped') {
        _skipped++;
        _skippedTests.add(testName);
      }
      // Other statuses are ignored
    });

    // Register teardown hook to print report
    tearDownAll(() {
      printSummary();
    });
  }

  /// Print test summary
  void printSummary() {
    print('');
    print('┌──────────────────────────┐');
    print('│     TEST RUN SUMMARY     │');
    print('├──────────────────────────┤');
    print('│ Passed:  $_passed${_getSpaces(12 - _passed.toString().length)}│');
    print('│ Failed:  $_failed${_getSpaces(12 - _failed.toString().length)}│');
    print('│ Skipped: $_skipped${_getSpaces(11 - _skipped.toString().length)}│');
    print('│ Total:   ${_passed + _failed + _skipped}${_getSpaces(12 - (_passed + _failed + _skipped).toString().length)}│');
    print('└──────────────────────────┘');

    if (_failedTests.isNotEmpty) {
      print('');
      print('Failed tests:');
      for (final test in _failedTests) {
        print(' ✗ $test');
      }
    }

    if (_skippedTests.isNotEmpty) {
      print('');
      print('Skipped tests:');
      for (final test in _skippedTests) {
        print(' ↷ $test');
      }
    }

    print('');
  }

  /// Generate spaces for formatting
  String _getSpaces(int count) {
    return ' ' * count;
  }

  /// Get current test name
  static String? get currentTestCase {
    try {
      return Zone.current[#test_description] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Get current test result
  static String? get currentTestCaseResult {
    try {
      return Zone.current[#test_result] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Create reporter for main test run
  static void setup() {
    TestReporter();
  }
}