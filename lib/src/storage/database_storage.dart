// lib/src/storage/database_storage.dart
import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as path;

import '../utils/logger.dart';
import '../utils/compression.dart';
import 'storage_manager.dart';

/// Database storage implementation (standard Dart compatible)
class DatabaseStorage implements StorageManager {
  final String _databaseName;
  final String _basePath;
  final Logger _logger = Logger('mcp_llm.database_storage');
  late Database _db;
  bool _isInitialized = false;

  // Compression options
  final CompressionOptions _compressionOptions;

  DatabaseStorage({
    required String databaseName,
    String? basePath,
    CompressionOptions? compressionOptions,
  })  : _databaseName = databaseName,
        _basePath = basePath ?? 'data',
        _compressionOptions = compressionOptions ?? CompressionOptions();

  /// Initialize storage
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Create database directory
      final dbDir = Directory(_basePath);
      if (!dbDir.existsSync()) {
        dbDir.createSync(recursive: true);
      }

      final dbPath = path.join(_basePath, '$_databaseName.db');

      // Open database
      _db = sqlite3.open(dbPath);

      // Create tables
      _db.execute('''
        CREATE TABLE IF NOT EXISTS storage (
          key TEXT PRIMARY KEY,
          value TEXT,
          binary_data BLOB,
          type TEXT NOT NULL,
          is_compressed INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');

      // Create indices
      _db.execute(
          'CREATE INDEX IF NOT EXISTS idx_storage_type ON storage (type)');
      _db.execute(
          'CREATE INDEX IF NOT EXISTS idx_storage_key_prefix ON storage (key)');

      _isInitialized = true;
      _logger.info('Database storage initialized at $dbPath');
    } catch (e) {
      _logger.error('Failed to initialize database storage: $e');
      rethrow;
    }
  }

  /// Check if storage is initialized
  void _checkInitialized() {
    if (!_isInitialized) {
      throw StateError(
          'Database storage not initialized. Call initialize() first.');
    }
  }

  @override
  Future<void> saveString(String key, String value) async {
    _checkInitialized();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      String finalValue = value;
      int isCompressed = 0;

      // String compression
      if (_compressionOptions.compressStrings &&
          value.length > _compressionOptions.minSizeForCompression) {
        finalValue = await DataCompressor.compressAndEncodeString(value);
        isCompressed = 1;
      }

      // Query previous creation time
      final existingResult =
          _db.select('SELECT created_at FROM storage WHERE key = ?', [key]);

      final createdAt = existingResult.isEmpty
          ? now
          : existingResult.first['created_at'] as int;

      // Save or update
      _db.execute(
          'INSERT OR REPLACE INTO storage (key, value, type, is_compressed, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [key, finalValue, 'string', isCompressed, createdAt, now]);

      _logger.debug('Saved string to key: $key (${value.length} chars)');
    } catch (e) {
      _logger.error('Error saving string to key $key: $e');
      rethrow;
    }
  }

  @override
  Future<String?> loadString(String key) async {
    _checkInitialized();

    try {
      final result = _db.select(
          'SELECT value, is_compressed FROM storage WHERE key = ? AND type = ?',
          [key, 'string']);

      if (result.isEmpty || result.first['value'] == null) {
        return null;
      }

      final isCompressed = (result.first['is_compressed'] as int) == 1;
      final value = result.first['value'] as String;

      // Decompress if needed
      if (isCompressed) {
        return await DataCompressor.decodeAndDecompressString(value);
      }

      return value;
    } catch (e) {
      _logger.error('Error loading string from key $key: $e');
      return null;
    }
  }

  @override
  Future<void> saveData(String key, List<int> data) async {
    _checkInitialized();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      List<int> finalData = data;
      int isCompressed = 0;

      // Binary data compression
      if (_compressionOptions.compressBinaryData &&
          data.length > _compressionOptions.minSizeForCompression) {
        finalData = await DataCompressor.compressData(data);
        isCompressed = 1;
      }

      // Query previous creation time
      final existingResult =
          _db.select('SELECT created_at FROM storage WHERE key = ?', [key]);

      final createdAt = existingResult.isEmpty
          ? now
          : existingResult.first['created_at'] as int;

      // Save or update
      _db.execute(
          'INSERT OR REPLACE INTO storage (key, binary_data, type, is_compressed, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [key, finalData, 'binary', isCompressed, createdAt, now]);

      _logger.debug('Saved data to key: $key (${data.length} bytes)');
    } catch (e) {
      _logger.error('Error saving data to key $key: $e');
      rethrow;
    }
  }

  @override
  Future<List<int>?> loadData(String key) async {
    _checkInitialized();

    try {
      final result = _db.select(
          'SELECT binary_data, is_compressed FROM storage WHERE key = ? AND type = ?',
          [key, 'binary']);

      if (result.isEmpty || result.first['binary_data'] == null) {
        return null;
      }

      final isCompressed = (result.first['is_compressed'] as int) == 1;
      final data = result.first['binary_data'] as List<int>;

      // Decompress if needed
      if (isCompressed) {
        return await DataCompressor.decompressData(data);
      }

      return data;
    } catch (e) {
      _logger.error('Error loading data from key $key: $e');
      return null;
    }
  }

  @override
  Future<void> saveObject(String key, Map<String, dynamic> object) async {
    _checkInitialized();

    try {
      final json = jsonEncode(object);
      await saveString(key, json);
      _logger.debug('Saved object to key: $key');
    } catch (e) {
      _logger.error('Error saving object to key $key: $e');
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>?> loadObject(String key) async {
    _checkInitialized();

    try {
      final json = await loadString(key);
      if (json == null) return null;

      final object = jsonDecode(json) as Map<String, dynamic>;
      _logger.debug('Loaded object from key: $key');
      return object;
    } catch (e) {
      _logger.error('Error loading object from key $key: $e');
      return null;
    }
  }

  @override
  Future<bool> exists(String key) async {
    _checkInitialized();

    try {
      final result =
          _db.select('SELECT 1 FROM storage WHERE key = ? LIMIT 1', [key]);

      return result.isNotEmpty;
    } catch (e) {
      _logger.error('Error checking if key $key exists: $e');
      return false;
    }
  }

  @override
  Future<bool> delete(String key) async {
    _checkInitialized();

    try {
      // First check if key exists
      final checkResult =
          _db.select('SELECT 1 FROM storage WHERE key = ? LIMIT 1', [key]);
      final exists = checkResult.isNotEmpty;

      if (exists) {
        // Delete if key exists
        final stmt = _db.prepare('DELETE FROM storage WHERE key = ?');
        stmt.execute([key]); // Returns void - cannot check result
        stmt.dispose();

        _logger.debug('Deleted key: $key');
        return true;
      }

      return false;
    } catch (e) {
      _logger.error('Error deleting key $key: $e');
      return false;
    }
  }

  @override
  Future<void> clear() async {
    _checkInitialized();

    try {
      _db.execute('DELETE FROM storage');
      _logger.debug('Cleared all storage');
    } catch (e) {
      _logger.error('Error clearing storage: $e');
      rethrow;
    }
  }

  @override
  Future<List<String>> listKeys([String? prefix]) async {
    _checkInitialized();

    try {
      if (prefix != null) {
        // Use prepared statement with parameter binding to prevent SQL injection
        final stmt = _db.prepare(
            'SELECT key FROM storage WHERE key LIKE ? ESCAPE "\\"');
        final result = stmt.select(['$prefix%']);
        stmt.dispose();

        return result.map((row) => row['key'] as String).toList();
      } else {
        final result = _db.select('SELECT key FROM storage');
        return result.map((row) => row['key'] as String).toList();
      }
    } catch (e) {
      _logger.error('Error listing keys with prefix $prefix: $e');
      return [];
    }
  }

  /// Get storage size
  Future<int> getStorageSize() async {
    _checkInitialized();

    try {
      final result = _db.select('''
        SELECT 
          SUM(LENGTH(IFNULL(value, ''))) + 
          SUM(LENGTH(IFNULL(binary_data, ''))) AS total_size 
        FROM storage
      ''');

      return (result.first['total_size'] as int?) ?? 0;
    } catch (e) {
      _logger.error('Error getting storage size: $e');
      return 0;
    }
  }

  /// Get size of specific key
  Future<int> getKeySize(String key) async {
    _checkInitialized();

    try {
      final result = _db.select('''
        SELECT 
          LENGTH(IFNULL(value, '')) + 
          LENGTH(IFNULL(binary_data, '')) AS size 
        FROM storage
        WHERE key = ?
      ''', [key]);

      if (result.isEmpty) return 0;
      return (result.first['size'] as int?) ?? 0;
    } catch (e) {
      _logger.error('Error getting key size for $key: $e');
      return 0;
    }
  }

  /// Close database
  Future<void> close() async {
    if (_isInitialized) {
      _db.dispose();
      _isInitialized = false;
      _logger.debug('Database storage closed');
    }
  }

  /// Create database backup
  Future<String> createBackup(String backupPath) async {
    _checkInitialized();

    try {
      // Check and create backup directory
      final backupDir = Directory(backupPath);
      if (!backupDir.existsSync()) {
        backupDir.createSync(recursive: true);
      }

      // Create backup filename with timestamp
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backupFile =
          path.join(backupPath, '${_databaseName}_backup_$timestamp.db');

      // WAL checkpoint before backup (apply all changes to main DB)
      _db.execute('PRAGMA wal_checkpoint(FULL)');

      // Create backup file
      _db.execute('VACUUM INTO ?', [backupFile]);

      _logger.info('Created database backup at: $backupFile');
      return backupFile;
    } catch (e) {
      _logger.error('Error creating database backup: $e');
      rethrow;
    }
  }

  /// Restore from backup
  Future<void> restoreFromBackup(String backupFile) async {
    // Close current database
    if (_isInitialized) {
      _db.dispose();
      _isInitialized = false;
    }

    try {
      // Original database file path
      final dbPath = path.join(_basePath, '$_databaseName.db');

      // Delete existing file
      final dbFile = File(dbPath);
      if (dbFile.existsSync()) {
        dbFile.deleteSync();
      }

      // Copy backup file
      File(backupFile).copySync(dbPath);

      // Reopen database
      _db = sqlite3.open(dbPath);
      _isInitialized = true;

      _logger.info('Restored database from backup: $backupFile');
    } catch (e) {
      _logger.error('Error restoring from backup: $e');
      rethrow;
    }
  }
}
