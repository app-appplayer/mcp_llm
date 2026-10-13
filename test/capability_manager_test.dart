import 'package:test/test.dart';
import 'dart:async';
import 'package:mcp_llm/src/capabilities/capability_manager.dart';
import 'package:mcp_llm/src/core/models.dart';

/// Mirrors what mcp_client's `Client` exposes after initialization: the
/// capabilities the server declared and the negotiated revision.
class MockCapabilityMcpClient {
  final String clientId;
  final Map<String, Map<String, dynamic>> _declared = {
    'tools': {'listChanged': true},
    'prompts': {},
    'resources': {'subscribe': true},
  };

  MockCapabilityMcpClient(this.clientId);

  void enableCapability(String capability) => _declared[capability] = {};

  void disableCapability(String capability) => _declared.remove(capability);

  Map<String, dynamic> get serverCapabilities => {..._declared};

  String get negotiatedProtocolVersion => '2025-11-25';
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
      
      // Exactly what the server declared, as declared, under the
      // negotiated revision.
      expect(capabilities.keys, unorderedEquals(['tools', 'prompts', 'resources']));
      expect(capabilities['tools']?.enabled, isTrue);
      expect(capabilities['tools']?.configuration, {'listChanged': true});
      expect(capabilities['resources']?.configuration, {'subscribe': true});
      expect(capabilities['tools']?.version, '2025-11-25');
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
      expect(toolsEvent.data['reason'], equals('Declared by the peer'));
    });

    test('should update capabilities', () async {
      capabilityManager.registerClient('client1', client1);
      await Future.delayed(Duration(milliseconds: 100));
      
      final updateRequest = CapabilityUpdateRequest(
        clientId: 'client1',
        capabilities: [
          McpCapability(
            type: McpCapabilityType.logging,
            name: 'logging',
            version: '2025-11-25',
            enabled: false,
            configuration: {},
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
      expect(capabilities.containsKey('logging'), isTrue);
      expect(capabilities['logging']?.enabled, isFalse);
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

    test('records no capability the peer did not declare', () async {
      client1.disableCapability('prompts');
      client1.enableCapability('completions');
      capabilityManager.registerClient('client1', client1);
      await Future.delayed(Duration(milliseconds: 100));

      final capabilities = capabilityManager.getClientCapabilities('client1');
      expect(capabilities.keys, unorderedEquals(['tools', 'resources', 'completions']),
          reason: 'health, batch and protocol versioning used to be read off '
              'toString() or simply added; none of them is an MCP capability');
    });

    test('a server reports its own declaration', () async {
      capabilityManager.registerClient('s', _MockServer());
      await Future.delayed(Duration(milliseconds: 100));
      final capabilities = capabilityManager.getClientCapabilities('s');
      expect(capabilities.keys, unorderedEquals(['tools', 'logging']));
      expect(capabilities['tools']?.version, '2026-07-28');
    });

    test('accepts every revision mcp_llm supports', () async {
      capabilityManager.registerClient('client1', client1);
      await Future.delayed(Duration(milliseconds: 100));
      for (final v in ['2024-11-05', '2025-03-26', '2025-06-18', '2025-11-25', '2026-07-28']) {
        final response = await capabilityManager.updateCapabilities(CapabilityUpdateRequest(
          clientId: 'client1',
          capabilities: [
            McpCapability(type: McpCapabilityType.tools, name: 'tools', version: v, enabled: true, lastUpdated: DateTime.now()),
          ],
          requestId: capabilityManager.generateRequestId(),
          timestamp: DateTime.now(),
        ));
        expect(response.success, isTrue, reason: v);
      }
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

  });
}

/// Mirrors mcp_server's `Server`: its own declaration, no negotiated revision.
class _MockServer {
  Map<String, dynamic> get capabilities => {
        'tools': {'listChanged': false},
        'logging': {},
      };
}
