/// OCR Provider Tests
///
/// Tests for OcrProvider interface, base class, and implementations.
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:mcp_bundle/ports.dart' as bundle;
import 'package:mcp_llm/mcp_llm.dart';

import 'test_utils/mock_extension_providers.dart';

void main() {
  group('OcrProvider', () {
    group('MockOcrProvider', () {
      late MockOcrProvider provider;

      setUp(() {
        provider = MockOcrProvider();
      });

      tearDown(() async {
        await provider.close();
      });

      test('has correct id', () {
        expect(provider.id, equals('mock-ocr'));
      });

      test('is not available before initialization', () async {
        expect(await provider.isAvailable(), isFalse);
      });

      test('is available after initialization', () async {
        await provider.initialize(
          const OcrProviderConfig(apiKey: 'test-key'),
        );
        expect(await provider.isAvailable(), isTrue);
      });

      test('is not available after close', () async {
        await provider.initialize(
          const OcrProviderConfig(apiKey: 'test-key'),
        );
        await provider.close();
        expect(await provider.isAvailable(), isFalse);
      });

      test('supportedLanguages returns list', () async {
        await provider.initialize(
          const OcrProviderConfig(apiKey: 'test-key'),
        );

        final languages = await provider.supportedLanguages();

        expect(languages, isNotEmpty);
        expect(languages, contains('eng'));
      });

      test('recognize returns result with text', () async {
        await provider.initialize(
          const OcrProviderConfig(apiKey: 'test-key'),
        );

        final imageData = bytesToStream([1, 2, 3, 4, 5]);
        final options = const bundle.OcrOptions();

        final result = await provider.recognize(imageData, options);

        expect(result.text, isNotEmpty);
        expect(result.confidence, greaterThan(0));
        expect(result.processingTime, isNotNull);
      });

      test('recognize returns custom text', () async {
        provider.setMockText('Custom OCR text');
        await provider.initialize(
          const OcrProviderConfig(apiKey: 'test-key'),
        );

        final imageData = bytesToStream([1, 2, 3]);
        final options = const bundle.OcrOptions();

        final result = await provider.recognize(imageData, options);

        expect(result.text, equals('Custom OCR text'));
      });

      test('recognize returns regions with bounding boxes', () async {
        await provider.initialize(
          const OcrProviderConfig(apiKey: 'test-key'),
        );

        final imageData = bytesToStream([1, 2, 3]);
        final options = const bundle.OcrOptions();

        final result = await provider.recognize(imageData, options);

        expect(result.regions, isNotNull);
        expect(result.regions!.length, greaterThan(0));
        expect(result.regions!.first.text, isNotEmpty);
        expect(result.regions!.first.confidence, greaterThan(0));
        expect(result.regions!.first.boundingBox, isNotNull);
        expect(result.regions!.first.boundingBox.width, greaterThan(0));
        expect(result.regions!.first.boundingBox.height, greaterThan(0));
      });

      test('recognize respects language option', () async {
        await provider.initialize(
          const OcrProviderConfig(apiKey: 'test-key'),
        );

        final imageData = bytesToStream([1, 2, 3]);
        final options = const bundle.OcrOptions(language: 'kor');

        final result = await provider.recognize(imageData, options);

        expect(result.language, equals('kor'));
      });

      test('recognize throws when configured to fail', () async {
        provider.setFailure(true);
        await provider.initialize(
          const OcrProviderConfig(apiKey: 'test-key'),
        );

        final imageData = bytesToStream([1, 2, 3]);
        final options = const bundle.OcrOptions();

        expect(
          () => provider.recognize(imageData, options),
          throwsA(isA<OcrProviderException>()),
        );
      });
    });

    group('OcrProviderConfig', () {
      test('creates config with required apiKey', () {
        const config = OcrProviderConfig(apiKey: 'test-key');

        expect(config.apiKey, equals('test-key'));
        expect(config.projectId, isNull);
        expect(config.region, isNull);
        expect(config.timeout, equals(const Duration(seconds: 30)));
        expect(config.maxRetries, equals(3));
      });

      test('creates config with all parameters', () {
        const config = OcrProviderConfig(
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

    group('OcrProviderException', () {
      test('creates exception with message', () {
        final exception = OcrProviderException('Test error');

        expect(exception.message, equals('Test error'));
        expect(exception.cause, isNull);
        expect(exception.toString(), contains('Test error'));
      });

      test('creates exception with message and cause', () {
        final cause = Exception('Original error');
        final exception = OcrProviderException('Test error', cause);

        expect(exception.message, equals('Test error'));
        expect(exception.cause, equals(cause));
        expect(exception.toString(), contains('Test error'));
        expect(exception.toString(), contains('Original error'));
      });
    });

    group('BaseOcrProvider', () {
      test('collectBytes collects stream into Uint8List', () async {
        final provider = _TestOcrProvider();
        await provider.initialize(
          const OcrProviderConfig(apiKey: 'test-key'),
        );

        final stream = bytesToStream([1, 2, 3, 4, 5]);
        final bytes = await provider.testCollectBytes(stream);

        expect(bytes, equals(Uint8List.fromList([1, 2, 3, 4, 5])));
      });

      test('config throws when not initialized', () {
        final provider = _TestOcrProvider();

        expect(
          () => provider.testGetConfig(),
          throwsA(isA<StateError>()),
        );
      });

      test('config returns value after initialization', () async {
        final provider = _TestOcrProvider();
        const expectedConfig = OcrProviderConfig(apiKey: 'test-key');
        await provider.initialize(expectedConfig);

        final config = provider.testGetConfig();

        expect(config.apiKey, equals('test-key'));
      });
    });
  });

  group('OcrPortAdapter', () {
    late MockOcrProvider mockProvider;
    late OcrPortAdapter adapter;

    setUp(() async {
      mockProvider = MockOcrProvider();
      await mockProvider.initialize(
        const OcrProviderConfig(apiKey: 'test-key'),
      );
      adapter = OcrPortAdapter(mockProvider);
    });

    tearDown(() async {
      await mockProvider.close();
    });

    test('implements bundle.OcrPort', () {
      expect(adapter, isA<bundle.OcrPort>());
    });

    test('isAvailable delegates to provider', () async {
      expect(await adapter.isAvailable(), isTrue);

      await mockProvider.close();
      expect(await adapter.isAvailable(), isFalse);
    });

    test('supportedLanguages delegates to provider', () async {
      final languages = await adapter.supportedLanguages();

      expect(languages, isNotEmpty);
      expect(languages, contains('eng'));
    });

    test('recognize delegates to provider', () async {
      final imageData = bytesToStream([1, 2, 3]);
      final options = const bundle.OcrOptions();

      final result = await adapter.recognize(imageData, options);

      expect(result.text, isNotEmpty);
      expect(result.confidence, greaterThan(0));
    });

    test('can be used where bundle.OcrPort is expected', () async {
      Future<String> useOcrPort(bundle.OcrPort ocr) async {
        final imageData = bytesToStream([1, 2, 3]);
        final result = await ocr.recognize(
          imageData,
          const bundle.OcrOptions(),
        );
        return result.text;
      }

      final text = await useOcrPort(adapter);
      expect(text, isNotEmpty);
    });
  });
}

/// Test implementation of BaseOcrProvider for testing base class methods.
class _TestOcrProvider extends BaseOcrProvider {
  @override
  String get id => 'test-ocr';

  @override
  Future<bundle.OcrResult> recognize(
    Stream<List<int>> imageData,
    bundle.OcrOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<String>> supportedLanguages() async => ['eng'];

  /// Expose collectBytes for testing.
  Future<Uint8List> testCollectBytes(Stream<List<int>> stream) {
    return collectBytes(stream);
  }

  /// Expose config getter for testing.
  OcrProviderConfig testGetConfig() => config;
}
