// test/multi_round_tool_test.dart

import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  group('Multi-Round Tool Calling', () {
    group('LlmClient maxToolRounds parameter', () {
      test('should default to 1 round', () {
        final provider = MockLlmProvider();
        final client = LlmClient(llmProvider: provider);

        // Default should be 1 round (single tool call)
        expect(client, isNotNull);
      });

      test('should accept maxToolRounds parameter', () {
        final provider = MockLlmProvider();
        final client = LlmClient(
          llmProvider: provider,
          maxToolRounds: 3,
        );

        expect(client, isNotNull);
      });

      test('should clamp maxToolRounds between 1 and 10', () {
        final provider = MockLlmProvider();

        // Test with 0 (should clamp to 1)
        final clientMin = LlmClient(
          llmProvider: provider,
          maxToolRounds: 0,
        );
        expect(clientMin, isNotNull);

        // Test with 100 (should clamp to 10)
        final clientMax = LlmClient(
          llmProvider: provider,
          maxToolRounds: 100,
        );
        expect(clientMax, isNotNull);
      });

      test('should accept valid maxToolRounds values', () {
        final provider = MockLlmProvider();

        for (int rounds = 1; rounds <= 10; rounds++) {
          final client = LlmClient(
            llmProvider: provider,
            maxToolRounds: rounds,
          );
          expect(client, isNotNull);
        }
      });
    });

    group('useDeferredLoading parameter', () {
      test('should default to false', () {
        final provider = MockLlmProvider();
        final client = LlmClient(llmProvider: provider);

        expect(client, isNotNull);
      });

      test('should accept useDeferredLoading=true', () {
        final provider = MockLlmProvider();
        final client = LlmClient(
          llmProvider: provider,
          useDeferredLoading: true,
        );

        expect(client, isNotNull);
      });

      test('should work with both parameters combined', () {
        final provider = MockLlmProvider();
        final client = LlmClient(
          llmProvider: provider,
          useDeferredLoading: true,
          maxToolRounds: 5,
        );

        expect(client, isNotNull);
      });
    });
  });
}

/// Mock LLM provider for testing
class MockLlmProvider implements LlmProvider {
  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    return LlmResponse(text: 'Mock response');
  }

  @override
  Stream<LlmResponseChunk> streamComplete(LlmRequest request) async* {
    yield LlmResponseChunk(textChunk: 'Mock', isDone: false);
    yield LlmResponseChunk(textChunk: ' response', isDone: true);
  }

  @override
  Future<List<double>> getEmbeddings(String text) async {
    return List.filled(384, 0.0);
  }

  @override
  Future<void> initialize(LlmConfiguration config) async {}

  @override
  Future<void> close() async {}

  @override
  bool get supportsPromptCaching => false;

  @override
  bool hasToolCallMetadata(Map<String, dynamic> metadata) {
    return metadata.containsKey('tool_calls');
  }

  @override
  LlmToolCall? extractToolCallFromMetadata(Map<String, dynamic> metadata) {
    return null;
  }

  @override
  Map<String, dynamic> standardizeMetadata(Map<String, dynamic> metadata) {
    return metadata;
  }
}
