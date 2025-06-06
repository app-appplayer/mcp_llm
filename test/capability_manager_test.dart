import 'package:test/test.dart';
import 'dart:async';
import 'package:mcp_llm/src/capabilities/capability_manager.dart';
import 'package:mcp_llm/src/core/models.dart';

/// Mock MCP client for capability testing
class MockCapabilityMcpClient {
  final String clientId;
  final Map<String, bool> _capabilities = {
    'tools': true,
    'prompts': true,
    'resources': true,
    'batch': false,
    'health': false,
  };
  
  MockCapabilityMcpClient(this.clientId);
  
  void enableCapability(String capability) {
    _capabilities[capability] = true;
  }
  
  void disableCapability(String capability) {
    _capabilities[capability] = false;
  }
  
  Future<List<dynamic>> listTools() async {
    if (_capabilities['tools'] != true) {
      throw Exception('Tools capability not supported');
    }
    await Future.delayed(Duration(milliseconds: 10));
    return [
      {'name': 'tool1', 'description': 'Test tool 1'},
      {'name': 'tool2', 'description': 'Test tool 2'},
    ];
  }
  
  Future<List<dynamic>> listPrompts() async {
    if (_capabilities['prompts'] != true) {
      throw Exception('Prompts capability not supported');
    }
    await Future.delayed(Duration(milliseconds: 10));
    return [
      {'name': 'prompt1', 'description': 'Test prompt'},
    ];
  }
  
  Future<List<dynamic>> listResources() async {
    if (_capabilities['resources'] != true) {
      throw Exception('Resources capability not supported');
    }
    await Future.delayed(Duration(milliseconds: 10));
    return [
      {'name': 'resource1', 'uri': 'test://resource'},
    ];
  }
  
  @override
  String toString() {
    // Simulate batch support check
    return _capabilities['batch'] == true ? 'MockClient with batch support' : 'MockClient';
  }
}

void main() {
  group('McpCapabilityManager Tests', () {
    late McpCapabilityManager capabilityManager;
    late MockCapabilityMcpClient client1;
    late MockCapabilityMcpClient client2;
    late StreamSubscription<CapabilityEvent> eventSubscription;
    late List<CapabilityEvent> capturedEvents;

    setUp(() {
      capabilityManager = McpCapabilityManager();
      client1 = MockCapabilityMcpClient('client1');
      client2 = MockCapabilityMcpClient('client2');
      capturedEvents = [];
      
      eventSubscription = capabilityManager.events.listen((event) {
        capturedEvents.add(event);
      });
    });

    tearDown(() async {
      await eventSubscription.cancel();
      capabilityManager.dispose();
    });

    test('should register and unregister clients', () async {
      capabilityManager.registerClient('client1', client1);
      
      // Give time for capability discovery
      await Future.delayed(Duration(milliseconds: 100));
      
      final capabilities = capabilityManager.getClientCapabilities('client1');
      expect(capabilities.length, greaterThan(0));
      
      capabilityManager.unregisterClient('client1');
      
      final afterUnregister = capabilityManager.getClientCapabilities('client1');
      expect(afterUnregister.isEmpty, isTrue);
    });

    test('should discover client capabilities automatically', () async {
      capabilityManager.registerClient('client1', client1);
      
      // Wait for discovery
      await Future.delayed(Duration(milliseconds: 100));
      
      final capabilities = capabilityManager.getClientCapabilities('client1');
      
      // Should have discovered tools, prompts, and resources
      expect(capabilities.containsKey('tools'), isTrue);
      expect(capabilities['tools']?.enabled, isTrue);
      expect(capabilities['tools']?.configuration?['tool_count'], equals(2));
      
      expect(capabilities.containsKey('prompts'), isTrue);
      expect(capabilities['prompts']?.enabled, isTrue);
      expect(capabilities['prompts']?.configuration?['prompt_count'], equals(1));
      
      expect(capabilities.containsKey('resources'), isTrue);
      expect(capabilities['resources']?.enabled, isTrue);
      expect(capabilities['resources']?.configuration?['resource_count'], equals(1));
    });

    test('should emit capability events', () async {
      capabilityManager.registerClient('client1', client1);
      
      // Wait for discovery events
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(capturedEvents.length, greaterThan(0));
      
      final toolsEvent = capturedEvents.firstWhere(
        (e) => e.capabilityName == 'tools',
        orElse: () => throw Exception('No tools event found'),
      );
      
      expect(toolsEvent.clientId, equals('client1'));
      expect(toolsEvent.type, equals(CapabilityEventType.enabled));
      expect(toolsEvent.data['reason'], equals('Initial discovery'));
    });

    test('should update capabilities', () async {
      capabilityManager.registerClient('client1', client1);
      await Future.delayed(Duration(milliseconds: 100));
      
      final updateRequest = CapabilityUpdateRequest(
        clientId: 'client1',
        capabilities: [
          McpCapability(
            type: McpCapabilityType.batch,
            name: 'batch_processing',
            version: '2025-03-26',
            enabled: true,
            configuration: {'max_batch_size': 10},
            lastUpdated: DateTime.now(),
          ),
        ],
        requestId: capabilityManager.generateRequestId(),
        timestamp: DateTime.now(),
      );
      
      final response = await capabilityManager.updateCapabilities(updateRequest);
      
      expect(response.success, isTrue);
      expect(response.updatedCapabilities.length, equals(1));
      expect(response.error, isNull);
      
      final capabilities = capabilityManager.getClientCapabilities('client1');
      expect(capabilities.containsKey('batch_processing'), isTrue);
      expect(capabilities['batch_processing']?.enabled, isTrue);
      expect(capabilities['batch_processing']?.configuration?['max_batch_size'], equals(10));
    });

    test('should handle update failures', () async {
      final updateRequest = CapabilityUpdateRequest(
        clientId: 'nonexistent',
        capabilities: [
          McpCapability(
            type: McpCapabilityType.tools,
            name: 'test',
            version: '2025-03-26',
            enabled: true,
            lastUpdated: DateTime.now(),
          ),
        ],
        requestId: capabilityManager.generateRequestId(),
        timestamp: DateTime.now(),
      );
      
      final response = await capabilityManager.updateCapabilities(updateRequest);
      
      expect(response.success, isFalse);
      expect(response.error, contains('Client not found'));
    });

    test('should enable and disable capabilities', () async {
      capabilityManager.registerClient('client1', client1);
      await Future.delayed(Duration(milliseconds: 100));
      
      // Initially enabled
      var capability = capabilityManager.getClientCapability('client1', 'tools');
      expect(capability?.enabled, isTrue);
      
      // Disable
      final disableResult = await capabilityManager.disableCapability('client1', 'tools');
      expect(disableResult, isTrue);
      
      capability = capabilityManager.getClientCapability('client1', 'tools');
      expect(capability?.enabled, isFalse);
      
      // Re-enable
      final enableResult = await capabilityManager.enableCapability('client1', 'tools');
      expect(enableResult, isTrue);
      
      capability = capabilityManager.getClientCapability('client1', 'tools');
      expect(capability?.enabled, isTrue);
    });

    test('should get all capabilities across clients', () async {
      capabilityManager.registerClient('client1', client1);
      capabilityManager.registerClient('client2', client2);
      
      await Future.delayed(Duration(milliseconds: 100));
      
      final allCapabilities = capabilityManager.getAllCapabilities();
      
      expect(allCapabilities.containsKey('client1'), isTrue);
      expect(allCapabilities.containsKey('client2'), isTrue);
      expect(allCapabilities['client1']?.isNotEmpty, isTrue);
      expect(allCapabilities['client2']?.isNotEmpty, isTrue);
    });

    test('should get capability statistics', () async {
      capabilityManager.registerClient('client1', client1);
      capabilityManager.registerClient('client2', client2);
      
      await Future.delayed(Duration(milliseconds: 100));
      
      final stats = capabilityManager.getCapabilityStatistics();
      
      expect(stats['total_clients'], equals(2));
      expect(stats['total_capabilities'], greaterThan(0));
      expect(stats['enabled_capabilities'], greaterThan(0));
      expect(stats['capabilities_by_type'], isA<Map>());
      
      final byType = stats['capabilities_by_type'] as Map;
      expect(byType['tools'], greaterThan(0));
      expect(byType['prompts'], greaterThan(0));
      expect(byType['resources'], greaterThan(0));
    });

    test('should maintain update history', () async {
      capabilityManager.registerClient('client1', client1);
      await Future.delayed(Duration(milliseconds: 100));
      
      // Perform multiple updates
      for (int i = 0; i < 3; i++) {
        final updateRequest = CapabilityUpdateRequest(
          clientId: 'client1',
          capabilities: [
            McpCapability(
              type: McpCapabilityType.tools,
              name: 'test_update_$i',
              version: '2025-03-26',
              enabled: true,
              lastUpdated: DateTime.now(),
            ),
          ],
          requestId: capabilityManager.generateRequestId(),
          timestamp: DateTime.now(),
        );
        
        await capabilityManager.updateCapabilities(updateRequest);
      }
      
      final history = capabilityManager.getUpdateHistory('client1');
      expect(history.length, equals(3));
    });

    test('should refresh all capabilities', () async {
      capabilityManager.registerClient('client1', client1);
      capabilityManager.registerClient('client2', client2);
      
      await Future.delayed(Duration(milliseconds: 100));
      
      final beforeRefresh = capturedEvents.length;
      
      await capabilityManager.refreshAllCapabilities();
      
      await Future.delayed(Duration(milliseconds: 100));
      
      // Should have more events after refresh
      expect(capturedEvents.length, greaterThan(beforeRefresh));
    });

    test('should generate unique request IDs', () async {
      final id1 = capabilityManager.generateRequestId();
      await Future.delayed(Duration(milliseconds: 2)); // Ensure time difference
      final id2 = capabilityManager.generateRequestId();
      
      expect(id1, isNot(equals(id2)));
      expect(id1, startsWith('cap_'));
      expect(id2, startsWith('cap_'));
    });

    test('should check modern capabilities', () async {
      client1.enableCapability('batch');
      client1.enableCapability('health');
      
      capabilityManager.registerClient('client1', client1);
      
      await Future.delayed(Duration(milliseconds: 100));
      
      final capabilities = capabilityManager.getClientCapabilities('client1');
      
      // Should have protocol versioning capability
      expect(capabilities.containsKey('protocol_versioning'), isTrue);
      expect(capabilities['protocol_versioning']?.enabled, isTrue);
      
      final supportedVersions = capabilities['protocol_versioning']
          ?.configuration?['supported_versions'] as List?;
      expect(supportedVersions, contains('2025-03-26'));
    });

    test('should validate capability updates', () async {
      capabilityManager.registerClient('client1', client1);
      await Future.delayed(Duration(milliseconds: 100));
      
      // Invalid version
      final invalidVersionRequest = CapabilityUpdateRequest(
        clientId: 'client1',
        capabilities: [
          McpCapability(
            type: McpCapabilityType.tools,
            name: 'test',
            version: '1999-01-01', // Unsupported version
            enabled: true,
            lastUpdated: DateTime.now(),
          ),
        ],
        requestId: capabilityManager.generateRequestId(),
        timestamp: DateTime.now(),
      );
      
      final response = await capabilityManager.updateCapabilities(invalidVersionRequest);
      expect(response.success, isFalse);
      expect(response.error, contains('Unsupported capability version'));
    });

    test('should validate capability configuration', () async {
      capabilityManager.registerClient('client1', client1);
      await Future.delayed(Duration(milliseconds: 100));
      
      // Invalid batch size
      final invalidConfigRequest = CapabilityUpdateRequest(
        clientId: 'client1',
        capabilities: [
          McpCapability(
            type: McpCapabilityType.batch,
            name: 'batch',
            version: '2025-03-26',
            enabled: true,
            configuration: {'max_batch_size': 1000}, // Too large
            lastUpdated: DateTime.now(),
          ),
        ],
        requestId: capabilityManager.generateRequestId(),
        timestamp: DateTime.now(),
      );
      
      final response = await capabilityManager.updateCapabilities(invalidConfigRequest);
      expect(response.success, isFalse);
      expect(response.error, contains('Invalid max_batch_size'));
    });
  });
}