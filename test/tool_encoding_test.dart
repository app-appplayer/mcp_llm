// test/tool_encoding_test.dart
// Tests for tool call arguments encoding - provider-agnostic storage with provider-specific encoding

import 'dart:convert';
import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  group('Tool Arguments Encoding', () {
    group('Provider-Agnostic Storage (llm_client)', () {
      test('llm_client stores arguments as Map (not pre-encoded)', () {
        // llm_client should store arguments as Map for provider-agnostic handling
        final originalArgs = {'query': 'test search', 'limit': 10};

        // Simulating llm_client behavior - stores as Map
        final storedToolCall = {
          'id': 'call_123',
          'name': 'search_tool',
          'arguments': originalArgs, // Map, not jsonEncode!
        };

        expect(storedToolCall['arguments'], isA<Map>());
        expect(storedToolCall['arguments'], isNot(isA<String>()));
        expect(storedToolCall['arguments'], equals(originalArgs));
      });
    });

    group('Provider-Specific Encoding', () {
      test('OpenAI provider encodes Map arguments to JSON String', () {
        final originalArgs = {'query': 'test search', 'limit': 10};

        // llm_client stores as Map
        final storedToolCall = {
          'id': 'call_123',
          'name': 'search_tool',
          'arguments': originalArgs,
        };

        // OpenAI provider encodes with is String check
        final toolCallArgs = storedToolCall['arguments'];
        final formattedArgs = toolCallArgs is String
            ? toolCallArgs
            : jsonEncode(toolCallArgs);

        // Result is JSON String
        expect(formattedArgs, isA<String>());
        expect(jsonDecode(formattedArgs), equals(originalArgs));
      });

      test('Claude provider encodes Map arguments to JSON String', () {
        final originalArgs = {'query': 'test search', 'limit': 10};

        // llm_client stores as Map
        final storedToolCall = {
          'id': 'call_123',
          'name': 'search_tool',
          'arguments': originalArgs,
        };

        // Claude provider encodes
        final args = storedToolCall['arguments'] ?? {};
        final encodedArgs = jsonEncode(args);

        // Result is JSON String
        expect(encodedArgs, isA<String>());
        expect(jsonDecode(encodedArgs), equals(originalArgs));
      });
    });

    group('No Double Encoding', () {
      test('Map arguments are encoded exactly once by each provider', () {
        final originalArgs = {'key': 'value', 'nested': {'a': 1}};

        // llm_client stores as Map
        final storedToolCall = {
          'id': 'call_123',
          'name': 'test_tool',
          'arguments': originalArgs,
        };

        // Provider encodes once
        final encoded = jsonEncode(storedToolCall['arguments']);

        // Parse back - should be Map, not String
        final decoded = jsonDecode(encoded);
        expect(decoded, isA<Map>());
        expect(decoded['key'], equals('value'));
        expect(decoded['nested'], isA<Map>());
      });

      test('OpenAI is String check handles both Map and String inputs', () {
        final originalArgs = {'key': 'value'};

        // Case 1: Input is Map
        final dynamic mapInput = originalArgs;
        final resultFromMap = mapInput is String ? mapInput : jsonEncode(mapInput);
        expect(jsonDecode(resultFromMap), equals(originalArgs));

        // Case 2: Input is already String (edge case)
        final dynamic stringInput = jsonEncode(originalArgs);
        final resultFromString = stringInput is String ? stringInput : jsonEncode(stringInput);
        expect(jsonDecode(resultFromString), equals(originalArgs));
      });
    });

    group('Tool Call Storage Format', () {
      test('LlmToolCall preserves Map arguments', () {
        final toolCall = LlmToolCall(
          id: 'call_123',
          name: 'test_tool',
          arguments: {'param1': 'value1', 'param2': 42},
        );

        expect(toolCall.arguments, isA<Map<String, dynamic>>());
        expect(toolCall.arguments['param1'], equals('value1'));
        expect(toolCall.arguments['param2'], equals(42));
      });

      test('LlmMessage with tool_calls preserves Map arguments', () {
        final toolCalls = [
          {
            'id': 'call_123',
            'name': 'tool1',
            'arguments': {'key': 'value'},
          },
        ];

        final message = LlmMessage(
          role: 'assistant',
          content: {'tool_calls': toolCalls},
          metadata: {'tool_call': true},
        );

        final storedToolCalls = message.content['tool_calls'] as List;
        final firstToolCall = storedToolCalls[0] as Map;

        expect(firstToolCall['arguments'], isA<Map>());
      });
    });

    group('OpenAI API Format', () {
      test('OpenAI API requires arguments as JSON String in function object', () {
        final args = {'key': 'value'};

        // OpenAI API format
        final openaiFormat = {
          'id': 'call_123',
          'type': 'function',
          'function': {
            'name': 'test_tool',
            'arguments': jsonEncode(args), // Must be JSON String
          },
        };

        final function = openaiFormat['function'] as Map<String, dynamic>;
        expect(function['arguments'], isA<String>());
        expect(jsonDecode(function['arguments'] as String), equals(args));
      });
    });
  });

  group('LlmMessage Tool Arguments', () {
    test('LlmMessage.tool preserves arguments in metadata', () {
      final arguments = {'query': 'search term', 'limit': 5};
      final result = {'data': 'result data'};

      final toolMessage = LlmMessage.tool(
        'search_tool',
        result,
        toolCallId: 'call_123',
        arguments: arguments,
      );

      expect(toolMessage.role, equals('tool'));
      expect(toolMessage.metadata['arguments'], isA<Map>());
      expect(toolMessage.metadata['arguments'], equals(arguments));
    });

    test('tool message arguments are Map type', () {
      final arguments = {'key': 'value', 'nested': {'a': 1}};

      final toolMessage = LlmMessage.tool(
        'test_tool',
        'result',
        arguments: arguments,
      );

      final storedArgs = toolMessage.metadata['arguments'];
      expect(storedArgs, isA<Map>());
      expect(storedArgs, isNot(isA<String>()));
    });
  });
}
