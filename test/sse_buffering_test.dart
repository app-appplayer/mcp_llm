// test/sse_buffering_test.dart

import 'dart:convert';
import 'package:test/test.dart';

void main() {
  group('SSE Buffering', () {
    group('StringBuffer Line Accumulation', () {
      test('should handle complete lines', () {
        final buffer = StringBuffer();
        final lines = <String>[];

        // Simulate complete SSE data
        const data = 'data: {"text": "Hello"}\n\ndata: {"text": "World"}\n\n';

        for (final char in data.split('')) {
          buffer.write(char);

          // Check for complete line
          final content = buffer.toString();
          if (content.contains('\n\n')) {
            final parts = content.split('\n\n');
            for (int i = 0; i < parts.length - 1; i++) {
              if (parts[i].isNotEmpty) {
                lines.add(parts[i]);
              }
            }
            buffer.clear();
            buffer.write(parts.last);
          }
        }

        expect(lines.length, equals(2));
        expect(lines[0], equals('data: {"text": "Hello"}'));
        expect(lines[1], equals('data: {"text": "World"}'));
      });

      test('should handle chunked JSON data', () {
        final buffer = StringBuffer();
        final completedLines = <String>[];

        // Simulate TCP chunks splitting JSON mid-line
        final chunks = [
          'data: {"tex',
          't": "Hel',
          'lo"}\n\n',
          'data: {"text": "World"}\n\n',
        ];

        for (final chunk in chunks) {
          buffer.write(chunk);

          final content = buffer.toString();
          if (content.contains('\n\n')) {
            final parts = content.split('\n\n');
            for (int i = 0; i < parts.length - 1; i++) {
              if (parts[i].isNotEmpty) {
                completedLines.add(parts[i]);
              }
            }
            buffer.clear();
            buffer.write(parts.last);
          }
        }

        expect(completedLines.length, equals(2));
        expect(completedLines[0], equals('data: {"text": "Hello"}'));
        expect(completedLines[1], equals('data: {"text": "World"}'));
      });

      test('should handle incomplete final chunk', () {
        final buffer = StringBuffer();
        final completedLines = <String>[];

        final chunks = [
          'data: {"text": "Complete"}\n\n',
          'data: {"text": "Incomp',
        ];

        for (final chunk in chunks) {
          buffer.write(chunk);

          final content = buffer.toString();
          if (content.contains('\n\n')) {
            final parts = content.split('\n\n');
            for (int i = 0; i < parts.length - 1; i++) {
              if (parts[i].isNotEmpty) {
                completedLines.add(parts[i]);
              }
            }
            buffer.clear();
            buffer.write(parts.last);
          }
        }

        expect(completedLines.length, equals(1));
        expect(completedLines[0], equals('data: {"text": "Complete"}'));
        expect(buffer.toString(), equals('data: {"text": "Incomp'));
      });
    });

    group('JSON Parsing Safety', () {
      test('should parse complete JSON successfully', () {
        const jsonString = '{"text": "Hello", "done": false}';
        final parsed = jsonDecode(jsonString);

        expect(parsed['text'], equals('Hello'));
        expect(parsed['done'], equals(false));
      });

      test('should throw on incomplete JSON', () {
        const incompleteJson = '{"text": "Hello';

        expect(
          () => jsonDecode(incompleteJson),
          throwsFormatException,
        );
      });

      test('should throw on truncated JSON', () {
        const truncatedJson = '{"text": "Hel';

        expect(
          () => jsonDecode(truncatedJson),
          throwsFormatException,
        );
      });
    });

    group('SSE Data Line Processing', () {
      test('should extract data from SSE line', () {
        const sseLine = 'data: {"text": "Hello"}';
        String? dataContent;

        if (sseLine.startsWith('data: ')) {
          dataContent = sseLine.substring(6);
        }

        expect(dataContent, equals('{"text": "Hello"}'));
      });

      test('should handle empty data lines', () {
        const sseLine = 'data: ';
        String? dataContent;

        if (sseLine.startsWith('data: ')) {
          dataContent = sseLine.substring(6);
        }

        expect(dataContent, isEmpty);
      });

      test('should handle [DONE] marker', () {
        const sseLine = 'data: [DONE]';
        String? dataContent;
        bool isDone = false;

        if (sseLine.startsWith('data: ')) {
          dataContent = sseLine.substring(6);
          if (dataContent == '[DONE]') {
            isDone = true;
          }
        }

        expect(isDone, isTrue);
      });
    });

    group('Multi-line SSE Events', () {
      test('should handle event with multiple data lines', () {
        final lines = [
          'event: message',
          'data: {"part": 1}',
          'data: {"part": 2}',
          '',
        ];

        final dataLines = lines.where((l) => l.startsWith('data: ')).toList();

        expect(dataLines.length, equals(2));
      });

      test('should handle event with id field', () {
        final lines = [
          'id: 123',
          'event: message',
          'data: {"text": "Hello"}',
          '',
        ];

        String? eventId;
        String? eventType;
        String? data;

        for (final line in lines) {
          if (line.startsWith('id: ')) {
            eventId = line.substring(4);
          } else if (line.startsWith('event: ')) {
            eventType = line.substring(7);
          } else if (line.startsWith('data: ')) {
            data = line.substring(6);
          }
        }

        expect(eventId, equals('123'));
        expect(eventType, equals('message'));
        expect(data, equals('{"text": "Hello"}'));
      });
    });
  });
}
