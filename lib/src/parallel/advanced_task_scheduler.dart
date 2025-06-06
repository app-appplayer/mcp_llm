import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:collection/collection.dart';

import '../../mcp_llm.dart';

/// Task priority calculation strategy
enum PriorityStrategy {
  simple, // Simple numeric priority
  fifo, // First-in-first-out
  deadline, // Deadline priority
  resourceAware, // Resource-aware
  custom, // Custom defined
}

/// Task status
enum TaskStatus {
  pending, // Waiting
  running, // Currently running
  completed, // Completed
  failed, // Failed
  cancelled, // Cancelled
}

/// Task definition
class AdvancedLlmTask<T> {
  /// Task ID
  final String id;

  /// Task execution function
  final Future<T> Function() task;

  /// Priority value
  final int priority;

  /// Task category
  final String category;

  /// Task creation time
  final DateTime createdAt;

  /// Task deadline
  final DateTime? deadline;

  /// Task start time
  DateTime? startedAt;

  /// Task completion time
  DateTime? completedAt;

  /// Task metadata
  final Map<String, dynamic> metadata;

  /// Task status
  TaskStatus status = TaskStatus.pending;

  /// Task result completer
  final Completer<T> completer = Completer<T>();

  /// Task dependency list
  final List<String> dependencies;

  /// Task cancellation function
  final void Function()? onCancel;

  /// Task auto-retry count
  final int maxRetries;

  /// Current retry count
  int retryCount = 0;

  /// Task required resources
  final Map<String, double> requiredResources;

  AdvancedLlmTask({
    required this.id,
    required this.task,
    this.priority = 0,
    required this.category,
    DateTime? createdAt,
    this.deadline,
    this.metadata = const {},
    this.dependencies = const [],
    this.onCancel,
    this.maxRetries = 0,
    this.requiredResources = const {},
  }) : createdAt = createdAt ?? DateTime.now();

  /// Result Future
  Future<T> get future => completer.future;

  /// Calculate waiting time
  Duration getWaitingTime() {
    if (startedAt == null) {
      return DateTime.now().difference(createdAt);
    } else {
      return startedAt!.difference(createdAt);
    }
  }

  /// Calculate execution time
  Duration? getExecutionTime() {
    if (startedAt == null) return null;
    if (completedAt == null) {
      return DateTime.now().difference(startedAt!);
    } else {
      return completedAt!.difference(startedAt!);
    }
  }

  /// Time remaining until deadline
  Duration? getTimeUntilDeadline() {
    if (deadline == null) return null;
    return deadline!.difference(DateTime.now());
  }

  /// Check if past deadline
  bool get isOverdue {
    if (deadline == null) return false;
    return deadline!.isBefore(DateTime.now());
  }

  /// Check if retry is possible
  bool get canRetry {
    return retryCount < maxRetries;
  }
}

/// Advanced task scheduler
class AdvancedTaskScheduler {
  /// Priority strategy
  PriorityStrategy _priorityStrategy;

  /// Maximum concurrent tasks
  final int _maxConcurrency;

  /// Task queue
  final Map<PriorityStrategy, PriorityQueue<AdvancedLlmTask>> _taskQueues = {};

  /// Running tasks
  final Set<AdvancedLlmTask> _runningTasks = {};

  /// Completed tasks (limited number kept)
  final ListQueue<AdvancedLlmTask> _completedTasks = ListQueue();
  final int _maxCompletedTasksHistory;

  /// Task map (by ID)
  final Map<String, AdvancedLlmTask> _tasksById = {};

  /// Task dependency graph
  final Map<String, Set<String>> _dependencyGraph = {};

  /// Running state
  bool _isRunning = false;

  /// Logging
  final Logger _logger = Logger('mcp_llm.advanced_task_scheduler');

  /// Performance monitor
  final PerformanceMonitor _performanceMonitor;

  /// Available resource pool
  final Map<String, double> _resourcePool;

  /// Retry strategy
  final RetryStrategy _retryStrategy;

  /// Completion callback
  final void Function(AdvancedLlmTask, dynamic)? _onTaskComplete;

  AdvancedTaskScheduler({
    int maxConcurrency = 5,
    required PerformanceMonitor performanceMonitor,
    PriorityStrategy priorityStrategy = PriorityStrategy.simple,
    int maxCompletedTasksHistory = 100,
    Map<String, double>? resourcePool,
    RetryStrategy? retryStrategy,
    void Function(AdvancedLlmTask, dynamic)? onTaskComplete,
  })  : _maxConcurrency = maxConcurrency,
        _priorityStrategy = priorityStrategy,
        _performanceMonitor = performanceMonitor,
        _maxCompletedTasksHistory = maxCompletedTasksHistory,
        _resourcePool = resourcePool ?? {'cpu': 100.0, 'memory': 100.0},
        _retryStrategy = retryStrategy ?? RetryStrategy(),
        _onTaskComplete = onTaskComplete {
    // lib/src/parallel/advanced_task_scheduler.dart (continued)
    // Initialize queues for each priority strategy
    _initializeQueues();
  }

  /// Initialize priority queues
  void _initializeQueues() {
    _taskQueues[PriorityStrategy.simple] = PriorityQueue<AdvancedLlmTask>(
        (a, b) => b.priority.compareTo(a.priority));

    _taskQueues[PriorityStrategy.fifo] = PriorityQueue<AdvancedLlmTask>(
        (a, b) => a.createdAt.compareTo(b.createdAt));

    _taskQueues[PriorityStrategy.deadline] =
        PriorityQueue<AdvancedLlmTask>((a, b) {
      if (a.deadline == null && b.deadline == null) return 0;
      if (a.deadline == null) return 1;
      if (b.deadline == null) return -1;
      return a.deadline!.compareTo(b.deadline!);
    });

    _taskQueues[PriorityStrategy.resourceAware] =
        PriorityQueue<AdvancedLlmTask>(
            (a, b) => _compareResourceRequirements(a, b));

    _taskQueues[PriorityStrategy.custom] =
        PriorityQueue<AdvancedLlmTask>((a, b) => _customComparer(a, b));
  }

  /// Resource requirements comparison function
  int _compareResourceRequirements(AdvancedLlmTask a, AdvancedLlmTask b) {
    // Priority for tasks with lower resource requirements
    double aTotalResources =
        a.requiredResources.values.fold(0.0, (sum, val) => sum + val);
    double bTotalResources =
        b.requiredResources.values.fold(0.0, (sum, val) => sum + val);

    // If resource requirements are equal, compare by priority
    if ((aTotalResources - bTotalResources).abs() < 0.001) {
      return b.priority.compareTo(a.priority);
    }

    return aTotalResources.compareTo(bTotalResources);
  }

  /// Custom comparison function
  int _customComparer(AdvancedLlmTask a, AdvancedLlmTask b) {
    // Deadline first, then priority, then waiting time

    // Compare deadlines
    if (a.deadline != null && b.deadline != null) {
      final deadlineComparison = a.deadline!.compareTo(b.deadline!);
      if (deadlineComparison != 0) return deadlineComparison;
    } else if (a.deadline != null) {
      return -1; // a has a deadline, so a goes first
    } else if (b.deadline != null) {
      return 1; // b has a deadline, so b goes first
    }

    // Compare priorities
    final priorityComparison = b.priority.compareTo(a.priority);
    if (priorityComparison != 0) return priorityComparison;

    // Compare waiting times (tasks that have waited longer go first)
    return b.getWaitingTime().compareTo(a.getWaitingTime());
  }

  /// Number of currently waiting tasks
  int get queueLength => _getCurrentQueue().length;

  /// Number of currently running tasks
  int get runningTaskCount => _runningTasks.length;

  /// Scheduler running state
  bool get isRunning => _isRunning;

  /// Get queue for current strategy
  PriorityQueue<AdvancedLlmTask> _getCurrentQueue() {
    return _taskQueues[_priorityStrategy]!;
  }

  /// Start scheduler
  void start() {
    if (_isRunning) return;

    _isRunning = true;
    _processQueue();

    _logger.debug(
        'Advanced task scheduler started with strategy: ${_priorityStrategy.toString().split('.').last}');
  }

  /// Stop scheduler
  void stop() {
    _isRunning = false;
    _logger.debug('Advanced task scheduler stopped');
  }

  /// Change priority strategy
  void setPriorityStrategy(PriorityStrategy strategy) {
    if (_priorityStrategy == strategy) return;

    _priorityStrategy = strategy;

    // Rebuild task queue
    final allTasks = <AdvancedLlmTask>[];

    for (final queue in _taskQueues.values) {
      while (queue.isNotEmpty) {
        allTasks.add(queue.removeFirst());
      }
    }

    // Re-register all tasks
    for (final task in allTasks) {
      _addToQueue(task);
    }

    _logger.info(
        'Changed priority strategy to: ${strategy.toString().split('.').last}');

    // Restart queue processing
    if (_isRunning) {
      _processQueue();
    }
  }

  /// Schedule task
  Future<T> scheduleTask<T>({
    required Future<T> Function() task,
    int priority = 0,
    String category = 'default',
    Map<String, dynamic> metadata = const {},
    DateTime? deadline,
    List<String> dependencies = const [],
    void Function()? onCancel,
    int maxRetries = 0,
    Map<String, double> requiredResources = const {},
  }) {
    final taskId =
        'task_${DateTime.now().millisecondsSinceEpoch}_${_tasksById.length}';

    final llmTask = AdvancedLlmTask<T>(
      id: taskId,
      task: task,
      priority: priority,
      category: category,
      metadata: metadata,
      deadline: deadline,
      dependencies: dependencies,
      onCancel: onCancel,
      maxRetries: maxRetries,
      requiredResources: requiredResources,
    );

    // Register task
    _tasksById[taskId] = llmTask;

    // Update dependency graph
    for (final depId in dependencies) {
      _dependencyGraph.putIfAbsent(depId, () => {}).add(taskId);
    }

    // If there are no dependencies or dependencies are met, add to queue
    if (dependencies.isEmpty || _areDependenciesMet(llmTask)) {
      _addToQueue(llmTask);
    } else {
      _logger.debug(
          'Task $taskId waiting for dependencies: ${dependencies.join(', ')}');
    }

    // If scheduler is running, start processing queue
    if (_isRunning) {
      _processQueue();
    }

    return llmTask.future;
  }

  /// Add task to current queue
  void _addToQueue(AdvancedLlmTask task) {
    _getCurrentQueue().add(task);
    _logger.debug(
        'Added task ${task.id} to queue with strategy: ${_priorityStrategy.toString().split('.').last}');
  }

  /// Check if task dependencies are met
  bool _areDependenciesMet(AdvancedLlmTask task) {
    for (final depId in task.dependencies) {
      final depTask = _tasksById[depId];
      if (depTask == null || depTask.status != TaskStatus.completed) {
        return false;
      }
    }
    return true;
  }

  /// Cancel all tasks in a category
  int cancelTasksByCategory(String category) {
    int cancelCount = 0;

    // Cancel waiting tasks
    for (final queue in _taskQueues.values) {
      // Create temporary list
      final List<AdvancedLlmTask> allTasks = [];
      final List<AdvancedLlmTask> tasksToKeep = [];

      // Extract all tasks from queue
      while (queue.isNotEmpty) {
        allTasks.add(queue.removeFirst());
      }

      // Classify and process tasks
      for (final task in allTasks) {
        if (task.category == category && task.status == TaskStatus.pending) {
          // Task to cancel
          task.status = TaskStatus.cancelled;

          // Call cancellation callback
          if (task.onCancel != null) {
            try {
              task.onCancel!();
            } catch (e) {
              _logger.error('Error in cancel callback for task ${task.id}: $e');
            }
          }

          if (!task.completer.isCompleted) {
            task.completer.completeError(TaskCancelledException(
                'Task cancelled by category: $category'));
          }

          cancelCount++;
        } else {
          // Task to keep
          tasksToKeep.add(task);
        }
      }

      // Add tasks to keep back to queue
      for (final task in tasksToKeep) {
        queue.add(task);
      }
    }

    _logger.debug('Cancelled $cancelCount tasks in category: $category');
    return cancelCount;
  }

  /// Cancel specific task by ID
  bool cancelTask(String taskId) {
    // Find task
    final task = _tasksById[taskId];
    if (task == null) return false;

    // Cannot cancel tasks that are already running or completed
    if (task.status == TaskStatus.running ||
        task.status == TaskStatus.completed ||
        task.status == TaskStatus.failed) {
      return false;
    }

    // Update task status
    task.status = TaskStatus.cancelled;

    // Remove from queue
    for (final queue in _taskQueues.values) {
      queue.remove(task);
    }

    // Call cancellation callback
    if (task.onCancel != null) {
      try {
        task.onCancel!();
      } catch (e) {
        _logger.error('Error in cancel callback for task ${task.id}: $e');
      }
    }

    // Complete completer with error
    if (!task.completer.isCompleted) {
      task.completer.completeError(
          TaskCancelledException('Task cancelled explicitly: $taskId'));
    }

    _logger.debug('Cancelled task: $taskId');
    return true;
  }

  /// Process task queue
  void _processQueue() async {
    // Don't process if scheduler is stopped or max concurrency reached
    if (!_isRunning || _runningTasks.length >= _maxConcurrency) {
      return;
    }

    // Calculate available resources
    final availableResources = Map<String, double>.from(_resourcePool);
    for (final task in _runningTasks) {
      for (final entry in task.requiredResources.entries) {
        final resource = entry.key;
        final amount = entry.value;

        availableResources[resource] =
            (availableResources[resource] ?? 0.0) - amount;
      }
    }

    // Prepare to execute tasks
    while (_isRunning &&
        _runningTasks.length < _maxConcurrency &&
        _getCurrentQueue().isNotEmpty) {
      // Select next task
      final task = _getCurrentQueue().first;

      // Check dependencies
      if (!_areDependenciesMet(task)) {
        // Dependencies not met, skip this task
        _getCurrentQueue().removeFirst();
        continue;
      }

      // Check resource sufficiency
      bool hasEnoughResources = true;
      for (final entry in task.requiredResources.entries) {
        final resource = entry.key;
        final amount = entry.value;

        if ((availableResources[resource] ?? 0.0) < amount) {
          hasEnoughResources = false;
          break;
        }
      }

      if (!hasEnoughResources) {
        // Not enough resources for this task, consider next task
        break;
      }

      // Remove and execute task
      _getCurrentQueue().removeFirst();
      _runningTasks.add(task);

      // Allocate resources
      for (final entry in task.requiredResources.entries) {
        final resource = entry.key;
        final amount = entry.value;

        availableResources[resource] =
            (availableResources[resource] ?? 0.0) - amount;
      }

      // Execute task
      _executeTask(task);
    }
  }

  /// Execute task
  void _executeTask(AdvancedLlmTask task) async {
    // Update task status
    task.status = TaskStatus.running;
    task.startedAt = DateTime.now();

    _logger.debug('Starting task ${task.id} in category ${task.category}');

    // Start performance monitoring
    final requestId = _performanceMonitor.startRequest(task.category);

    try {
      // Execute task
      final result = await task.task();

      // Handle task completion
      _completeTask(task, result, true);

      // End performance monitoring
      _performanceMonitor.endRequest(requestId, success: true);
    } catch (e, stackTrace) {
      _logger.error('Error executing task ${task.id}: $e');
      _logger.debug('Stack trace: $stackTrace');

      // Check if retry is possible
      if (task.canRetry) {
        _retryTask(task, e);
      } else {
        // Handle failure
        _completeTask(task, e, false);
      }

      // Record failure in performance monitoring
      _performanceMonitor.endRequest(requestId, success: false);
    }
  }

  /// Handle task completion
  void _completeTask(AdvancedLlmTask task, dynamic result, bool success) {
    // Remove from running tasks
    _runningTasks.remove(task);

    // Update task status
    task.status = success ? TaskStatus.completed : TaskStatus.failed;
    task.completedAt = DateTime.now();

    // Complete completer
    if (!task.completer.isCompleted) {
      if (success) {
        task.completer.complete(result);
      } else {
        task.completer.completeError(result);
      }
    }

    // Call completion callback
    if (_onTaskComplete != null) {
      try {
        _onTaskComplete(task, result);
      } catch (e) {
        _logger.error('Error in task completion callback: $e');
      }
    }

    // Record completed task
    _completedTasks.addLast(task);
    while (_completedTasks.length > _maxCompletedTasksHistory) {
      _completedTasks.removeFirst();
    }

    // Process dependent tasks
    _processDependentTasks(task.id);

    // Continue processing queue
    _processQueue();
  }

  /// Retry task
  void _retryTask(AdvancedLlmTask task, dynamic error) {
    task.retryCount++;

    // Calculate delay before retry
    final delay = _retryStrategy.getDelayForRetry(task.retryCount);

    _logger.debug(
        'Scheduling retry ${task.retryCount}/${task.maxRetries} for task ${task.id} '
        'after ${delay.inMilliseconds}ms');

    // Schedule retry
    Future.delayed(delay, () {
      // Check if scheduler is still running
      if (!_isRunning) return;

      // Reset task status
      task.status = TaskStatus.pending;

      // Add task back to queue
      _addToQueue(task);

      // Start processing queue
      _processQueue();
    });
  }

  /// Process dependent tasks
  void _processDependentTasks(String taskId) {
    final dependentTasks = _dependencyGraph[taskId];
    if (dependentTasks == null || dependentTasks.isEmpty) return;

    for (final depTaskId in dependentTasks) {
      final depTask = _tasksById[depTaskId];
      if (depTask == null) continue;

      // Check if dependencies are met
      if (_areDependenciesMet(depTask) &&
          depTask.status == TaskStatus.pending) {
        // Add waiting task with met dependencies to queue
        _addToQueue(depTask);
      }
    }
  }

  /// Cancel all pending tasks
  void clearQueue() {
    int taskCount = 0;

    // Cancel tasks in all priority queues
    for (final queue in _taskQueues.values) {
      taskCount += queue.length;

      final tasks = <AdvancedLlmTask>[];
      while (queue.isNotEmpty) {
        tasks.add(queue.removeFirst());
      }

      // Handle task cancellation
      for (final task in tasks) {
        task.status = TaskStatus.cancelled;

        // Call cancellation callback
        if (task.onCancel != null) {
          try {
            task.onCancel!();
          } catch (e) {
            _logger.error('Error in cancel callback for task ${task.id}: $e');
          }
        }

        if (!task.completer.isCompleted) {
          task.completer.completeError(
              TaskCancelledException('Task cancelled by queue clear'));
        }
      }
    }

    _logger.debug('Cleared $taskCount pending tasks from queues');
  }

  /// Get task statistics
  Map<String, Map<String, dynamic>> getTaskStats() {
    // Statistics by category
    final categoryStats = <String, Map<String, dynamic>>{};

    // Statistics for waiting tasks - modified PriorityQueue traversal
    final queue = _getCurrentQueue();
    final List<AdvancedLlmTask> tempTasks = [];

    // Extract all tasks from queue to temporary list
    while (queue.isNotEmpty) {
      tempTasks.add(queue.removeFirst());
    }

    // Collect statistics from temporary list
    for (final task in tempTasks) {
      categoryStats.putIfAbsent(task.category, () => _createEmptyStats());
      categoryStats[task.category]!['queued'] =
          (categoryStats[task.category]!['queued'] as int) + 1;
    }

    // Add tasks back to queue
    for (final task in tempTasks) {
      queue.add(task);
    }

    // Statistics for running tasks
    for (final task in _runningTasks) {
      categoryStats.putIfAbsent(task.category, () => _createEmptyStats());
      categoryStats[task.category]!['running'] =
          (categoryStats[task.category]!['running'] as int) + 1;
    }

    // Statistics for completed tasks
    for (final task in _completedTasks) {
      categoryStats.putIfAbsent(task.category, () => _createEmptyStats());

      // Success/failure statistics
      if (task.status == TaskStatus.completed) {
        categoryStats[task.category]!['completed'] =
            (categoryStats[task.category]!['completed'] as int) + 1;
      } else if (task.status == TaskStatus.failed) {
        categoryStats[task.category]!['failed'] =
            (categoryStats[task.category]!['failed'] as int) + 1;
      } else if (task.status == TaskStatus.cancelled) {
        categoryStats[task.category]!['cancelled'] =
            (categoryStats[task.category]!['cancelled'] as int) + 1;
      }

      // Calculate average execution time
      if (task.startedAt != null && task.completedAt != null) {
        final execTime =
            task.completedAt!.difference(task.startedAt!).inMilliseconds;

        categoryStats[task.category]!['total_exec_time'] =
            (categoryStats[task.category]!['total_exec_time'] as int) +
                execTime;
        categoryStats[task.category]!['exec_count'] =
            (categoryStats[task.category]!['exec_count'] as int) + 1;
      }
    }

    // Calculate averages
    for (final entry in categoryStats.entries) {
      final stats = entry.value;
      final execCount = stats['exec_count'] as int;

      if (execCount > 0) {
        stats['avg_exec_time_ms'] =
            (stats['total_exec_time'] as int) / execCount;
      }

      // Remove temporary values used for average calculation
      stats.remove('total_exec_time');
      stats.remove('exec_count');
    }

    return categoryStats;
  }

  /// Create empty stats map
  Map<String, dynamic> _createEmptyStats() {
    return {
      'queued': 0,
      'running': 0,
      'completed': 0,
      'failed': 0,
      'cancelled': 0,
      'total_exec_time': 0,
      'exec_count': 0,
    };
  }

  /// Get specific task info by ID
  Map<String, dynamic>? getTaskInfo(String taskId) {
    final task = _tasksById[taskId];
    if (task == null) return null;

    return {
      'id': task.id,
      'category': task.category,
      'status': task.status.toString().split('.').last,
      'priority': task.priority,
      'created_at': task.createdAt.toIso8601String(),
      'started_at': task.startedAt?.toIso8601String(),
      'completed_at': task.completedAt?.toIso8601String(),
      'waiting_time_ms': task.getWaitingTime().inMilliseconds,
      'execution_time_ms': task.getExecutionTime()?.inMilliseconds,
      'deadline': task.deadline?.toIso8601String(),
      'dependencies': task.dependencies,
      'retry_count': task.retryCount,
      'max_retries': task.maxRetries,
      'required_resources': task.requiredResources,
      'metadata': task.metadata,
    };
  }

  /// Change resource allocation
  void updateResourcePool(Map<String, double> newResources) {
    _resourcePool.clear();
    _resourcePool.addAll(newResources);

    // Restart queue processing
    if (_isRunning) {
      _processQueue();
    }
  }
}

/// Retry strategy
class RetryStrategy {
  /// Base delay
  final Duration baseDelay;

  /// Exponential multiplier
  final double factor;

  /// Random factor
  final double jitter;

  /// Maximum delay
  final Duration maxDelay;

  RetryStrategy({
    this.baseDelay = const Duration(milliseconds: 500),
    this.factor = 2.0,
    this.jitter = 0.2,
    this.maxDelay = const Duration(seconds: 30),
  });

  /// Calculate delay based on retry count
  Duration getDelayForRetry(int retryCount) {
    // Calculate exponential backoff
    final delay = baseDelay.inMilliseconds * pow(factor, retryCount - 1);

    // Apply jitter (random factor)
    final jitterAmount = delay * jitter * (Random().nextDouble() * 2 - 1);
    final finalDelay = delay + jitterAmount;

    // Cap at maximum delay
    final cappedDelay = min(finalDelay, maxDelay.inMilliseconds).toInt();

    return Duration(milliseconds: cappedDelay);
  }
}
