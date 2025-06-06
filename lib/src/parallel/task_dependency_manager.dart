import 'dart:async';

import '../utils/logger.dart';

/// Task node
class TaskNode<T> {
  /// Task ID
  final String id;

  /// Task name
  final String name;

  /// Task execution function
  final Future<T> Function() task;

  /// Completion status
  bool completed = false;

  /// Running status
  bool running = false;

  /// Result value
  T? result;

  /// Completion completer
  final Completer<T> completer = Completer<T>();

  /// Task dependency list (IDs)
  final Set<String> dependencies = {};

  /// List of tasks dependent on this task (IDs)
  final Set<String> dependents = {};

  TaskNode({
    required this.id,
    required this.name,
    required this.task,
  });

  /// Whether task is completed
  bool get isCompleted => completed;

  /// Whether task is running
  bool get isRunning => running;

  /// Future to wait for completion
  Future<T> get future => completer.future;
}

/// Task dependency manager
class TaskDependencyManager<T> {
  /// Task map
  final Map<String, TaskNode<T>> _tasks = {};

  /// Task graph
  final Graph<String> _graph = Graph<String>();

  /// Logging
  final Logger _logger = Logger('mcp_llm.task_dependency_manager');

  /// Maximum concurrent task execution count
  final int _maxConcurrency;

  /// Running task count
  int _runningCount = 0;

  /// Constructor
  TaskDependencyManager({
    int maxConcurrency = 5,
  }) : _maxConcurrency = maxConcurrency;

  /// Register task
  void registerTask(
    String id,
    String name,
    Future<T> Function() task, {
    List<String> dependencies = const [],
  }) {
    if (_tasks.containsKey(id)) {
      throw Exception('Task with ID $id already exists');
    }

    final taskNode = TaskNode<T>(
      id: id,
      name: name,
      task: task,
    );

    // Set dependencies
    for (final depId in dependencies) {
      if (!_tasks.containsKey(depId)) {
        throw Exception('Dependency task $depId does not exist');
      }

      taskNode.dependencies.add(depId);
      _tasks[depId]!.dependents.add(id);
    }

    // Register task
    _tasks[id] = taskNode;
    _graph.addNode(id);

    // Add dependency edges
    for (final depId in dependencies) {
      _graph.addEdge(depId, id);
    }

    _logger
        .debug('Registered task: $id with ${dependencies.length} dependencies');

    // Check for cyclic dependencies
    if (_detectCycle()) {
      // Rollback recently added task
      _tasks.remove(id);
      _graph.removeNode(id);

      throw Exception('Adding task $id would create a cyclic dependency');
    }
  }

  /// Check for cyclic dependencies
  bool _detectCycle() {
    final visited = <String>{};
    final recursionStack = <String>{};

    for (final nodeId in _graph.nodes) {
      if (_isCyclicUtil(nodeId, visited, recursionStack)) {
        return true;
      }
    }

    return false;
  }

  /// Cyclic dependency utility function
  bool _isCyclicUtil(
      String nodeId, Set<String> visited, Set<String> recursionStack) {
    // If already visited, no cycle
    if (visited.contains(nodeId)) return false;

    // Mark current node as visited
    visited.add(nodeId);
    recursionStack.add(nodeId);

    // Check adjacent nodes
    for (final adjId in _graph.getEdges(nodeId)) {
      // If adjacent node is in recursion stack, cycle found
      if (recursionStack.contains(adjId)) {
        return true;
      }

      // Check for cycles from adjacent node
      if (!visited.contains(adjId) &&
          _isCyclicUtil(adjId, visited, recursionStack)) {
        return true;
      }
    }

    // Remove from recursion stack
    recursionStack.remove(nodeId);

    return false;
  }

  /// Execute all tasks
  Future<Map<String, T>> executeAll() async {
    // Find executable tasks
    final readyTasks = _findReadyTasks();

    // Execute all ready tasks
    for (final taskId in readyTasks) {
      _executeTask(taskId);
    }

    // Wait for all tasks to complete
    final futures = _tasks.values.map((task) => task.future);
    await Future.wait(futures);

    // Collect results
    final results = <String, T>{};
    for (final entry in _tasks.entries) {
      final result = entry.value.result;
      if (result != null) {
        results[entry.key] = result;
      }
    }

    return results;
  }

  /// Find executable tasks
  Set<String> _findReadyTasks() {
    final readyTasks = <String>{};

    for (final entry in _tasks.entries) {
      final taskId = entry.key;
      final task = entry.value;

      // Skip if already completed or running
      if (task.isCompleted || task.isRunning) continue;

      // Ready if no dependencies or all dependencies completed
      if (task.dependencies.isEmpty ||
          task.dependencies.every((depId) => _tasks[depId]!.isCompleted)) {
        readyTasks.add(taskId);
      }
    }

    return readyTasks;
  }

  /// Execute task
  void _executeTask(String taskId) {
    // Check concurrency limit
    if (_runningCount >= _maxConcurrency) {
      // Queue for later execution
      _logger.debug('Delaying task $taskId due to concurrency limit');
      return;
    }

    final task = _tasks[taskId]!;

    // Ignore if already running or completed
    if (task.isRunning || task.isCompleted) return;

    // Set task running state
    task.running = true;
    _runningCount++;

    _logger.debug('Executing task: $taskId');

    // Execute task asynchronously
    task.task().then((result) {
      // Save result
      task.result = result;
      task.completed = true;
      task.running = false;
      _runningCount--;

      // Complete completer
      if (!task.completer.isCompleted) {
        task.completer.complete(result);
      }

      _logger.debug('Task completed: $taskId');

      // Check dependent tasks
      _checkDependents(taskId);
    }).catchError((error, stackTrace) {
      // Handle error
      task.running = false;
      _runningCount--;

      _logger.error('Task $taskId failed: $error');
      _logger.debug('Stack trace: $stackTrace');

      // Forward error to completer
      if (!task.completer.isCompleted) {
        task.completer.completeError(error, stackTrace);
      }
    });
  }

  /// Check dependent tasks
  void _checkDependents(String taskId) {
    final task = _tasks[taskId]!;

    // Check all tasks dependent on this task
    for (final depTaskId in task.dependents) {
      final depTask = _tasks[depTaskId]!;

      // Check if all dependencies are completed
      if (!depTask.isRunning &&
          !depTask.isCompleted &&
          depTask.dependencies.every((id) => _tasks[id]!.isCompleted)) {
        // Execute ready dependent task
        _executeTask(depTaskId);
      }
    }
  }

  /// Execute specific task
  Future<T> executeTask(String taskId) async {
    if (!_tasks.containsKey(taskId)) {
      throw Exception('Task $taskId does not exist');
    }

    final task = _tasks[taskId]!;

    // Return result if already completed
    if (task.isCompleted) {
      return task.result!;
    }

    // Wait if already running
    if (task.isRunning) {
      return task.future;
    }

    // Check dependencies
    for (final depId in task.dependencies) {
      if (!_tasks[depId]!.isCompleted) {
        await executeTask(depId);
      }
    }

    // Execute task
    _executeTask(taskId);

    // Wait for completion
    return task.future;
  }

  /// Get task status
  Map<String, Map<String, dynamic>> getTasksStatus() {
    final result = <String, Map<String, dynamic>>{};

    for (final entry in _tasks.entries) {
      final taskId = entry.key;
      final task = entry.value;

      result[taskId] = {
        'name': task.name,
        'status': task.isCompleted
            ? 'completed'
            : (task.isRunning ? 'running' : 'pending'),
        'dependencies': task.dependencies.toList(),
        'dependents': task.dependents.toList(),
        'has_result': task.result != null,
      };
    }

    return result;
  }

  /// Get topological sort order
  List<String> getTopologicalOrder() {
    return _graph.topologicalSort();
  }

  /// Get result of specific task
  T? getTaskResult(String taskId) {
    if (!_tasks.containsKey(taskId) || !_tasks[taskId]!.isCompleted) {
      return null;
    }

    return _tasks[taskId]!.result;
  }
}

/// Graph class
class Graph<T> {
  /// Node set
  final Set<T> _nodes = {};

  /// Edge map
  final Map<T, Set<T>> _edges = {};

  /// Reverse edge map
  final Map<T, Set<T>> _reverseEdges = {};

  /// Add node
  void addNode(T node) {
    _nodes.add(node);
    _edges.putIfAbsent(node, () => {});
    _reverseEdges.putIfAbsent(node, () => {});
  }

  /// Remove node
  void removeNode(T node) {
    // Remove outgoing edges from node
    final outgoing = _edges.remove(node) ?? {};
    for (final target in outgoing) {
      _reverseEdges[target]?.remove(node);
    }

    // Remove incoming edges to node
    final incoming = _reverseEdges.remove(node) ?? {};
    for (final source in incoming) {
      _edges[source]?.remove(node);
    }

    // Remove node
    _nodes.remove(node);
  }

  /// Add edge
  void addEdge(T from, T to) {
    if (!_nodes.contains(from) || !_nodes.contains(to)) {
      throw Exception('Nodes must be added to the graph first');
    }

    _edges[from]!.add(to);
    _reverseEdges[to]!.add(from);
  }

  /// Remove edge
  void removeEdge(T from, T to) {
    _edges[from]?.remove(to);
    _reverseEdges[to]?.remove(from);
  }

  /// Get outgoing edges from node
  Set<T> getEdges(T node) {
    return _edges[node] ?? {};
  }

  /// Get incoming edges to node
  Set<T> getReverseEdges(T node) {
    return _reverseEdges[node] ?? {};
  }

  /// Get all nodes
  Set<T> get nodes => Set.from(_nodes);

  /// Perform topological sort
  List<T> topologicalSort() {
    final result = <T>[];
    final visitedNodes = <T>{};
    final temporaryMarks = <T>{};

    // Visit all nodes
    void visit(T node) {
      // If already temporarily marked, cyclic dependency
      if (temporaryMarks.contains(node)) {
        throw Exception('Graph contains a cycle');
      }

      // Process if not yet visited
      if (!visitedNodes.contains(node)) {
        temporaryMarks.add(node);

        // Visit neighbors first
        for (final neighbor in getEdges(node)) {
          visit(neighbor);
        }

        // Node processing complete
        temporaryMarks.remove(node);
        visitedNodes.add(node);
        result.add(node);
      }
    }

    // Try to visit all nodes
    for (final node in _nodes) {
      if (!visitedNodes.contains(node)) {
        visit(node);
      }
    }

    // Reverse result (source nodes
    final List<T> reversed = result.reversed.toList();
    return reversed;
  }
}
