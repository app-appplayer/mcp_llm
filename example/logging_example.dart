import 'package:mcp_llm/src/utils/logger.dart';

/// Example demonstrating the updated logging system (2025-03-26)
void main() async {
  print('=== MCP LLM Logging System Example (2025-03-26) ===\n');

  // Configure root logger to show all messages
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('[${record.level.name}] ${record.loggerName}: ${record.message}');
  });

  // Example 1: Demonstrate individual logger usage
  print('1. Demonstrating individual logger usage...\n');
  
  final logger = Logger('example.logger');
  
  // Standard logging package methods
  logger.info('This is an info message');
  logger.warning('This is a warning message');
  logger.severe('This is an error message');
  logger.fine('This is a debug message');
  
  // Extension methods for backward compatibility
  logger.debug('This is a debug message (using extension)');
  logger.error('This is an error message (using extension)');
  logger.warn('This is a warning message (using extension)');
  logger.trace('This is a trace message (using extension)');
  
  print('\n   ✅ Logger methods demonstrated\n');

  // Example 2: Configure logging levels
  print('2. Configuring logging levels...\n');
  
  // Set root logger level to INFO (will only show INFO, WARNING, SEVERE)
  Logger.root.level = Level.INFO;
  print('   Setting log level to INFO:');
  logger.fine('This debug message will NOT be shown');
  logger.info('This info message WILL be shown');
  
  // Set to FINE to show debug messages
  Logger.root.level = Level.FINE;
  print('\n   Setting log level to FINE:');
  logger.fine('This debug message WILL now be shown');
  
  print('\n   ✅ Logging levels configured\n');

  // Example 3: Namespace-based logging
  print('3. Demonstrating namespace-based logging...\n');
  
  final mcpLogger = Logger('mcp_llm.example');
  final batchLogger = Logger('mcp_llm.batch');
  final healthLogger = Logger('mcp_llm.health');
  final capabilityLogger = Logger('mcp_llm.capability');
  
  mcpLogger.info('MCP client operation completed');
  batchLogger.info('Batch processing started');
  healthLogger.info('Health check passed');
  capabilityLogger.info('Capability discovery completed');
  
  print('\n   ✅ Namespace-based logging demonstrated\n');

  // Example 4: Filtering by logger name
  print('4. Demonstrating logger name filtering...\n');
  
  // Create specific handler for MCP loggers only
  Logger.root.onRecord.listen((record) {
    if (record.loggerName.startsWith('mcp_llm')) {
      print('[MCP] ${record.level.name}: ${record.loggerName.split('.').last}: ${record.message}');
    }
  });
  
  final clientLogger = Logger('mcp_llm.client');
  final serverLogger = Logger('mcp_llm.server');
  final otherLogger = Logger('other.system');
  
  clientLogger.info('Client connected successfully');
  serverLogger.info('Server started on port 3000');
  otherLogger.info('This message will be filtered out by MCP handler');
  
  print('\n   ✅ Logger filtering demonstrated\n');
  
  print('=== Example completed successfully! ===');
  print('\nThe logging system now matches mcp_client and mcp_server:');
  print('- Uses standard Dart logging package');
  print('- Provides extension methods for backward compatibility');
  print('- Supports namespace-based organization');
  print('- Configurable log levels and filtering');
}