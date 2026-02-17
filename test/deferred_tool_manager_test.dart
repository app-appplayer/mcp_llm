// test/deferred_tool_manager_test.dart

import 'package:test/test.dart';
import 'package:mcp_llm/src/deferred/deferred_tool_manager.dart';
import 'package:mcp_llm/src/core/models.dart';

void main() {
  group('DeferredToolManager', () {
    late DeferredToolManager manager;

    setUp(() {
      manager = DeferredToolManager();
    });

    group('Initialization', () {
      test('should start uninitialized', () {
        expect(manager.isInitialized, isFalse);
        expect(manager.count, equals(0));
      });

      test('should have empty tool names initially', () {
        expect(manager.toolNames, isEmpty);
      });
    });

    group('Tool Caching', () {
      test('should check if tool exists', () {
        expect(manager.hasTool('non_existent'), isFalse);
      });

      test('should return null for non-existent tool metadata', () {
        expect(manager.getMetadata('non_existent'), isNull);
      });

      test('should return null for non-existent tool schema', () {
        expect(manager.getFullSchema('non_existent'), isNull);
      });
    });

    group('Validation', () {
      test('should return invalid for non-existent tool', () {
        final result = manager.validateToolCall('non_existent', {});

        expect(result.isValid, isFalse);
        expect(result.error, contains('Tool not found'));
      });
    });

    group('Reset', () {
      test('should reset initialization state', () {
        manager.reset();

        expect(manager.isInitialized, isFalse);
        expect(manager.count, equals(0));
        expect(manager.toolNames, isEmpty);
      });
    });

    group('Invalidate', () {
      test('should clear all data on invalidate', () {
        manager.invalidate();

        expect(manager.isInitialized, isFalse);
        expect(manager.count, equals(0));
      });
    });
  });

  group('ValidationResult', () {
    test('should create valid result', () {
      final result = ValidationResult.valid();

      expect(result.isValid, isTrue);
      expect(result.error, isNull);
    });

    test('should create invalid result with error', () {
      final result = ValidationResult.invalid('Missing parameter');

      expect(result.isValid, isFalse);
      expect(result.error, equals('Missing parameter'));
    });

    test('should have meaningful toString', () {
      final valid = ValidationResult.valid();
      final invalid = ValidationResult.invalid('Test error');

      expect(valid.toString(), contains('valid'));
      expect(invalid.toString(), contains('invalid'));
      expect(invalid.toString(), contains('Test error'));
    });
  });

  group('LlmToolMetadata', () {
    test('should create from map', () {
      final map = {
        'name': 'test_tool',
        'description': 'A test tool',
      };

      final metadata = LlmToolMetadata.fromMap(map);

      expect(metadata.name, equals('test_tool'));
      expect(metadata.description, equals('A test tool'));
    });

    test('should convert to JSON', () {
      final metadata = LlmToolMetadata(
        name: 'my_tool',
        description: 'My tool description',
      );

      final json = metadata.toJson();

      expect(json['name'], equals('my_tool'));
      expect(json['description'], equals('My tool description'));
    });
  });
}
