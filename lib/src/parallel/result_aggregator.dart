import 'dart:math';
import '../core/models.dart';

/// Interface for aggregating multiple LLM responses
abstract class ResultAggregator {
  LlmResponse aggregate(List<LlmResponse> responses);
}

/// Aggregator that selects the response with highest confidence
class ConfidenceResultAggregator implements ResultAggregator {
  @override
  LlmResponse aggregate(List<LlmResponse> responses) {
    if (responses.isEmpty) {
      return LlmResponse(text: 'No responses received from any provider.');
    }

    LlmResponse bestResponse = responses.first;
    double highestConfidence = _getConfidence(responses.first);

    for (final response in responses.skip(1)) {
      final confidence = _getConfidence(response);
      if (confidence > highestConfidence) {
        highestConfidence = confidence;
        bestResponse = response;
      }
    }

    return bestResponse;
  }

  double _getConfidence(LlmResponse response) {
    return (response.metadata['confidence'] as num?)?.toDouble() ?? 0.5;
  }
}

/// Aggregator that merges results
class MergeResultAggregator implements ResultAggregator {
  @override
  LlmResponse aggregate(List<LlmResponse> responses) {
    if (responses.isEmpty) {
      return LlmResponse(text: 'No responses received from any provider.');
    }

    if (responses.length == 1) {
      return responses.first;
    }

    final allTexts = responses.map((r) => r.text).join('\n\n');
    final mergedText = 'Multiple results:\n\n$allTexts';

    // Merge metadata
    final mergedMetadata = <String, dynamic>{};
    for (final response in responses) {
      mergedMetadata.addAll(response.metadata);
    }

    return LlmResponse(
      text: mergedText,
      metadata: mergedMetadata,
      toolCalls: _mergeToolCalls(responses),
    );
  }

  List<LlmToolCall>? _mergeToolCalls(List<LlmResponse> responses) {
    final allToolCalls = <LlmToolCall>[];

    for (final response in responses) {
      if (response.toolCalls != null) {
        allToolCalls.addAll(response.toolCalls!);
      }
    }

    return allToolCalls.isEmpty ? null : allToolCalls;
  }
}

/// Simple result aggregator
class SimpleResultAggregator implements ResultAggregator {
  final SelectionStrategy _selectionStrategy;

  SimpleResultAggregator({
    SelectionStrategy selectionStrategy = SelectionStrategy.first,
  }) : _selectionStrategy = selectionStrategy;

  @override
  LlmResponse aggregate(List<LlmResponse> responses) {
    if (responses.isEmpty) {
      return LlmResponse(text: 'No responses received from any provider.');
    }

    switch (_selectionStrategy) {
      case SelectionStrategy.first:
        return responses.first;

      case SelectionStrategy.shortest:
        return responses
            .reduce((a, b) => a.text.length <= b.text.length ? a : b);

      case SelectionStrategy.longest:
        return responses
            .reduce((a, b) => a.text.length >= b.text.length ? a : b);

      case SelectionStrategy.random:
        return responses[Random().nextInt(responses.length)];
    }
  }
}

enum SelectionStrategy {
  first,
  shortest,
  longest,
  random,
}
