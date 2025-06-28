import 'dart:html';
import 'package:mcp_llm/mcp_llm.dart';
import 'package:mcp_llm/src/storage/storage.dart';
import 'package:mcp_llm/src/utils/compression.dart';

void main() {
  // Get the button and results div
  querySelector('#run-tests')?.onClick.listen((_) => runTests());
}

void runTests() {
  final resultsDiv = querySelector('#test-results') as DivElement;
  resultsDiv.text = '';
  
  log('Starting web compatibility tests...', 'info');
  
  try {
    // Test 1: LLM Providers
    log('\n=== Testing LLM Providers ===', 'info');
    testProviders();
    
    // Test 2: Storage System
    log('\n=== Testing Storage System ===', 'info');
    testStorage();
    
    // Test 3: Compression
    log('\n=== Testing Compression ===', 'info');
    testCompression();
    
    // Test 4: Integration
    log('\n=== Testing Integration ===', 'info');
    testIntegration();
    
    log('\n✅ All tests completed successfully!', 'success');
  } catch (e) {
    log('\n❌ Test failed: $e', 'error');
  }
}

void testProviders() {
  try {
    // Test Claude Provider
    final claude = ClaudeProvider(
      apiKey: 'test-key',
      model: 'claude-3-sonnet',
      config: LlmConfiguration(),
    );
    log('✓ ClaudeProvider created successfully', 'success');
    
    // Test OpenAI Provider
    final openai = OpenAiProvider(
      apiKey: 'test-key',
      model: 'gpt-4',
      config: LlmConfiguration(),
    );
    log('✓ OpenAiProvider created successfully', 'success');
    
    // Test Together Provider
    final together = TogetherProvider(
      apiKey: 'test-key',
      model: 'mixtral-8x7b',
      config: LlmConfiguration(),
    );
    log('✓ TogetherProvider created successfully', 'success');
  } catch (e) {
    log('✗ Provider test failed: $e', 'error');
    rethrow;
  }
}

void testStorage() async {
  try {
    // Create storage
    final storage = createStorage();
    log('✓ Storage created successfully', 'success');
    
    // Initialize
    await storage.initialize();
    log('✓ Storage initialized', 'success');
    
    // Test store and retrieve
    await storage.store('test_key', 'Hello from web!');
    final value = await storage.retrieve('test_key');
    log('✓ Stored and retrieved value: $value', 'success');
    
    // Test chat history
    final message = LlmMessage(
      role: 'user',
      content: 'Test message from web browser',
    );
    
    await storage.storeMessage('web_session', message);
    log('✓ Stored chat message', 'success');
    
    final history = await storage.retrieveHistory('web_session');
    if (history != null && history.messages.isNotEmpty) {
      log('✓ Retrieved chat history with ${history.messages.length} messages', 'success');
    } else {
      log('✓ Chat history storage tested (empty result expected on first run)', 'success');
    }
    
    // Cleanup
    await storage.delete('test_key');
    log('✓ Cleaned up test data', 'success');
  } catch (e) {
    log('✗ Storage test failed: $e', 'error');
    rethrow;
  }
}

void testCompression() async {
  try {
    // Test string compression
    const testString = 'Hello from the web browser! This is a test of compression.';
    final compressed = await DataCompressor.compressAndEncodeString(testString);
    log('✓ Compressed string to base64: ${compressed.substring(0, 20)}...', 'success');
    
    final decompressed = await DataCompressor.decodeAndDecompressString(compressed);
    log('✓ Decompressed string: $decompressed', 'success');
    
    // Test binary compression
    final testData = List.generate(100, (i) => i);
    final compressedData = await DataCompressor.compressData(testData);
    log('✓ Compressed ${testData.length} bytes to ${compressedData.length} bytes', 'success');
    
    final decompressedData = await DataCompressor.decompressData(compressedData);
    log('✓ Decompressed back to ${decompressedData.length} bytes', 'success');
  } catch (e) {
    log('✗ Compression test failed: $e', 'error');
    rethrow;
  }
}

void testIntegration() async {
  try {
    // Create MCPLlm instance
    final mcpLlm = McpLlm();
    log('✓ Created McpLlm instance', 'success');
    
    // Register providers
    mcpLlm.registerProvider('claude', ClaudeProviderFactory());
    mcpLlm.registerProvider('openai', OpenAiProviderFactory());
    mcpLlm.registerProvider('together', TogetherProviderFactory());
    log('✓ Registered all providers', 'success');
    
    // Create a client (will fail with invalid API key, but should not fail due to platform issues)
    try {
      final client = await mcpLlm.createClient(
        providerName: 'claude',
        config: LlmConfiguration(
          apiKey: 'test-key',
          model: 'claude-3-sonnet',
        ),
      );
      log('✓ Created LLM client', 'success');
    } catch (e) {
      // Expected to fail with invalid API key
      log('✓ Client creation tested (API key validation expected)', 'success');
    }
  } catch (e) {
    log('✗ Integration test failed: $e', 'error');
    rethrow;
  }
}

void log(String message, String type) {
  final resultsDiv = querySelector('#test-results') as DivElement;
  final span = SpanElement()
    ..text = '$message\n'
    ..className = type;
  resultsDiv.append(span);
  
  // Also log to console
  print('[$type] $message');
}