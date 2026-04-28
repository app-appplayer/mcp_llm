/// Cloud Provider Registry Tests
///
/// Tests for CloudProviderRegistry unified provider management.
library;

import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

import 'test_utils/mock_provider.dart';
import 'test_utils/mock_extension_providers.dart';

void main() {
  group('CloudProviderRegistry', () {
    late CloudProviderRegistry registry;

    setUp(() {
      registry = CloudProviderRegistry();
    });

    tearDown(() async {
      await registry.close();
    });

    group('constructor', () {
      test('creates empty registry', () {
        expect(registry.llmIds, isEmpty);
        expect(registry.visionIds, isEmpty);
        expect(registry.asrIds, isEmpty);
        expect(registry.ocrIds, isEmpty);
        expect(registry.storageIds, isEmpty);
      });

      test('empty() factory creates empty registry', () {
        final emptyRegistry = CloudProviderRegistry.empty();

        expect(emptyRegistry.llmIds, isEmpty);
        expect(emptyRegistry.visionIds, isEmpty);
        expect(emptyRegistry.asrIds, isEmpty);
        expect(emptyRegistry.ocrIds, isEmpty);
        expect(emptyRegistry.storageIds, isEmpty);
      });
    });

    group('LLM providers', () {
      late MockLlmProvider mockLlm;

      setUp(() {
        mockLlm = MockLlmProvider(
          config: LlmConfiguration(model: 'test-model'),
        );
      });

      test('registerLlm adds provider', () {
        registry.registerLlm('test', mockLlm);

        expect(registry.llmIds, contains('test'));
        expect(registry.getLlm('test'), equals(mockLlm));
      });

      test('getLlm returns null for non-existent id', () {
        expect(registry.getLlm('non-existent'), isNull);
      });

      test('registerLlm overwrites existing provider', () {
        final otherLlm = MockLlmProvider(
          config: LlmConfiguration(model: 'other-model'),
        );

        registry.registerLlm('test', mockLlm);
        registry.registerLlm('test', otherLlm);

        expect(registry.getLlm('test'), equals(otherLlm));
      });

      test('unregisterLlm removes provider', () {
        registry.registerLlm('test', mockLlm);
        expect(registry.getLlm('test'), isNotNull);

        registry.unregisterLlm('test');

        expect(registry.getLlm('test'), isNull);
        expect(registry.llmIds, isNot(contains('test')));
      });

      test('llmIds returns all registered ids', () {
        registry.registerLlm('llm1', mockLlm);
        registry.registerLlm('llm2', mockLlm);
        registry.registerLlm('llm3', mockLlm);

        expect(registry.llmIds, containsAll(['llm1', 'llm2', 'llm3']));
        expect(registry.llmIds.length, equals(3));
      });
    });

    group('Vision providers', () {
      late MockVisionProvider mockVision;

      setUp(() async {
        mockVision = MockVisionProvider();
        await mockVision.initialize(
          const VisionProviderConfig(apiKey: 'test-key'),
        );
      });

      test('registerVision adds provider', () {
        registry.registerVision('test', mockVision);

        expect(registry.visionIds, contains('test'));
        expect(registry.getVision('test'), equals(mockVision));
      });

      test('getVision returns null for non-existent id', () {
        expect(registry.getVision('non-existent'), isNull);
      });

      test('unregisterVision removes provider', () {
        registry.registerVision('test', mockVision);
        expect(registry.getVision('test'), isNotNull);

        registry.unregisterVision('test');

        expect(registry.getVision('test'), isNull);
        expect(registry.visionIds, isNot(contains('test')));
      });

      test('visionIds returns all registered ids', () {
        registry.registerVision('vision1', mockVision);
        registry.registerVision('vision2', mockVision);

        expect(registry.visionIds, containsAll(['vision1', 'vision2']));
        expect(registry.visionIds.length, equals(2));
      });
    });

    group('ASR providers', () {
      late MockAsrProvider mockAsr;

      setUp(() async {
        mockAsr = MockAsrProvider();
        await mockAsr.initialize(
          const AsrProviderConfig(apiKey: 'test-key'),
        );
      });

      test('registerAsr adds provider', () {
        registry.registerAsr('test', mockAsr);

        expect(registry.asrIds, contains('test'));
        expect(registry.getAsr('test'), equals(mockAsr));
      });

      test('getAsr returns null for non-existent id', () {
        expect(registry.getAsr('non-existent'), isNull);
      });

      test('unregisterAsr removes provider', () {
        registry.registerAsr('test', mockAsr);
        expect(registry.getAsr('test'), isNotNull);

        registry.unregisterAsr('test');

        expect(registry.getAsr('test'), isNull);
        expect(registry.asrIds, isNot(contains('test')));
      });

      test('asrIds returns all registered ids', () {
        registry.registerAsr('asr1', mockAsr);
        registry.registerAsr('asr2', mockAsr);

        expect(registry.asrIds, containsAll(['asr1', 'asr2']));
        expect(registry.asrIds.length, equals(2));
      });
    });

    group('OCR providers', () {
      late MockOcrProvider mockOcr;

      setUp(() async {
        mockOcr = MockOcrProvider();
        await mockOcr.initialize(
          const OcrProviderConfig(apiKey: 'test-key'),
        );
      });

      test('registerOcr adds provider', () {
        registry.registerOcr('test', mockOcr);

        expect(registry.ocrIds, contains('test'));
        expect(registry.getOcr('test'), equals(mockOcr));
      });

      test('getOcr returns null for non-existent id', () {
        expect(registry.getOcr('non-existent'), isNull);
      });

      test('unregisterOcr removes provider', () {
        registry.registerOcr('test', mockOcr);
        expect(registry.getOcr('test'), isNotNull);

        registry.unregisterOcr('test');

        expect(registry.getOcr('test'), isNull);
        expect(registry.ocrIds, isNot(contains('test')));
      });

      test('ocrIds returns all registered ids', () {
        registry.registerOcr('ocr1', mockOcr);
        registry.registerOcr('ocr2', mockOcr);

        expect(registry.ocrIds, containsAll(['ocr1', 'ocr2']));
        expect(registry.ocrIds.length, equals(2));
      });
    });

    group('Storage providers', () {
      late MockBinaryStorageProvider mockStorage;

      setUp(() async {
        mockStorage = MockBinaryStorageProvider();
        await mockStorage.initialize(
          const StorageProviderConfig(
            accessKey: 'test-key',
            bucket: 'test-bucket',
          ),
        );
      });

      test('registerStorage adds provider', () {
        registry.registerStorage('test', mockStorage);

        expect(registry.storageIds, contains('test'));
        expect(registry.getStorage('test'), equals(mockStorage));
      });

      test('getStorage returns null for non-existent id', () {
        expect(registry.getStorage('non-existent'), isNull);
      });

      test('unregisterStorage removes provider', () {
        registry.registerStorage('test', mockStorage);
        expect(registry.getStorage('test'), isNotNull);

        registry.unregisterStorage('test');

        expect(registry.getStorage('test'), isNull);
        expect(registry.storageIds, isNot(contains('test')));
      });

      test('storageIds returns all registered ids', () {
        registry.registerStorage('storage1', mockStorage);
        registry.registerStorage('storage2', mockStorage);

        expect(registry.storageIds, containsAll(['storage1', 'storage2']));
        expect(registry.storageIds.length, equals(2));
      });
    });

    group('close', () {
      test('closes all vision providers', () async {
        final mockVision = MockVisionProvider();
        await mockVision.initialize(
          const VisionProviderConfig(apiKey: 'test-key'),
        );
        registry.registerVision('test', mockVision);

        expect(await mockVision.isAvailable(), isTrue);

        await registry.close();

        expect(await mockVision.isAvailable(), isFalse);
        expect(registry.visionIds, isEmpty);
      });

      test('closes all ASR providers', () async {
        final mockAsr = MockAsrProvider();
        await mockAsr.initialize(
          const AsrProviderConfig(apiKey: 'test-key'),
        );
        registry.registerAsr('test', mockAsr);

        expect(await mockAsr.isAvailable(), isTrue);

        await registry.close();

        expect(await mockAsr.isAvailable(), isFalse);
        expect(registry.asrIds, isEmpty);
      });

      test('closes all OCR providers', () async {
        final mockOcr = MockOcrProvider();
        await mockOcr.initialize(
          const OcrProviderConfig(apiKey: 'test-key'),
        );
        registry.registerOcr('test', mockOcr);

        expect(await mockOcr.isAvailable(), isTrue);

        await registry.close();

        expect(await mockOcr.isAvailable(), isFalse);
        expect(registry.ocrIds, isEmpty);
      });

      test('closes all storage providers', () async {
        final mockStorage = MockBinaryStorageProvider();
        await mockStorage.initialize(
          const StorageProviderConfig(
            accessKey: 'test-key',
            bucket: 'test-bucket',
          ),
        );
        registry.registerStorage('test', mockStorage);

        expect(await mockStorage.isAvailable(), isTrue);

        await registry.close();

        expect(await mockStorage.isAvailable(), isFalse);
        expect(registry.storageIds, isEmpty);
      });

      test('clears all LLM providers', () async {
        final mockLlm = MockLlmProvider(
          config: LlmConfiguration(model: 'test-model'),
        );
        registry.registerLlm('test', mockLlm);

        expect(registry.llmIds, isNotEmpty);

        await registry.close();

        expect(registry.llmIds, isEmpty);
      });

      test('closes all providers of all types', () async {
        final mockLlm = MockLlmProvider(
          config: LlmConfiguration(model: 'test-model'),
        );
        final mockVision = MockVisionProvider();
        await mockVision.initialize(
          const VisionProviderConfig(apiKey: 'test-key'),
        );
        final mockAsr = MockAsrProvider();
        await mockAsr.initialize(
          const AsrProviderConfig(apiKey: 'test-key'),
        );
        final mockOcr = MockOcrProvider();
        await mockOcr.initialize(
          const OcrProviderConfig(apiKey: 'test-key'),
        );
        final mockStorage = MockBinaryStorageProvider();
        await mockStorage.initialize(
          const StorageProviderConfig(
            accessKey: 'test-key',
            bucket: 'test-bucket',
          ),
        );

        registry.registerLlm('llm', mockLlm);
        registry.registerVision('vision', mockVision);
        registry.registerAsr('asr', mockAsr);
        registry.registerOcr('ocr', mockOcr);
        registry.registerStorage('storage', mockStorage);

        await registry.close();

        expect(registry.llmIds, isEmpty);
        expect(registry.visionIds, isEmpty);
        expect(registry.asrIds, isEmpty);
        expect(registry.ocrIds, isEmpty);
        expect(registry.storageIds, isEmpty);
      });
    });

    group('multiple providers with same id aliases', () {
      test('supports registering same provider with multiple ids', () async {
        final mockAsr = MockAsrProvider();
        await mockAsr.initialize(
          const AsrProviderConfig(apiKey: 'test-key'),
        );

        registry.registerAsr('whisper', mockAsr);
        registry.registerAsr('openai', mockAsr);

        expect(registry.getAsr('whisper'), equals(mockAsr));
        expect(registry.getAsr('openai'), equals(mockAsr));
        expect(registry.getAsr('whisper'), equals(registry.getAsr('openai')));
      });
    });
  });

  group('CloudProviderRegistry integration', () {
    test('can create adapters from registered providers', () async {
      final registry = CloudProviderRegistry();

      final mockVision = MockVisionProvider();
      await mockVision.initialize(
        const VisionProviderConfig(apiKey: 'test-key'),
      );
      registry.registerVision('google', mockVision);

      final mockAsr = MockAsrProvider();
      await mockAsr.initialize(
        const AsrProviderConfig(apiKey: 'test-key'),
      );
      registry.registerAsr('whisper', mockAsr);

      final mockOcr = MockOcrProvider();
      await mockOcr.initialize(
        const OcrProviderConfig(apiKey: 'test-key'),
      );
      registry.registerOcr('google', mockOcr);

      final mockStorage = MockBinaryStorageProvider();
      await mockStorage.initialize(
        const StorageProviderConfig(
          accessKey: 'test-key',
          bucket: 'test-bucket',
        ),
      );
      registry.registerStorage('s3', mockStorage);

      // Create adapters from registry
      final visionAdapter = VisionPortAdapter(registry.getVision('google')!);
      final asrAdapter = AsrPortAdapter(registry.getAsr('whisper')!);
      final ocrAdapter = OcrPortAdapter(registry.getOcr('google')!);
      final storageAdapter = BinaryStoragePortAdapter(registry.getStorage('s3')!);

      // Verify adapters are usable
      expect(await visionAdapter.isAvailable(), isTrue);
      expect(await asrAdapter.isAvailable(), isTrue);
      expect(await ocrAdapter.isAvailable(), isTrue);
      expect(await storageAdapter.exists('test'), isFalse);

      await registry.close();
    });
  });
}
