import 'dart:convert';
import '../utils/logger.dart';
import 'storage_manager.dart';

/// In-memory implementation of StorageManager for testing and simple use cases
class MemoryStorage implements StorageManager {
  final Map<String, String> _stringStorage = {};
  final Map<String, List<int>> _dataStorage = {};
  final Logger _logger = Logger('mcp_llm.memory_storage');

  /// Create a new memory storage
  MemoryStorage();

  @override
  Future<void> saveString(String key, String value) async {
    _stringStorage[key] = value;
    _logger.debug('Saved string to key: $key');
  }

  @override
  Future<String?> loadString(String key) async {
    final value = _stringStorage[key];
    if (value != null) {
      _logger.debug('Loaded string from key: $key');
    } else {
      _logger.debug('Key not found: $key');
    }
    return value;
  }

  @override
  Future<void> saveData(String key, List<int> data) async {
    _dataStorage[key] = List<int>.from(data);
    _logger.debug('Saved data to key: $key (${data.length} bytes)');
  }

  @override
  Future<List<int>?> loadData(String key) async {
    final data = _dataStorage[key];
    if (data != null) {
      _logger.debug('Loaded data from key: $key (${data.length} bytes)');
    } else {
      _logger.debug('Key not found: $key');
    }
    return data != null ? List<int>.from(data) : null;
  }

  @override
  Future<void> saveObject(String key, Map<String, dynamic> object) async {
    final json = jsonEncode(object);
    await saveString(key, json);
    _logger.debug('Saved object to key: $key');
  }

  @override
  Future<Map<String, dynamic>?> loadObject(String key) async {
    final json = await loadString(key);
    if (json == null) return null;

    try {
      final object = jsonDecode(json) as Map<String, dynamic>;
      _logger.debug('Loaded object from key: $key');
      return object;
    } catch (e) {
      _logger.error('Error decoding JSON for key $key: $e');
      return null;
    }
  }

  @override
  Future<bool> exists(String key) async {
    return _stringStorage.containsKey(key) || _dataStorage.containsKey(key);
  }

  @override
  Future<bool> delete(String key) async {
    final existedInStrings = _stringStorage.remove(key) != null;
    final existedInData = _dataStorage.remove(key) != null;

    final existed = existedInStrings || existedInData;
    if (existed) {
      _logger.debug('Deleted key: $key');
    }

    return existed;
  }

  @override
  Future<void> clear() async {
    _stringStorage.clear();
    _dataStorage.clear();
    _logger.debug('Cleared all storage');
  }

  @override
  Future<List<String>> listKeys([String? prefix]) async {
    final allKeys = {..._stringStorage.keys, ..._dataStorage.keys};

    if (prefix != null) {
      return allKeys.where((key) => key.startsWith(prefix)).toList();
    }

    return allKeys.toList();
  }

  /// Get the total number of items in storage
  int get itemCount => _stringStorage.length + _dataStorage.length;

  /// Get the size of an item in bytes (approximate)
  Future<int> getItemSize(String key) async {
    if (_stringStorage.containsKey(key)) {
      return _stringStorage[key]!.length * 2; // Unicode chars can be 2 bytes
    } else if (_dataStorage.containsKey(key)) {
      return _dataStorage[key]!.length;
    }
    return 0;
  }

  /// Get total storage usage in bytes (approximate)
  Future<int> getTotalSize() async {
    int total = 0;

    // Calculate size of string storage
    for (final value in _stringStorage.values) {
      total += value.length * 2; // Unicode chars can be 2 bytes
    }

    // Calculate size of binary storage
    for (final data in _dataStorage.values) {
      total += data.length;
    }

    // Add approximate overhead for keys
    total += (_stringStorage.keys.join() + _dataStorage.keys.join()).length * 2;

    return total;
  }
}