/// Storage Provider Tests
///
/// Tests for BinaryStorageProvider interface, base class, and implementations.
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:mcp_bundle/ports.dart' as bundle;
import 'package:mcp_llm/mcp_llm.dart';

import 'test_utils/mock_extension_providers.dart';

void main() {
  group('BinaryStorageProvider', () {
    group('MockBinaryStorageProvider', () {
      late MockBinaryStorageProvider provider;

      setUp(() {
        provider = MockBinaryStorageProvider();
      });

      tearDown(() async {
        await provider.close();
      });

      test('has correct id', () {
        expect(provider.id, equals('mock-storage'));
      });

      test('is not available before initialization', () async {
        expect(await provider.isAvailable(), isFalse);
      });

      test('is available after initialization', () async {
        await provider.initialize(
          const StorageProviderConfig(
            accessKey: 'test-key',
            bucket: 'test-bucket',
          ),
        );
        expect(await provider.isAvailable(), isTrue);
      });

      test('is not available after close', () async {
        await provider.initialize(
          const StorageProviderConfig(
            accessKey: 'test-key',
            bucket: 'test-bucket',
          ),
        );
        await provider.close();
        expect(await provider.isAvailable(), isFalse);
      });

      group('store', () {
        setUp(() async {
          await provider.initialize(
            const StorageProviderConfig(
              accessKey: 'test-key',
              bucket: 'test-bucket',
            ),
          );
        });

        test('stores data and returns reference', () async {
          final data = bytesToStream([1, 2, 3, 4, 5]);

          final reference = await provider.store(data, 'application/octet-stream');

          expect(reference, isNotEmpty);
          expect(reference, contains('mock://'));
        });

        test('stores data with prefix option', () async {
          final data = bytesToStream([1, 2, 3]);
          const options = bundle.StorageOptions(prefix: 'test-prefix/');

          final reference = await provider.store(data, 'text/plain', options);

          expect(reference, startsWith('test-prefix/'));
        });

        test('throws when configured to fail', () async {
          provider.setFailure(true);
          final data = bytesToStream([1, 2, 3]);

          expect(
            () => provider.store(data, 'application/octet-stream'),
            throwsA(isA<StorageProviderException>()),
          );
        });
      });

      group('retrieve', () {
        late String reference;
        final testData = Uint8List.fromList([1, 2, 3, 4, 5]);

        setUp(() async {
          await provider.initialize(
            const StorageProviderConfig(
              accessKey: 'test-key',
              bucket: 'test-bucket',
            ),
          );
          reference = await provider.store(
            bytesToStream(testData),
            'application/octet-stream',
          );
        });

        test('retrieves stored data', () async {
          final retrieved = await provider.retrieve(reference);

          expect(retrieved, equals(testData));
        });

        test('throws for non-existent reference', () async {
          expect(
            () => provider.retrieve('non-existent'),
            throwsA(isA<StorageProviderException>()),
          );
        });

        test('throws when configured to fail', () async {
          provider.setFailure(true);

          expect(
            () => provider.retrieve(reference),
            throwsA(isA<StorageProviderException>()),
          );
        });
      });

      group('exists', () {
        late String reference;

        setUp(() async {
          await provider.initialize(
            const StorageProviderConfig(
              accessKey: 'test-key',
              bucket: 'test-bucket',
            ),
          );
          reference = await provider.store(
            bytesToStream([1, 2, 3]),
            'application/octet-stream',
          );
        });

        test('returns true for existing reference', () async {
          expect(await provider.exists(reference), isTrue);
        });

        test('returns false for non-existent reference', () async {
          expect(await provider.exists('non-existent'), isFalse);
        });
      });

      group('metadata', () {
        late String reference;

        setUp(() async {
          await provider.initialize(
            const StorageProviderConfig(
              accessKey: 'test-key',
              bucket: 'test-bucket',
            ),
          );
          reference = await provider.store(
            bytesToStream([1, 2, 3, 4, 5]),
            'text/plain',
          );
        });

        test('returns metadata for existing reference', () async {
          final metadata = await provider.metadata(reference);

          expect(metadata, isNotNull);
          expect(metadata!.key, equals(reference));
          expect(metadata.mimeType, equals('text/plain'));
          expect(metadata.size, equals(5));
          expect(metadata.sha256, isNotEmpty);
          expect(metadata.createdAt, isNotNull);
        });

        test('returns null for non-existent reference', () async {
          final metadata = await provider.metadata('non-existent');

          expect(metadata, isNull);
        });
      });

      group('delete', () {
        late String reference;

        setUp(() async {
          await provider.initialize(
            const StorageProviderConfig(
              accessKey: 'test-key',
              bucket: 'test-bucket',
            ),
          );
          reference = await provider.store(
            bytesToStream([1, 2, 3]),
            'application/octet-stream',
          );
        });

        test('deletes existing reference', () async {
          expect(await provider.exists(reference), isTrue);

          final deleted = await provider.delete(reference);

          expect(deleted, isTrue);
          expect(await provider.exists(reference), isFalse);
        });

        test('throws when configured to fail', () async {
          provider.setFailure(true);

          expect(
            () => provider.delete(reference),
            throwsA(isA<StorageProviderException>()),
          );
        });
      });

      group('list', () {
        setUp(() async {
          await provider.initialize(
            const StorageProviderConfig(
              accessKey: 'test-key',
              bucket: 'test-bucket',
            ),
          );
          await provider.store(
            bytesToStream([1]),
            'text/plain',
            const bundle.StorageOptions(prefix: 'prefix1/'),
          );
          await provider.store(
            bytesToStream([2]),
            'text/plain',
            const bundle.StorageOptions(prefix: 'prefix1/'),
          );
          await provider.store(
            bytesToStream([3]),
            'text/plain',
            const bundle.StorageOptions(prefix: 'prefix2/'),
          );
        });

        test('lists all references without prefix', () async {
          final references = await provider.list();

          expect(references.length, equals(3));
        });

        test('lists references with prefix', () async {
          final references = await provider.list('prefix1/');

          expect(references.length, equals(2));
          expect(references, everyElement(startsWith('prefix1/')));
        });

        test('returns empty list for non-matching prefix', () async {
          final references = await provider.list('non-existent/');

          expect(references, isEmpty);
        });
      });
    });

    group('StorageProviderConfig', () {
      test('creates config with required parameters', () {
        const config = StorageProviderConfig(
          accessKey: 'test-key',
          bucket: 'test-bucket',
        );

        expect(config.accessKey, equals('test-key'));
        expect(config.bucket, equals('test-bucket'));
        expect(config.secretKey, isNull);
        expect(config.region, isNull);
        expect(config.projectId, isNull);
        expect(config.timeout, equals(const Duration(seconds: 60)));
        expect(config.maxRetries, equals(3));
      });

      test('creates config with all parameters', () {
        const config = StorageProviderConfig(
          accessKey: 'test-key',
          secretKey: 'secret-key',
          bucket: 'test-bucket',
          region: 'us-east-1',
          projectId: 'my-project',
          timeout: Duration(seconds: 120),
          maxRetries: 5,
        );

        expect(config.accessKey, equals('test-key'));
        expect(config.secretKey, equals('secret-key'));
        expect(config.bucket, equals('test-bucket'));
        expect(config.region, equals('us-east-1'));
        expect(config.projectId, equals('my-project'));
        expect(config.timeout, equals(const Duration(seconds: 120)));
        expect(config.maxRetries, equals(5));
      });
    });

    group('StorageProviderException', () {
      test('creates exception with message', () {
        final exception = StorageProviderException('Test error');

        expect(exception.message, equals('Test error'));
        expect(exception.cause, isNull);
        expect(exception.toString(), contains('Test error'));
      });

      test('creates exception with message and cause', () {
        final cause = Exception('Original error');
        final exception = StorageProviderException('Test error', cause);

        expect(exception.message, equals('Test error'));
        expect(exception.cause, equals(cause));
        expect(exception.toString(), contains('Test error'));
        expect(exception.toString(), contains('Original error'));
      });
    });

    group('BaseBinaryStorageProvider', () {
      test('collectBytes collects stream into Uint8List', () async {
        final provider = _TestStorageProvider();
        await provider.initialize(
          const StorageProviderConfig(
            accessKey: 'test-key',
            bucket: 'test-bucket',
          ),
        );

        final stream = bytesToStream([1, 2, 3, 4, 5]);
        final bytes = await provider.testCollectBytes(stream);

        expect(bytes, equals(Uint8List.fromList([1, 2, 3, 4, 5])));
      });

      test('generateHash generates consistent hash', () async {
        final provider = _TestStorageProvider();

        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final hash1 = provider.testGenerateHash(data);
        final hash2 = provider.testGenerateHash(data);

        expect(hash1, equals(hash2));
      });

      test('generateHash generates different hash for different data', () async {
        final provider = _TestStorageProvider();

        final data1 = Uint8List.fromList([1, 2, 3]);
        final data2 = Uint8List.fromList([4, 5, 6]);
        final hash1 = provider.testGenerateHash(data1);
        final hash2 = provider.testGenerateHash(data2);

        expect(hash1, isNot(equals(hash2)));
      });

      test('config throws when not initialized', () {
        final provider = _TestStorageProvider();

        expect(
          () => provider.testGetConfig(),
          throwsA(isA<StateError>()),
        );
      });

      test('config returns value after initialization', () async {
        final provider = _TestStorageProvider();
        const expectedConfig = StorageProviderConfig(
          accessKey: 'test-key',
          bucket: 'test-bucket',
        );
        await provider.initialize(expectedConfig);

        final config = provider.testGetConfig();

        expect(config.accessKey, equals('test-key'));
        expect(config.bucket, equals('test-bucket'));
      });
    });
  });

  group('BinaryStoragePortAdapter', () {
    late MockBinaryStorageProvider mockProvider;
    late BinaryStoragePortAdapter adapter;

    setUp(() async {
      mockProvider = MockBinaryStorageProvider();
      await mockProvider.initialize(
        const StorageProviderConfig(
          accessKey: 'test-key',
          bucket: 'test-bucket',
        ),
      );
      adapter = BinaryStoragePortAdapter(mockProvider);
    });

    tearDown(() async {
      await mockProvider.close();
    });

    test('implements bundle.BinaryStoragePort', () {
      expect(adapter, isA<bundle.BinaryStoragePort>());
    });

    test('store delegates to provider', () async {
      final data = bytesToStream([1, 2, 3]);

      final reference = await adapter.store(data, 'text/plain');

      expect(reference, isNotEmpty);
    });

    test('retrieve delegates to provider', () async {
      final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final reference = await adapter.store(
        bytesToStream(testData),
        'application/octet-stream',
      );

      final retrieved = await adapter.retrieve(reference);

      expect(retrieved, equals(testData));
    });

    test('exists delegates to provider', () async {
      final reference = await adapter.store(
        bytesToStream([1, 2, 3]),
        'text/plain',
      );

      expect(await adapter.exists(reference), isTrue);
      expect(await adapter.exists('non-existent'), isFalse);
    });

    test('metadata delegates to provider', () async {
      final reference = await adapter.store(
        bytesToStream([1, 2, 3]),
        'text/plain',
      );

      final metadata = await adapter.metadata(reference);

      expect(metadata, isNotNull);
      expect(metadata!.mimeType, equals('text/plain'));
    });

    test('delete delegates to provider', () async {
      final reference = await adapter.store(
        bytesToStream([1, 2, 3]),
        'text/plain',
      );

      expect(await adapter.exists(reference), isTrue);
      await adapter.delete(reference);
      expect(await adapter.exists(reference), isFalse);
    });

    test('list delegates to provider', () async {
      await adapter.store(
        bytesToStream([1]),
        'text/plain',
        const bundle.StorageOptions(prefix: 'test/'),
      );

      final references = await adapter.list('test/');

      expect(references.length, equals(1));
    });

    test('can be used where bundle.BinaryStoragePort is expected', () async {
      Future<String> useStoragePort(bundle.BinaryStoragePort storage) async {
        return await storage.store(
          bytesToStream([1, 2, 3]),
          'text/plain',
        );
      }

      final reference = await useStoragePort(adapter);
      expect(reference, isNotEmpty);
    });
  });
}

/// Test implementation of BaseBinaryStorageProvider for testing base class methods.
class _TestStorageProvider extends BaseBinaryStorageProvider {
  @override
  String get id => 'test-storage';

  @override
  Future<String> store(
    Stream<List<int>> data,
    String mimeType, [
    bundle.StorageOptions options = const bundle.StorageOptions(),
  ]) async {
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> retrieve(String reference) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> exists(String reference) async {
    throw UnimplementedError();
  }

  @override
  Future<bundle.StorageMetadata?> metadata(String reference) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> delete(String reference) async {
    throw UnimplementedError();
  }

  @override
  Future<List<String>> list([String? prefix]) async {
    throw UnimplementedError();
  }

  /// Expose collectBytes for testing.
  Future<Uint8List> testCollectBytes(Stream<List<int>> stream) {
    return collectBytes(stream);
  }

  /// Expose generateHash for testing.
  String testGenerateHash(Uint8List data) {
    return generateHash(data);
  }

  /// Expose config getter for testing.
  StorageProviderConfig testGetConfig() => config;
}
