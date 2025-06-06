import 'dart:async';
import 'package:collection/collection.dart';

import '../utils/logger.dart';
import '../utils/performance_monitor.dart';

/// Represents a scheduled task with priority
class LlmTask<T> {
  /// Unique task ID
  final String id;

  /// Task function to execute
  final Future<T> Function() task;

  /// Priority level (higher numbers = higher priority)
  final int priority;

  /// When the task was created
  final DateTime createdAt;

  /// Completer to resolve when task completes
  final Completer<T> completer = Completer<T>();

  /// Task category for monitoring
  final String category;

  /// Optional metadata
  final Map<String, dynamic> metadata;

  LlmTask({
    required this.id,
    required this.task,
    this.priority = 0,
    DateTime? createdAt,
    required this.category,
    this.metadata = const {},
  }) : createdAt = createdAt ?? DateTime.now();

  /// Future that completes when the task is done
  Future<T> get future => completer.future;
}

/// Task scheduler with priority queue and concurrency control
class TaskScheduler {
  /// Priority queue for task scheduling
  final PriorityQueue<LlmTask> _taskQueue = PriorityQueue<LlmTask>(
        (a, b) => b.priority.compareTo(a.priority),
  );

  /// Currently running tasks
  final Set<LlmTask> _runningTasks = {};

  /// Maximum number of concurrent tasks
  final int _maxConcurrency;

  /// Whether the scheduler is currently running
  bool _isRunning = false;

  /// Logger instance
  final Logger _logger = Logger('mcp_llm.plugin');

  /// Performance monitor
  final PerformanceMonitor _performanceMonitor;

  /// Create a new task scheduler
  TaskScheduler({int maxConcurrency = 5, required PerformanceMonitor performanceMonitor}) : _maxConcurrency = maxConcurrency, _performanceMonitor = performanceMonitor;

  /// Number of tasks currently in the queue
  int get queueLength => _taskQueue.length;

  /// Number of currently running tasks
  int get runningTaskCount => _runningTasks.length;

  /// Whether the scheduler is currently running tasks
  bool get isRunning => _isRunning;

  /// Start the scheduler
  void start() {
    if (_isRunning) return;

    _isRunning = true;
    _processQueue();

    _logger.debug('Task scheduler started');
  }

  /// Stop the scheduler (finishes running tasks but doesn't start new ones)
  void stop() {
    _isRunning = false;
    _logger.debug('Task scheduler stopped');
  }

  /// Schedule a task for execution
  Future<T> scheduleTask<T>({
    required Future<T> Function() task,
    int priority = 0,
    String category = 'default',
    Map<String, dynamic> metadata = const {},
  }) {
    final taskId = 'task_${DateTime.now().millisecondsSinceEpoch}_${_taskQueue.length}';

    final llmTask = LlmTask<T>(
      id: taskId,
      task: task,
      priority: priority,
      category: category,
      metadata: metadata,
    );

    _taskQueue.add(llmTask as LlmTask<dynamic>);

    _logger.debug('Scheduled task $taskId with priority $priority in category $category');

    // Start processing the queue if we're running
    if (_isRunning) {
      _processQueue();
    }

    return llmTask.future;
  }

  /// Cancel all tasks in a specific category
  int cancelTasksByCategory(String category) {
    int cancelCount = 0;

    // Find tasks in the queue
    final tasksToRemove = <LlmTask>[];
    for (final task in _taskQueue.toList()) {
      if (task.category == category) {
        tasksToRemove.add(task);
        task.completer.completeError(TaskCancelledException('Task cancelled by category: $category'));
        cancelCount++;
      }
    }

    // Remove from queue
    for (final task in tasksToRemove) {
      _taskQueue.remove(task);
    }

    // Note: We don't cancel already running tasks

    _logger.debug('Cancelled $cancelCount tasks in category $category');
    return cancelCount;
  }

  /// Process the task queue
  void _processQueue() async {
    // If we're not running or at max concurrency, don't start new tasks
    if (!_isRunning || _runningTasks.length >= _maxConcurrency) {
      return;
    }

    // Start tasks up to max concurrency
    while (_isRunning && _runningTasks.length < _maxConcurrency && _taskQueue.isNotEmpty) {
      final task = _taskQueue.removeFirst();
      _runningTasks.add(task);

      // Start the task
      _executeTask(task);
    }
  }

  /// Execute a single task
  void _executeTask(LlmTask task) async {
    try {
      _logger.debug('Starting task ${task.id} in category ${task.category}');

      // Track performance
      final requestId = _performanceMonitor.startRequest(task.category);

      // Execute the task
      final result = await task.task();

      // Complete the task and remove from running tasks
      if (!task.completer.isCompleted) {
        task.completer.complete(result);
      }

      // Record successful completion
      _performanceMonitor.endRequest(requestId, success: true);

    } catch (e, stackTrace) {
      _logger.error('Error executing task ${task.id}: $e');
      _logger.debug('Stack trace: $stackTrace');

      // Complete with error
      if (!task.completer.isCompleted) {
        task.completer.completeError(e, stackTrace);
      }

      // Record failure
      _performanceMonitor.endRequest('${task.category}_${task.id}', success: false);
    } finally {
      // Remove from running tasks
      _runningTasks.remove(task);

      // Continue processing the queue
      _processQueue();
    }
  }

  /// Clear all pending tasks
  void clearQueue() {
    final taskCount = _taskQueue.length;

    // Cancel all pending tasks
    for (final task in _taskQueue.toList()) {
      if (!task.completer.isCompleted) {
        task.completer.completeError(TaskCancelledException('Task cancelled by queue clear'));
      }
    }

    _taskQueue.clear();
    _logger.debug('Cleared $taskCount pending tasks from queue');
  }

  /// Get task statistics
  Map<String, Map<String, int>> getTaskStats() {
    // Count by category
    final categoryStats = <String, Map<String, int>>{};

    // Count running tasks by category
    for (final task in _runningTasks) {
      categoryStats.putIfAbsent(task.category, () => {'queued': 0, 'running': 0});
      categoryStats[task.category]!['running'] = (categoryStats[task.category]!['running'] ?? 0) + 1;
    }

    // Count queued tasks by category
    for (final task in _taskQueue.toList()) {
      categoryStats.putIfAbsent(task.category, () => {'queued': 0, 'running': 0});
      categoryStats[task.category]!['queued'] = (categoryStats[task.category]!['queued'] ?? 0) + 1;
    }

    return categoryStats;
  }
}

/// Exception thrown when a task is cancelled
class TaskCancelledException implements Exception {
  final String message;

  TaskCancelledException(this.message);

  @override
  String toString() => 'TaskCancelledException: $message';
}