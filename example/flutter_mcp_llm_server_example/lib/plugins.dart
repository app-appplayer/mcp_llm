import 'package:mcp_llm/mcp_llm.dart';

class EchoToolPlugin extends BaseToolPlugin {
  EchoToolPlugin() : super(
    name: 'echo',
    version: '1.0.0',
    description: 'Echoes back the input message with optional transformation',
    inputSchema: {
      'type': 'object',
      'properties': {
        'message': {
          'type': 'string',
          'description': 'Message to echo back'
        },
        'uppercase': {
          'type': 'boolean',
          'description': 'Whether to convert to uppercase',
          'default': false
        }
      },
      'required': ['message']
    },
  );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> arguments) async {
    final message = arguments['message'] as String;
    final uppercase = arguments['uppercase'] as bool? ?? false;

    final result = uppercase ? message.toUpperCase() : message;

    Logger.getLogger('LlmServerDemo').debug(message);
    return LlmCallToolResult([
      LlmTextContent(text: result),
    ]);
  }
}

class CalculatorToolPlugin extends BaseToolPlugin {
  CalculatorToolPlugin() : super(
    name: 'calculator',
    version: '1.0.0',
    description: 'Performs basic arithmetic operations',
    inputSchema: {
      'type': 'object',
      'properties': {
        'operation': {
          'type': 'string',
          'description': 'The operation to perform (add, subtract, multiply, divide)',
          'enum': ['add', 'subtract', 'multiply', 'divide']
        },
        'a': {
          'type': 'number',
          'description': 'First number'
        },
        'b': {
          'type': 'number',
          'description': 'Second number'
        }
      },
      'required': ['operation', 'a', 'b']
    },
  );

  @override
  Future<LlmCallToolResult> onExecute(Map<String, dynamic> arguments) async {
    final operation = arguments['operation'] as String;
    final a = (arguments['a'] as num).toDouble();
    final b = (arguments['b'] as num).toDouble();

    double result;
    switch (operation) {
      case 'add':
        result = a + b;
        break;
      case 'subtract':
        result = a - b;
        break;
      case 'multiply':
        result = a * b;
        break;
      case 'divide':
        if (b == 0) {
          throw Exception('Division by zero');
        }
        result = a / b;
        break;
      default:
        throw Exception('Unknown operation: $operation');
    }

    Logger.getLogger('LlmServerDemo').debug('$result');
    return LlmCallToolResult([
      LlmTextContent(text: result.toString()),
    ]);
  }
}