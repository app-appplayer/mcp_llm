/// Vision Provider Tests
///
/// Tests for VisionProvider interface, base class, and implementations.
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:mcp_bundle/ports.dart' as bundle;
import 'package:mcp_llm/mcp_llm.dart';

import 'test_utils/mock_extension_providers.dart';

void main() {
  group('VisionProvider', () {
    group('MockVisionProvider', () {
      late MockVisionProvider provider;

      setUp(() {
        provider = MockVisionProvider();
      });

      tearDown(() async {
        await provider.close();
      });

      test('has correct id', () {
        expect(provider.id, equals('mock-vision'));
      });

      test('is not available before initialization', () async {
        expect(await provider.isAvailable(), isFalse);
      });

      test('is available after initialization', () async {
        await provider.initialize(
          const VisionProviderConfig(apiKey: 'test-key'),
        );
        expect(await provider.isAvailable(), isTrue);
      });

      test('is not available after close', () async {
        await provider.initialize(
          const VisionProviderConfig(apiKey: 'test-key'),
        );
        await provider.close();
        expect(await provider.isAvailable(), isFalse);
      });

      test('describe returns result with description', () async {
        await provider.initialize(
          const VisionProviderConfig(apiKey: 'test-key'),
        );

        final imageData = bytesToStream([1, 2, 3, 4, 5]);
        final options = const bundle.VisionOptions();

        final result = await provider.describe(imageData, options);

        expect(result.description, isNotEmpty);
        expect(result.confidence, greaterThan(0));
        expect(result.processingTime, isNotNull);
      });

      test('describe returns custom description', () async {
        provider.setMockDescription('Custom test description');
        await provider.initialize(
          const VisionProviderConfig(apiKey: 'test-key'),
        );

        final imageData = bytesToStream([1, 2, 3]);
        final options = const bundle.VisionOptions();

        final result = await provider.describe(imageData, options);

        expect(result.description, equals('Custom test description'));
      });

      test('describe returns labels', () async {
        await provider.initialize(
          const VisionProviderConfig(apiKey: 'test-key'),
        );

        final imageData = bytesToStream([1, 2, 3]);
        final options = const bundle.VisionOptions();

        final result = await provider.describe(imageData, options);

        expect(result.labels, isNotNull);
        expect(result.labels!.length, greaterThan(0));
        expect(result.labels!.first.name, isNotEmpty);
        expect(result.labels!.first.confidence, greaterThan(0));
      });

      test('describe throws when configured to fail', () async {
        provider.setFailure(true);
        await provider.initialize(
          const VisionProviderConfig(apiKey: 'test-key'),
        );

        final imageData = bytesToStream([1, 2, 3]);
        final options = const bundle.VisionOptions();

        expect(
          () => provider.describe(imageData, options),
          throwsException,
        );
      });
    });

    group('VisionProviderConfig', () {
      test('creates config with required apiKey', () {
        const config = VisionProviderConfig(apiKey: 'test-key');

        expect(config.apiKey, equals('test-key'));
        expect(config.projectId, isNull);
        expect(config.region, isNull);
        expect(config.timeout, equals(const Duration(seconds: 30)));
        expect(config.maxRetries, equals(3));
      });

      test('creates config with all parameters', () {
        const config = VisionProviderConfig(
          apiKey: 'test-key',
          projectId: 'my-project',
          region: 'us-east-1',
          timeout: Duration(seconds: 60),
          maxRetries: 5,
        );

        expect(config.apiKey, equals('test-key'));
        expect(config.projectId, equals('my-project'));
        expect(config.region, equals('us-east-1'));
        expect(config.timeout, equals(const Duration(seconds: 60)));
        expect(config.maxRetries, equals(5));
      });
    });

    group('BaseVisionProvider', () {
      test('collectBytes collects stream into Uint8List', () async {
        final provider = _TestVisionProvider();
        await provider.initialize(
          const VisionProviderConfig(apiKey: 'test-key'),
        );

        final stream = bytesToStream([1, 2, 3, 4, 5]);
        final bytes = await provider.testCollectBytes(stream);

        expect(bytes, equals(Uint8List.fromList([1, 2, 3, 4, 5])));
      });

      test('config throws when not initialized', () {
        final provider = _TestVisionProvider();

        expect(
          () => provider.testGetConfig(),
          throwsA(isA<StateError>()),
        );
      });

      test('config returns value after initialization', () async {
        final provider = _TestVisionProvider();
        const expectedConfig = VisionProviderConfig(apiKey: 'test-key');
        await provider.initialize(expectedConfig);

        final config = provider.testGetConfig();

        expect(config.apiKey, equals('test-key'));
      });
    });
  });

  group('VisionPortAdapter', () {
    late MockVisionProvider mockProvider;
    late VisionPortAdapter adapter;

    setUp(() async {
      mockProvider = MockVisionProvider();
      await mockProvider.initialize(
        const VisionProviderConfig(apiKey: 'test-key'),
      );
      adapter = VisionPortAdapter(mockProvider);
    });

    tearDown(() async {
      await mockProvider.close();
    });

    test('implements bundle.VisionPort', () {
      expect(adapter, isA<bundle.VisionPort>());
    });

    test('isAvailable delegates to provider', () async {
      expect(await adapter.isAvailable(), isTrue);

      await mockProvider.close();
      expect(await adapter.isAvailable(), isFalse);
    });

    test('describe delegates to provider', () async {
      final imageData = bytesToStream([1, 2, 3]);
      final options = const bundle.VisionOptions();

      final result = await adapter.describe(imageData, options);

      expect(result.description, isNotEmpty);
      expect(result.confidence, greaterThan(0));
    });

    test('can be used where bundle.VisionPort is expected', () async {
      Future<String> useVisionPort(bundle.VisionPort vision) async {
        final imageData = bytesToStream([1, 2, 3]);
        final result = await vision.describe(
          imageData,
          const bundle.VisionOptions(),
        );
        return result.description;
      }

      final description = await useVisionPort(adapter);
      expect(description, isNotEmpty);
    });
  });
}

/// Test implementation of BaseVisionProvider for testing base class methods.
class _TestVisionProvider extends BaseVisionProvider {
  @override
  String get id => 'test-vision';

  @override
  Future<bundle.VisionResult> describe(
    Stream<List<int>> imageData,
    bundle.VisionOptions options,
  ) async {
    throw UnimplementedError();
  }

  /// Expose collectBytes for testing.
  Future<Uint8List> testCollectBytes(Stream<List<int>> stream) {
    return collectBytes(stream);
  }

  /// Expose config getter for testing.
  VisionProviderConfig testGetConfig() => config;
}
