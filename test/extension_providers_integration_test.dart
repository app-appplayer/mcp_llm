/// Extension Providers Integration Tests
///
/// Tests for VisionProvider, AsrProvider, OcrProvider, and BinaryStorageProvider
/// with real cloud API keys.
///
/// To run these tests, set the following environment variables:
/// - GOOGLE_API_KEY: Google Cloud API key (Vision, Speech, OCR)
/// - OPENAI_API_KEY: OpenAI API key (Vision, Whisper)
/// - AWS_ACCESS_KEY: AWS access key (Textract, S3)
/// - AWS_SECRET_KEY: AWS secret key
/// - AWS_REGION: AWS region (default: us-east-1)
/// - AWS_S3_BUCKET: S3 bucket name
/// - GCS_BUCKET: Google Cloud Storage bucket name
///
/// Run with:
/// ```bash
/// GOOGLE_API_KEY=... OPENAI_API_KEY=... dart test test/extension_providers_integration_test.dart
/// ```
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:mcp_bundle/ports.dart' as bundle;
import 'package:mcp_llm/mcp_llm.dart';

// Test data
final _testImageBytes = _createTestPngBytes();
final _testAudioBytes = _createTestWavBytes();

void main() {
  // Get API keys from environment
  final googleApiKey = Platform.environment['GOOGLE_API_KEY'];
  final openAiApiKey = Platform.environment['OPENAI_API_KEY'];
  final awsAccessKey = Platform.environment['AWS_ACCESS_KEY'];
  final awsSecretKey = Platform.environment['AWS_SECRET_KEY'];
  final awsRegion = Platform.environment['AWS_REGION'] ?? 'us-east-1';
  final s3Bucket = Platform.environment['AWS_S3_BUCKET'];
  final gcsBucket = Platform.environment['GCS_BUCKET'];

  group('Vision Providers Integration', () {
    group('GoogleVisionProvider', () {
      late GoogleVisionProvider provider;

      setUpAll(() async {
        if (googleApiKey == null) {
          return;
        }
        provider = GoogleVisionProvider();
        await provider.initialize(VisionProviderConfig(apiKey: googleApiKey));
      });

      tearDownAll(() async {
        if (googleApiKey != null) {
          await provider.close();
        }
      });

      test('describe analyzes image', () async {
        if (googleApiKey == null) {
          markTestSkipped('GOOGLE_API_KEY not set');
          return;
        }

        final imageStream = Stream.value(_testImageBytes);
        final result = await provider.describe(
          imageStream,
          const bundle.VisionOptions(detailed: true),
        );

        expect(result.description, isNotEmpty);
        expect(result.confidence, greaterThan(0));
        expect(result.processingTime.inMilliseconds, greaterThan(0));
      }, timeout: const Timeout(Duration(seconds: 30)));

      test('describe returns labels', () async {
        if (googleApiKey == null) {
          markTestSkipped('GOOGLE_API_KEY not set');
          return;
        }

        final imageStream = Stream.value(_testImageBytes);
        final result = await provider.describe(
          imageStream,
          const bundle.VisionOptions(detectObjects: true),
        );

        expect(result.labels, isNotNull);
      }, timeout: const Timeout(Duration(seconds: 30)));
    });

    group('OpenAIVisionProvider', () {
      late OpenAIVisionProvider provider;

      setUpAll(() async {
        if (openAiApiKey == null) {
          return;
        }
        provider = OpenAIVisionProvider();
        await provider.initialize(VisionProviderConfig(apiKey: openAiApiKey));
      });

      tearDownAll(() async {
        if (openAiApiKey != null) {
          await provider.close();
        }
      });

      test('describe analyzes image with GPT-4 Vision', () async {
        if (openAiApiKey == null) {
          markTestSkipped('OPENAI_API_KEY not set');
          return;
        }

        final imageStream = Stream.value(_testImageBytes);
        final result = await provider.describe(
          imageStream,
          const bundle.VisionOptions(
            detailed: true,
            prompt: 'Describe this image briefly.',
          ),
        );

        expect(result.description, isNotEmpty);
        expect(result.confidence, greaterThan(0));
      }, timeout: const Timeout(Duration(seconds: 60)));
    });
  });

  group('ASR Providers Integration', () {
    group('OpenAIWhisperProvider', () {
      late OpenAIWhisperProvider provider;

      setUpAll(() async {
        if (openAiApiKey == null) {
          return;
        }
        provider = OpenAIWhisperProvider();
        await provider.initialize(AsrProviderConfig(apiKey: openAiApiKey));
      });

      tearDownAll(() async {
        if (openAiApiKey != null) {
          await provider.close();
        }
      });

      test('transcribe processes audio', () async {
        if (openAiApiKey == null) {
          markTestSkipped('OPENAI_API_KEY not set');
          return;
        }

        final audioStream = Stream.value(_testAudioBytes);
        final result = await provider.transcribe(
          audioStream,
          const bundle.AsrOptions(language: 'en'),
        );

        expect(result.text, isNotNull);
        expect(result.confidence, greaterThanOrEqualTo(0));
        expect(result.processingTime.inMilliseconds, greaterThan(0));
      }, timeout: const Timeout(Duration(seconds: 60)));

      test('supportedLanguages returns languages', () async {
        if (openAiApiKey == null) {
          markTestSkipped('OPENAI_API_KEY not set');
          return;
        }

        final languages = await provider.supportedLanguages();

        expect(languages, isNotEmpty);
        expect(languages, contains('en'));
      });
    });

    group('GoogleSpeechProvider', () {
      late GoogleSpeechProvider provider;

      setUpAll(() async {
        if (googleApiKey == null) {
          return;
        }
        provider = GoogleSpeechProvider();
        await provider.initialize(AsrProviderConfig(apiKey: googleApiKey));
      });

      tearDownAll(() async {
        if (googleApiKey != null) {
          await provider.close();
        }
      });

      test('transcribe processes audio', () async {
        if (googleApiKey == null) {
          markTestSkipped('GOOGLE_API_KEY not set');
          return;
        }

        final audioStream = Stream.value(_testAudioBytes);
        final result = await provider.transcribe(
          audioStream,
          const bundle.AsrOptions(language: 'en'),
        );

        expect(result.text, isNotNull);
        expect(result.processingTime.inMilliseconds, greaterThan(0));
      }, timeout: const Timeout(Duration(seconds: 60)));
    });
  });

  group('OCR Providers Integration', () {
    group('GoogleVisionOcrProvider', () {
      late GoogleVisionOcrProvider provider;

      setUpAll(() async {
        if (googleApiKey == null) {
          return;
        }
        provider = GoogleVisionOcrProvider();
        await provider.initialize(OcrProviderConfig(apiKey: googleApiKey));
      });

      tearDownAll(() async {
        if (googleApiKey != null) {
          await provider.close();
        }
      });

      test('recognize extracts text from image', () async {
        if (googleApiKey == null) {
          markTestSkipped('GOOGLE_API_KEY not set');
          return;
        }

        final imageStream = Stream.value(_testImageBytes);
        final result = await provider.recognize(
          imageStream,
          const bundle.OcrOptions(language: 'eng'),
        );

        expect(result.text, isNotNull);
        expect(result.confidence, greaterThanOrEqualTo(0));
        expect(result.processingTime.inMilliseconds, greaterThan(0));
      }, timeout: const Timeout(Duration(seconds: 30)));

      test('supportedLanguages returns languages', () async {
        if (googleApiKey == null) {
          markTestSkipped('GOOGLE_API_KEY not set');
          return;
        }

        final languages = await provider.supportedLanguages();

        expect(languages, isNotEmpty);
      });
    });

    group('AwsTextractProvider', () {
      late AwsTextractProvider provider;

      setUpAll(() async {
        if (awsAccessKey == null || awsSecretKey == null) {
          return;
        }
        provider = AwsTextractProvider(region: awsRegion);
        await provider.initialize(OcrProviderConfig(
          apiKey: '$awsAccessKey:$awsSecretKey',
          region: awsRegion,
        ));
      });

      tearDownAll(() async {
        if (awsAccessKey != null && awsSecretKey != null) {
          await provider.close();
        }
      });

      test('recognize extracts text with Textract', () async {
        if (awsAccessKey == null || awsSecretKey == null) {
          markTestSkipped('AWS_ACCESS_KEY or AWS_SECRET_KEY not set');
          return;
        }

        final imageStream = Stream.value(_testImageBytes);
        final result = await provider.recognize(
          imageStream,
          const bundle.OcrOptions(language: 'eng'),
        );

        expect(result.text, isNotNull);
        expect(result.processingTime.inMilliseconds, greaterThan(0));
      }, timeout: const Timeout(Duration(seconds: 30)));
    });
  });

  group('Storage Providers Integration', () {
    group('S3StorageProvider', () {
      late S3StorageProvider provider;
      final storedReferences = <String>[];

      setUpAll(() async {
        if (awsAccessKey == null || awsSecretKey == null || s3Bucket == null) {
          return;
        }
        provider = S3StorageProvider();
        await provider.initialize(StorageProviderConfig(
          accessKey: awsAccessKey,
          secretKey: awsSecretKey,
          bucket: s3Bucket,
          region: awsRegion,
        ));
      });

      tearDownAll(() async {
        if (awsAccessKey != null && awsSecretKey != null && s3Bucket != null) {
          // Clean up stored objects
          for (final ref in storedReferences) {
            await provider.delete(ref);
          }
          await provider.close();
        }
      });

      test('store and retrieve binary data', () async {
        if (awsAccessKey == null || awsSecretKey == null || s3Bucket == null) {
          markTestSkipped('AWS credentials or S3 bucket not set');
          return;
        }

        final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final dataStream = Stream.value(testData);

        // Store
        final reference = await provider.store(
          dataStream,
          'application/octet-stream',
          const bundle.StorageOptions(prefix: 'test/'),
        );
        storedReferences.add(reference);

        expect(reference, isNotEmpty);

        // Retrieve
        final retrieved = await provider.retrieve(reference);
        expect(retrieved, equals(testData));
      }, timeout: const Timeout(Duration(seconds: 30)));

      test('exists and metadata work correctly', () async {
        if (awsAccessKey == null || awsSecretKey == null || s3Bucket == null) {
          markTestSkipped('AWS credentials or S3 bucket not set');
          return;
        }

        final testData = Uint8List.fromList([10, 20, 30]);
        final reference = await provider.store(
          Stream.value(testData),
          'text/plain',
        );
        storedReferences.add(reference);

        expect(await provider.exists(reference), isTrue);

        final metadata = await provider.metadata(reference);
        expect(metadata, isNotNull);
        expect(metadata!.size, equals(3));
        expect(metadata.mimeType, equals('text/plain'));
      }, timeout: const Timeout(Duration(seconds: 30)));

      test('list returns stored references', () async {
        if (awsAccessKey == null || awsSecretKey == null || s3Bucket == null) {
          markTestSkipped('AWS credentials or S3 bucket not set');
          return;
        }

        final references = await provider.list('test/');

        expect(references, isA<List<String>>());
      }, timeout: const Timeout(Duration(seconds: 30)));
    });

    group('GcsStorageProvider', () {
      late GcsStorageProvider provider;
      final storedReferences = <String>[];

      setUpAll(() async {
        if (googleApiKey == null || gcsBucket == null) {
          return;
        }
        provider = GcsStorageProvider();
        await provider.initialize(StorageProviderConfig(
          accessKey: googleApiKey,
          bucket: gcsBucket,
        ));
      });

      tearDownAll(() async {
        if (googleApiKey != null && gcsBucket != null) {
          // Clean up stored objects
          for (final ref in storedReferences) {
            await provider.delete(ref);
          }
          await provider.close();
        }
      });

      test('store and retrieve binary data', () async {
        if (googleApiKey == null || gcsBucket == null) {
          markTestSkipped('GOOGLE_API_KEY or GCS_BUCKET not set');
          return;
        }

        final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final dataStream = Stream.value(testData);

        // Store
        final reference = await provider.store(
          dataStream,
          'application/octet-stream',
        );
        storedReferences.add(reference);

        expect(reference, isNotEmpty);

        // Retrieve
        final retrieved = await provider.retrieve(reference);
        expect(retrieved, equals(testData));
      }, timeout: const Timeout(Duration(seconds: 30)));
    });
  });

  group('CloudProviderRegistry Integration', () {
    test('defaults creates registry with available providers', () async {
      final registry = await CloudProviderRegistry.defaults(
        googleApiKey: googleApiKey,
        openAiApiKey: openAiApiKey,
        awsAccessKey: awsAccessKey,
        awsSecretKey: awsSecretKey,
        awsRegion: awsRegion,
      );

      if (googleApiKey != null) {
        expect(registry.getVision('google'), isNotNull);
        expect(registry.getAsr('google'), isNotNull);
        expect(registry.getOcr('google'), isNotNull);
      }

      if (openAiApiKey != null) {
        expect(registry.getVision('openai'), isNotNull);
        expect(registry.getAsr('whisper'), isNotNull);
        expect(registry.getAsr('openai'), isNotNull);
      }

      if (awsAccessKey != null) {
        expect(registry.getOcr('textract'), isNotNull);
        expect(registry.getOcr('aws'), isNotNull);
      }

      await registry.close();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('port adapters work with registry providers', () async {
      if (googleApiKey == null) {
        markTestSkipped('GOOGLE_API_KEY not set');
        return;
      }

      final registry = await CloudProviderRegistry.defaults(
        googleApiKey: googleApiKey,
      );

      // Create adapters from registry
      final visionAdapter = VisionPortAdapter(registry.getVision('google')!);
      final asrAdapter = AsrPortAdapter(registry.getAsr('google')!);
      final ocrAdapter = OcrPortAdapter(registry.getOcr('google')!);

      // Verify they implement bundle ports
      expect(visionAdapter, isA<bundle.VisionPort>());
      expect(asrAdapter, isA<bundle.AsrPort>());
      expect(ocrAdapter, isA<bundle.OcrPort>());

      // Verify availability
      expect(await visionAdapter.isAvailable(), isTrue);
      expect(await asrAdapter.isAvailable(), isTrue);
      expect(await ocrAdapter.isAvailable(), isTrue);

      await registry.close();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

/// Create minimal valid PNG bytes for testing.
Uint8List _createTestPngBytes() {
  // Minimal 1x1 white PNG image
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    0x00, 0x00, 0x00, 0x0D, // IHDR length
    0x49, 0x48, 0x44, 0x52, // IHDR
    0x00, 0x00, 0x00, 0x01, // width: 1
    0x00, 0x00, 0x00, 0x01, // height: 1
    0x08, 0x02, // bit depth: 8, color type: RGB
    0x00, 0x00, 0x00, // compression, filter, interlace
    0x90, 0x77, 0x53, 0xDE, // CRC
    0x00, 0x00, 0x00, 0x0C, // IDAT length
    0x49, 0x44, 0x41, 0x54, // IDAT
    0x08, 0xD7, 0x63, 0xF8, 0xFF, 0xFF, 0xFF, 0x00, // compressed data
    0x05, 0xFE, 0x02, 0xFE, // CRC
    0x00, 0x00, 0x00, 0x00, // IEND length
    0x49, 0x45, 0x4E, 0x44, // IEND
    0xAE, 0x42, 0x60, 0x82, // CRC
  ]);
}

/// Create minimal valid WAV bytes for testing (silence).
Uint8List _createTestWavBytes() {
  // Minimal WAV file: 16-bit mono 16kHz, 1 second of silence
  final sampleRate = 16000;
  final numSamples = sampleRate; // 1 second
  final dataSize = numSamples * 2; // 16-bit samples
  final fileSize = 36 + dataSize;

  final bytes = ByteData(44 + dataSize);
  var offset = 0;

  // RIFF header
  bytes.setUint8(offset++, 0x52); // R
  bytes.setUint8(offset++, 0x49); // I
  bytes.setUint8(offset++, 0x46); // F
  bytes.setUint8(offset++, 0x46); // F
  bytes.setUint32(offset, fileSize, Endian.little);
  offset += 4;
  bytes.setUint8(offset++, 0x57); // W
  bytes.setUint8(offset++, 0x41); // A
  bytes.setUint8(offset++, 0x56); // V
  bytes.setUint8(offset++, 0x45); // E

  // fmt chunk
  bytes.setUint8(offset++, 0x66); // f
  bytes.setUint8(offset++, 0x6D); // m
  bytes.setUint8(offset++, 0x74); // t
  bytes.setUint8(offset++, 0x20); // space
  bytes.setUint32(offset, 16, Endian.little); // chunk size
  offset += 4;
  bytes.setUint16(offset, 1, Endian.little); // PCM format
  offset += 2;
  bytes.setUint16(offset, 1, Endian.little); // mono
  offset += 2;
  bytes.setUint32(offset, sampleRate, Endian.little);
  offset += 4;
  bytes.setUint32(offset, sampleRate * 2, Endian.little); // byte rate
  offset += 4;
  bytes.setUint16(offset, 2, Endian.little); // block align
  offset += 2;
  bytes.setUint16(offset, 16, Endian.little); // bits per sample
  offset += 2;

  // data chunk
  bytes.setUint8(offset++, 0x64); // d
  bytes.setUint8(offset++, 0x61); // a
  bytes.setUint8(offset++, 0x74); // t
  bytes.setUint8(offset++, 0x61); // a
  bytes.setUint32(offset, dataSize, Endian.little);
  offset += 4;

  // Silence (zeros)
  for (var i = 0; i < numSamples; i++) {
    bytes.setInt16(offset, 0, Endian.little);
    offset += 2;
  }

  return bytes.buffer.asUint8List();
}
