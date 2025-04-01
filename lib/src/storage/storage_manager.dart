
/// Abstract interface for storage management
abstract class StorageManager {
  /// Save a raw string to storage
  Future<void> saveString(String key, String value);

  /// Load a string from storage
  Future<String?> loadString(String key);

  /// Save a binary data to storage
  Future<void> saveData(String key, List<int> data);

  /// Load binary data from storage
  Future<List<int>?> loadData(String key);

  /// Save an object to storage (serialized as JSON)
  Future<void> saveObject(String key, Map<String, dynamic> object);

  /// Load an object from storage
  Future<Map<String, dynamic>?> loadObject(String key);

  /// Check if a key exists in storage
  Future<bool> exists(String key);

  /// Delete an item from storage
  Future<bool> delete(String key);

  /// Clear all storage
  Future<void> clear();

  /// List all keys in storage
  Future<List<String>> listKeys([String? prefix]);
}
