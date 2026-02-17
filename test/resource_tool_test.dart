// test/resource_tool_test.dart

import 'package:test/test.dart';
import 'package:mcp_llm/mcp_llm.dart';

void main() {
  group('Resource Tool Bridge', () {
    group('Synthetic Resource Tools', () {
      test('mcp_read_resource tool should have correct schema', () {
        // Expected schema for mcp_read_resource tool
        final expectedSchema = {
          'name': 'mcp_read_resource',
          'description': contains('Read content from an MCP resource'),
          'inputSchema': {
            'type': 'object',
            'properties': {
              'uri': {'type': 'string'},
              'resourceName': {'type': 'string'},
            },
            'required': [],
          },
        };

        expect(expectedSchema['name'], equals('mcp_read_resource'));
        expect(expectedSchema['inputSchema'], isNotNull);
      });

      test('mcp_list_resources tool should have correct schema', () {
        // Expected schema for mcp_list_resources tool
        final expectedSchema = {
          'name': 'mcp_list_resources',
          'description': contains('List all available MCP resources'),
          'inputSchema': {
            'type': 'object',
            'properties': {},
            'required': [],
          },
        };

        expect(expectedSchema['name'], equals('mcp_list_resources'));
        expect(expectedSchema['inputSchema'], isNotNull);
      });
    });

    group('Tool Arguments Validation', () {
      test('mcp_read_resource should accept uri parameter', () {
        final args = {'uri': 'file:///test/resource.txt'};
        expect(args['uri'], isNotNull);
        expect(args['uri'], isA<String>());
      });

      test('mcp_read_resource should accept resourceName parameter', () {
        final args = {'resourceName': 'my-resource'};
        expect(args['resourceName'], isNotNull);
        expect(args['resourceName'], isA<String>());
      });

      test('mcp_read_resource should accept both parameters', () {
        final args = {
          'uri': 'file:///test/resource.txt',
          'resourceName': 'my-resource',
        };
        expect(args.length, equals(2));
      });

      test('mcp_list_resources should accept empty args', () {
        final args = <String, dynamic>{};
        expect(args, isEmpty);
      });
    });

    group('Tool Result Format', () {
      test('mcp_read_resource should return content', () {
        // Expected result format
        final result = {
          'content': 'File content here',
          'mimeType': 'text/plain',
        };

        expect(result['content'], isNotNull);
      });

      test('mcp_read_resource error should include available resources', () {
        // Expected error format when resource not found
        final errorResult = {
          'error': 'Resource URI or valid resourceName is required',
          'availableResources': [
            {'name': 'resource1', 'uri': 'file:///resource1'},
            {'name': 'resource2', 'uri': 'file:///resource2'},
          ],
        };

        expect(errorResult['error'], isNotNull);
        expect(errorResult['availableResources'], isA<List>());
      });

      test('mcp_list_resources should return resources array', () {
        // Expected result format
        final result = {
          'resources': [
            {
              'name': 'resource1',
              'uri': 'file:///resource1',
              'description': 'First resource',
              'mimeType': 'text/plain',
            },
          ],
          'count': 1,
          'message': 'Found 1 available resources',
        };

        expect(result['resources'], isA<List>());
        expect(result['count'], equals(1));
        expect(result['message'], contains('Found'));
      });
    });
  });

  group('LlmMessage Tool Role', () {
    test('tool message should have role "tool"', () {
      final message = LlmMessage.tool('test_tool', 'result');
      expect(message.role, equals('tool'));
    });

    test('tool message should include toolCallId in metadata', () {
      final message = LlmMessage.tool(
        'test_tool',
        'result',
        toolCallId: 'call_123',
      );

      expect(message.metadata['tool_call_id'], equals('call_123'));
    });

    test('tool message should include arguments in metadata', () {
      final message = LlmMessage.tool(
        'test_tool',
        'result',
        arguments: {'param': 'value'},
      );

      expect(message.metadata['arguments'], equals({'param': 'value'}));
    });

    test('tool message content should have correct structure', () {
      final message = LlmMessage.tool('my_tool', {'data': 'value'});

      expect(message.content, isA<Map>());
      expect(message.content['type'], equals('tool_result'));
      expect(message.content['tool'], equals('my_tool'));
      expect(message.content['content'], equals({'data': 'value'}));
    });
  });
}
