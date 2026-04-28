/// ASR Provider Tests
///
/// Tests for AsrProvider interface, base class, and implementations.
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:mcp_bundle/ports.dart' as bundle;
import 'package:mcp_llm/mcp_llm.dart';

import 'test_utils/mock_extension_providers.dart';

void main() {
  group('AsrProvider', () {
    group('MockAsrProvider', () {
      late MockAsrProvider provider;

      setUp(() {
        provider = MockAsrProvider();
      });

      tearDown(() async {
        await provider.close();
      });

      test('has correct id', () {
        expect(provider.id, equals('mock-asr'));
      });

      test('is not available before initialization', () async {
        expect(await provider.isAvailable(), isFalse);
      });

      test('is available after initialization', () async {
        await provider.initialize(
          const AsrProviderConfig(apiKey: 'test-key'),
        );
        expect(await provider.isAvailable(), isTrue);
      });

      test('is not available after close', () async {
        await provider.initialize(
          const AsrProviderConfig(apiKey: 'test-key'),
        );
        await provider.close();
        expect(await provider.isAvailable(), isFalse);
      });

      test('supportedLanguages returns list', () async {
        await provider.initialize(
          const AsrProviderConfig(apiKey: 'test-key'),
        );

        final languages = await provider.supportedLanguages();

        expect(languages, isNotEmpty);
        expect(languages, contains('en'));
      });

      test('transcribe returns result with text', () async {
        await provider.initialize(
          const AsrProviderConfig(apiKey: 'test-key'),
        );

        final audioData = bytesToStream([1, 2, 3, 4, 5]);
        final options = const bundle.AsrOptions();

        final result = await provider.transcribe(audioData, options);

        expect(result.text, isNotEmpty);
        expect(result.confidence, greaterThan(0));
        expect(result.audioDuration, isNotNull);
        expect(result.processingTime, isNotNull);
      });

      test('transcribe returns custom text', () async {
        provider.setMockText('Custom transcription text');
        await provider.initialize(
          const AsrProviderConfig(apiKey: 'test-key'),
        );

        final audioData = bytesToStream([1, 2, 3]);
        final options = const bundle.AsrOptions();

        final result = await provider.transcribe(audioData, options);

        expect(result.text, equals('Custom transcription text'));
      });

      test('transcribe returns segments', () async {
        await provider.initialize(
          const AsrProviderConfig(apiKey: 'test-key'),
        );

        final audioData = bytesToStream([1, 2, 3]);
        final options = const bundle.AsrOptions();

        final result = await provider.transcribe(audioData, options);

        expect(result.segments, isNotNull);
        expect(result.segments!.length, greaterThan(0));
        expect(result.segments!.first.text, isNotEmpty);
        expect(result.segments!.first.confidence, greaterThan(0));
      });

      test('transcribe respects language option', () async {
        await provider.initialize(
          const AsrProviderConfig(apiKey: 'test-key'),
        );

        final audioData = bytesToStream([1, 2, 3]);
        final options = const bundle.AsrOptions(language: 'ko');

        final result = await provider.transcribe(audioData, options);

        expect(result.language, equals('ko'));
      });

      test('transcribe throws when configured to fail', () async {
        provider.setFailure(true);
        await provider.initialize(
          const AsrProviderConfig(apiKey: 'test-key'),
        );

        final audioData = bytesToStream([1, 2, 3]);
        final options = const bundle.AsrOptions();

        expect(
          () => provider.transcribe(audioData, options),
          throwsA(isA<AsrProviderException>()),
        );
      });
    });

    group('AsrProviderConfig', () {
      test('creates config with required apiKey', () {
        const config = AsrProviderConfig(apiKey: 'test-key');

        expect(config.apiKey, equals('test-key'));
        expect(config.projectId, isNull);
        expect(config.timeout, equals(const Duration(minutes: 5)));
        expect(config.maxRetries, equals(3));
      });

      test('creates config with all parameters', () {
        const config = AsrProviderConfig(
          apiKey: 'test-key',
          projectId: 'my-project',
          timeout: Duration(minutes: 10),
          maxRetries: 5,
        );

        expect(config.apiKey, equals('test-key'));
        expect(config.projectId, equals('my-project'));
        expect(config.timeout, equals(const Duration(minutes: 10)));
        expect(config.maxRetries, equals(5));
      });
    });

    group('AsrProviderException', () {
      test('creates exception with message', () {
        final exception = AsrProviderException('Test error');

        expect(exception.message, equals('Test error'));
        expect(exception.cause, isNull);
        expect(exception.toString(), contains('Test error'));
      });

      test('creates exception with message and cause', () {
        final cause = Exception('Original error');
        final exception = AsrProviderException('Test error', cause);

        expect(exception.message, equals('Test error'));
        expect(exception.cause, equals(cause));
        expect(exception.toString(), contains('Test error'));
        expect(exception.toString(), contains('Original error'));
      });
    });

    group('BaseAsrProvider', () {
      test('collectBytes collects stream into Uint8List', () async {
        final provider = _TestAsrProvider();
        await provider.initialize(
          const AsrProviderConfig(apiKey: 'test-key'),
        );

        final stream = bytesToStream([1, 2, 3, 4, 5]);
        final bytes = await provider.testCollectBytes(stream);

        expect(bytes, equals(Uint8List.fromList([1, 2, 3, 4, 5])));
      });

      test('config throws when not initialized', () {
        final provider = _TestAsrProvider();

        expect(
          () => provider.testGetConfig(),
          throwsA(isA<StateError>()),
        );
      });

      test('config returns value after initialization', () async {
        final provider = _TestAsrProvider();
        const expectedConfig = AsrProviderConfig(apiKey: 'test-key');
        await provider.initialize(expectedConfig);

        final config = provider.testGetConfig();

        expect(config.apiKey, equals('test-key'));
      });
    });
  });

  group('AsrPortAdapter', () {
    late MockAsrProvider mockProvider;
    late AsrPortAdapter adapter;

    setUp(() async {
      mockProvider = MockAsrProvider();
      await mockProvider.initialize(
        const AsrProviderConfig(apiKey: 'test-key'),
      );
      adapter = AsrPortAdapter(mockProvider);
    });

    tearDown(() async {
      await mockProvider.close();
    });

    test('implements bundle.AsrPort', () {
      expect(adapter, isA<bundle.AsrPort>());
    });

    test('isAvailable delegates to provider', () async {
      expect(await adapter.isAvailable(), isTrue);

      await mockProvider.close();
      expect(await adapter.isAvailable(), isFalse);
    });

    test('supportedLanguages delegates to provider', () async {
      final languages = await adapter.supportedLanguages();

      expect(languages, isNotEmpty);
      expect(languages, contains('en'));
    });

    test('transcribe delegates to provider', () async {
      final audioData = bytesToStream([1, 2, 3]);
      final options = const bundle.AsrOptions();

      final result = await adapter.transcribe(audioData, options);

      expect(result.text, isNotEmpty);
      expect(result.confidence, greaterThan(0));
    });

    test('can be used where bundle.AsrPort is expected', () async {
      Future<String> useAsrPort(bundle.AsrPort asr) async {
        final audioData = bytesToStream([1, 2, 3]);
        final result = await asr.transcribe(
          audioData,
          const bundle.AsrOptions(),
        );
        return result.text;
      }

      final text = await useAsrPort(adapter);
      expect(text, isNotEmpty);
    });
  });
}

/// Test implementation of BaseAsrProvider for testing base class methods.
class _TestAsrProvider extends BaseAsrProvider {
  @override
  String get id => 'test-asr';

  @override
  Future<bundle.AsrResult> transcribe(
    Stream<List<int>> audioData,
    bundle.AsrOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<List<String>> supportedLanguages() async => ['en'];

  /// Expose collectBytes for testing.
  Future<Uint8List> testCollectBytes(Stream<List<int>> stream) {
    return collectBytes(stream);
  }

  /// Expose config getter for testing.
  AsrProviderConfig testGetConfig() => config;
}
