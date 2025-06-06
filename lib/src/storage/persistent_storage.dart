import 'dart:convert';
import 'dart:io';

import '../utils/logger.dart';
import 'storage_manager.dart';

/// File-based persistent storage implementation
class PersistentStorage implements StorageManager {
  /// Base directory path for storage
  final String basePath;

  /// Logger instance
  final Logger _logger = Logger('mcp_llm.plugin');

  /// Create a new persistent storage
  ///
  /// [basePath] - Directory path where files will be stored
  PersistentStorage(this.basePath) {
    // Ensure the directory exists
    final directory = Directory(basePath);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
      _logger.info('Created storage directory: $basePath');
    }
  }

  /// Get the file path for a string key
  String _getStringFilePath(String key) {
    // Convert key to a valid filename
    final safeKey = key.replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_');
    return '$basePath/$safeKey.txt';
  }

  /// Get the file path for a data key
  String _getDataFilePath(String key) {
    // Convert key to a valid filename
    final safeKey = key.replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_');
    return '$basePath/$safeKey.bin';
  }

  /// Get the file path for a JSON object key
  String _getJsonFilePath(String key) {
    // Convert key to a valid filename
    final safeKey = key.replaceAll(RegExp(r'[/\\?%*:|"<>]'), '_');
    return '$basePath/$safeKey.json';
  }

  @override
  Future<void> saveString(String key, String value) async {
    final file = File(_getStringFilePath(key));
    await file.writeAsString(value, flush: true);
    _logger.debug('Saved string to file: ${file.path}');
  }

  @override
  Future<String?> loadString(String key) async {
    final file = File(_getStringFilePath(key));

    if (!await file.exists()) {
      _logger.debug('String file not found: ${file.path}');
      return null;
    }

    try {
      final content = await file.readAsString();
      _logger.debug('Loaded string from file: ${file.path}');
      return content;
    } catch (e) {
      _logger.error('Error reading string from file ${file.path}: $e');
      return null;
    }
  }

  @override
  Future<void> saveData(String key, List<int> data) async {
    final file = File(_getDataFilePath(key));
    await file.writeAsBytes(data, flush: true);
    _logger.debug('Saved data to file: ${file.path} (${data.length} bytes)');
  }

  @override
  Future<List<int>?> loadData(String key) async {
    final file = File(_getDataFilePath(key));

    if (!await file.exists()) {
      _logger.debug('Data file not found: ${file.path}');
      return null;
    }

    try {
      final data = await file.readAsBytes();
      _logger.debug('Loaded data from file: ${file.path} (${data.length} bytes)');
      return data;
    } catch (e) {
      _logger.error('Error reading data from file ${file.path}: $e');
      return null;
    }
  }

  @override
  Future<void> saveObject(String key, Map<String, dynamic> object) async {
    final file = File(_getJsonFilePath(key));
    final json = jsonEncode(object);
    await file.writeAsString(json, flush: true);
    _logger.debug('Saved object to file: ${file.path}');
  }

  @override
  Future<Map<String, dynamic>?> loadObject(String key) async {
    final file = File(_getJsonFilePath(key));

    if (!await file.exists()) {
      _logger.debug('JSON file not found: ${file.path}');
      return null;
    }

    try {
      final json = await file.readAsString();
      final object = jsonDecode(json) as Map<String, dynamic>;
      _logger.debug('Loaded object from file: ${file.path}');
      return object;
    } catch (e) {
      _logger.error('Error reading object from file ${file.path}: $e');
      return null;
    }
  }

  @override
  Future<bool> exists(String key) async {
    final stringFile = File(_getStringFilePath(key));
    final dataFile = File(_getDataFilePath(key));
    final jsonFile = File(_getJsonFilePath(key));

    return await stringFile.exists() ||
        await dataFile.exists() ||
        await jsonFile.exists();
  }

  @override
  Future<bool> delete(String key) async {
    bool deleted = false;

    final stringFile = File(_getStringFilePath(key));
    if (await stringFile.exists()) {
      await stringFile.delete();
      deleted = true;
      _logger.debug('Deleted string file: ${stringFile.path}');
    }

    final dataFile = File(_getDataFilePath(key));
    if (await dataFile.exists()) {
      await dataFile.delete();
      deleted = true;
      _logger.debug('Deleted data file: ${dataFile.path}');
    }

    final jsonFile = File(_getJsonFilePath(key));
    if (await jsonFile.exists()) {
      await jsonFile.delete();
      deleted = true;
      _logger.debug('Deleted JSON file: ${jsonFile.path}');
    }

    return deleted;
  }

  @override
  Future<void> clear() async {
    final directory = Directory(basePath);
    if (await directory.exists()) {
      // Get all files
      final files = await directory.list().where((entity) => entity is File).toList();

      // Delete all files
      for (final file in files) {
        await (file as File).delete();
      }

      _logger.debug('Cleared all files in directory: $basePath');
    }
  }

  @override
  Future<List<String>> listKeys([String? prefix]) async {
    final directory = Directory(basePath);
    if (!await directory.exists()) {
      return [];
    }

    final Set<String> keys = {};

    // List all files in the directory
    await for (final entity in directory.list()) {
      if (entity is File) {
        final path = entity.path;
        final fileName = path.split('/').last;

        // Extract key from filename
        String key;
        if (fileName.endsWith('.txt')) {
          key = fileName.substring(0, fileName.length - 4);
        } else if (fileName.endsWith('.bin')) {
          key = fileName.substring(0, fileName.length - 4);
        } else if (fileName.endsWith('.json')) {
          key = fileName.substring(0, fileName.length - 5);
        } else {
          continue; // Skip unknown file types
        }

        if (prefix == null || key.startsWith(prefix)) {
          keys.add(key);
        }
      }
    }

    return keys.toList();
  }

  /// Get total storage directory size in bytes
  Future<int> getDirectorySize() async {
    final directory = Directory(basePath);
    if (!await directory.exists()) {
      return 0;
    }

    int totalSize = 0;

    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }

    return totalSize;
  }

  /// Create a backup of all data
  Future<String> createBackup(String backupPath) async {
    final sourceDir = Directory(basePath);
    final backupDir = Directory(backupPath);

    // Create backup directory if it doesn't exist
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    // Create a timestamp for the backup
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupName = 'backup_$timestamp';
    final backupDirPath = '$backupPath/$backupName';
    final backupDirFinal = Directory(backupDirPath);
    await backupDirFinal.create();

    // Copy all files
    await for (final entity in sourceDir.list()) {
      if (entity is File) {
        final fileName = entity.path.split('/').last;
        final targetPath = '$backupDirPath/$fileName';
        await entity.copy(targetPath);
      }
    }

    _logger.info('Created backup at: $backupDirPath');
    return backupDirPath;
  }

  /// Restore from a backup
  Future<void> restoreFromBackup(String backupPath) async {
    final backupDir = Directory(backupPath);
    if (!await backupDir.exists()) {
      throw FileSystemException('Backup directory does not exist', backupPath);
    }

    // Clear current storage
    await clear();

    // Copy all files from backup
    await for (final entity in backupDir.list()) {
      if (entity is File) {
        final fileName = entity.path.split('/').last;
        final targetPath = '$basePath/$fileName';
        await entity.copy(targetPath);
      }
    }

    _logger.info('Restored from backup: $backupPath');
  }
}