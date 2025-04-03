import 'dart:convert';
import 'dart:io';

import 'package:mcp_llm/mcp_llm.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;

void main() {
  group('MemoryStorage', () {
    late MemoryStorage storage;

    setUp(() {
      storage = MemoryStorage();
    });

    test('saveString and loadString work correctly', () async {
      await storage.saveString('testKey', 'test value');
      final result = await storage.loadString('testKey');

      expect(result, equals('test value'));
    });

    test('saveData and loadData work correctly', () async {
      final testData = utf8.encode('test binary data');
      await storage.saveData('dataKey', testData);
      final result = await storage.loadData('dataKey');

      expect(result, equals(testData));
    });

    test('saveObject and loadObject work correctly', () async {
      final testObject = {'name': 'Test', 'value': 123};
      await storage.saveObject('objectKey', testObject);
      final result = await storage.loadObject('objectKey');

      expect(result, equals(testObject));
    });

    test('exists returns correct values', () async {
      await storage.saveString('existingKey', 'value');

      expect(await storage.exists('existingKey'), isTrue);
      expect(await storage.exists('nonExistentKey'), isFalse);
    });

    test('delete works correctly', () async {
      await storage.saveString('keyToDelete', 'delete me');

      expect(await storage.delete('keyToDelete'), isTrue);
      expect(await storage.exists('keyToDelete'), isFalse);
      expect(await storage.delete('nonExistentKey'), isFalse);
    });

    test('clear removes all data', () async {
      await storage.saveString('key1', 'value1');
      await storage.saveString('key2', 'value2');

      await storage.clear();

      expect(await storage.listKeys(), isEmpty);
    });

    test('listKeys returns correct keys', () async {
      await storage.saveString('key1', 'value1');
      await storage.saveObject('key2', {'a': 1});
      await storage.saveData('key3', [1, 2, 3]);

      final keys = await storage.listKeys();

      expect(keys, containsAll(['key1', 'key2', 'key3']));
      expect(keys.length, equals(3));
    });

    test('listKeys with prefix works correctly', () async {
      await storage.saveString('test_1', 'value1');
      await storage.saveString('test_2', 'value2');
      await storage.saveString('other', 'value3');

      final keys = await storage.listKeys('test_');

      expect(keys, containsAll(['test_1', 'test_2']));
      expect(keys.length, equals(2));
    });
  });

  group('PersistentStorage', () {
    late PersistentStorage storage;
    late Directory tempDir;

    setUp(() async {
      // Create a temporary directory for testing
      tempDir = await Directory.systemTemp.createTemp('mcp_llm_test_');
      storage = PersistentStorage(tempDir.path);
    });

    tearDown(() async {
      // Clean up temporary directory
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saveString creates a file and loadString retrieves it', () async {
      await storage.saveString('fileKey', 'file content');

      final filePath = path.join(tempDir.path, 'fileKey.txt');
      expect(File(filePath).existsSync(), isTrue);

      final result = await storage.loadString('fileKey');
      expect(result, equals('file content'));
    });

    test('saveData creates a binary file and loadData retrieves it', () async {
      final binaryData = [1, 2, 3, 4, 5];
      await storage.saveData('binaryKey', binaryData);

      final filePath = path.join(tempDir.path, 'binaryKey.bin');
      expect(File(filePath).existsSync(), isTrue);

      final result = await storage.loadData('binaryKey');
      expect(result, equals(binaryData));
    });

    test('saveObject creates a JSON file and loadObject retrieves it', () async {
      final object = {'name': 'Test', 'values': [1, 2, 3]};
      await storage.saveObject('objectKey', object);

      final filePath = path.join(tempDir.path, 'objectKey.json');
      expect(File(filePath).existsSync(), isTrue);

      final result = await storage.loadObject('objectKey');
      expect(result, equals(object));
    });

    test('delete removes files', () async {
      await storage.saveString('toDelete', 'delete me');

      expect(await storage.delete('toDelete'), isTrue);
      expect(await storage.exists('toDelete'), isFalse);

      final filePath = path.join(tempDir.path, 'toDelete.txt');
      expect(File(filePath).existsSync(), isFalse);
    });

    test('backup and restore functionality', () async {
      // Create initial data
      await storage.saveString('key1', 'value1');
      await storage.saveObject('key2', {'a': 1, 'b': 2});

      // Create backup directory
      final backupDir = Directory(path.join(tempDir.path, 'backups'));
      if (!backupDir.existsSync()) {
        backupDir.createSync();
      }

      // Create backup
      final backupPath = await storage.createBackup(backupDir.path);
      expect(Directory(backupPath).existsSync(), isTrue);

      // Clear original storage
      await storage.clear();
      expect(await storage.loadString('key1'), isNull);

      // Restore from backup
      await storage.restoreFromBackup(backupPath);

      // Verify data restored
      expect(await storage.loadString('key1'), equals('value1'));
      expect(await storage.loadObject('key2'), equals({'a': 1, 'b': 2}));
    });
  });
}