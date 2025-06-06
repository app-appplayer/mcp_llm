import 'package:test/test.dart';
import 'package:mcp_llm/src/core/models.dart';

void main() {
  group('2025-03-26 MCP Models Tests', () {
    group('ServerLifecycleState', () {
      test('should have all required states', () {
        expect(ServerLifecycleState.values.length, equals(7));
        expect(ServerLifecycleState.values, contains(ServerLifecycleState.stopped));
        expect(ServerLifecycleState.values, contains(ServerLifecycleState.starting));
        expect(ServerLifecycleState.values, contains(ServerLifecycleState.running));
        expect(ServerLifecycleState.values, contains(ServerLifecycleState.pausing));
        expect(ServerLifecycleState.values, contains(ServerLifecycleState.paused));
        expect(ServerLifecycleState.values, contains(ServerLifecycleState.stopping));
        expect(ServerLifecycleState.values, contains(ServerLifecycleState.error));
      });
    });

    group('McpCapability', () {
      test('should create capability with all fields', () {
        final capability = McpCapability(
          type: McpCapabilityType.tools,
          name: 'test_capability',
          version: '2025-03-26',
          enabled: true,
          configuration: {'max_tools': 10},
          lastUpdated: DateTime(2025, 3, 26),
        );

        expect(capability.type, equals(McpCapabilityType.tools));
        expect(capability.name, equals('test_capability'));
        expect(capability.version, equals('2025-03-26'));
        expect(capability.enabled, isTrue);
        expect(capability.configuration, equals({'max_tools': 10}));
        expect(capability.lastUpdated, equals(DateTime(2025, 3, 26)));
      });

      test('should create capability without configuration', () {
        final capability = McpCapability(
          type: McpCapabilityType.auth,
          name: 'oauth_capability',
          version: '2025-03-26',
          enabled: false,
          lastUpdated: DateTime.now(),
        );

        expect(capability.configuration, isNull);
      });

      test('should serialize to JSON correctly', () {
        final capability = McpCapability(
          type: McpCapabilityType.batch,
          name: 'batch_processing',
          version: '2025-03-26',
          enabled: true,
          configuration: {'max_batch_size': 100},
          lastUpdated: DateTime(2025, 3, 26, 12, 0, 0),
        );

        final json = capability.toJson();
        expect(json['type'], equals('batch'));
        expect(json['name'], equals('batch_processing'));
        expect(json['version'], equals('2025-03-26'));
        expect(json['enabled'], isTrue);
        expect(json['configuration'], equals({'max_batch_size': 100}));
        expect(json['lastUpdated'], equals('2025-03-26T12:00:00.000'));
      });

      test('should support copyWith', () {
        final original = McpCapability(
          type: McpCapabilityType.streaming,
          name: 'stream_capability',
          version: '2025-03-26',
          enabled: true,
          lastUpdated: DateTime(2025, 3, 26),
        );

        final modified = original.copyWith(
          enabled: false,
          configuration: {'buffer_size': 1024},
        );

        expect(modified.type, equals(original.type));
        expect(modified.name, equals(original.name));
        expect(modified.enabled, isFalse);
        expect(modified.configuration, equals({'buffer_size': 1024}));
      });
    });

    group('HealthReport', () {
      test('should create health report', () {
        final componentResults = {
          'client1': HealthCheckResult(
            clientId: 'client1',
            status: HealthStatus.healthy,
            metrics: {'uptime': 3600},
            timestamp: DateTime.now(),
          ),
          'client2': HealthCheckResult(
            clientId: 'client2',
            status: HealthStatus.degraded,
            metrics: {'errors': 5},
            error: 'High error rate',
            timestamp: DateTime.now(),
          ),
        };

        final report = HealthReport(
          overallStatus: HealthStatus.degraded,
          componentResults: componentResults,
          totalCheckTime: Duration(milliseconds: 250),
          timestamp: DateTime.now(),
        );

        expect(report.overallStatus, equals(HealthStatus.degraded));
        expect(report.componentResults.length, equals(2));
        expect(report.totalCheckTime.inMilliseconds, equals(250));
      });

      test('should serialize to JSON correctly', () {
        final timestamp = DateTime(2025, 3, 26, 12, 0, 0);
        final componentResults = {
          'test_client': HealthCheckResult(
            clientId: 'test_client',
            status: HealthStatus.healthy,
            metrics: {'ping': 50},
            timestamp: timestamp,
          ),
        };

        final report = HealthReport(
          overallStatus: HealthStatus.healthy,
          componentResults: componentResults,
          totalCheckTime: Duration(milliseconds: 100),
          timestamp: timestamp,
        );

        final json = report.toJson();
        expect(json['overallStatus'], equals('healthy'));
        expect(json['totalCheckTime'], equals(100));
        expect(json['timestamp'], equals('2025-03-26T12:00:00.000'));
        expect(json['componentResults'], isA<Map>());
      });
    });

    group('ServerInfo', () {
      test('should create server info', () {
        final serverInfo = ServerInfo(
          serverId: 'server_001',
          name: 'Test Server',
          state: ServerLifecycleState.running,
          uptime: Duration(hours: 24),
          metadata: {
            'version': '2025-03-26',
            'protocol': 'MCP',
          },
        );

        expect(serverInfo.serverId, equals('server_001'));
        expect(serverInfo.name, equals('Test Server'));
        expect(serverInfo.state, equals(ServerLifecycleState.running));
        expect(serverInfo.uptime.inHours, equals(24));
        expect(serverInfo.metadata['version'], equals('2025-03-26'));
      });
    });

    group('McpEnhancedError', () {
      test('should create enhanced error', () {
        final error = McpEnhancedError(
          clientId: 'client_001',
          category: McpErrorCategory.authentication,
          message: 'Invalid token',
          context: {'endpoint': '/api/tools'},
          timestamp: DateTime(2025, 3, 26),
        );

        expect(error.clientId, equals('client_001'));
        expect(error.category, equals(McpErrorCategory.authentication));
        expect(error.message, equals('Invalid token'));
        expect(error.context['endpoint'], equals('/api/tools'));
      });

      test('should handle stack trace', () {
        final stackTrace = StackTrace.current;
        final error = McpEnhancedError(
          clientId: 'client_002',
          category: McpErrorCategory.network,
          message: 'Connection timeout',
          context: {},
          timestamp: DateTime.now(),
          stackTrace: stackTrace,
        );

        expect(error.stackTrace, equals(stackTrace));
      });

      test('should serialize to JSON correctly', () {
        final error = McpEnhancedError(
          clientId: 'client_003',
          category: McpErrorCategory.validation,
          message: 'Invalid parameters',
          context: {'param': 'value'},
          timestamp: DateTime(2025, 3, 26, 12, 0, 0),
        );

        final json = error.toJson();
        expect(json['clientId'], equals('client_003'));
        expect(json['category'], equals('validation'));
        expect(json['message'], equals('Invalid parameters'));
        expect(json['context'], equals({'param': 'value'}));
        expect(json['timestamp'], equals('2025-03-26T12:00:00.000'));
      });

      test('should provide meaningful toString', () {
        final error = McpEnhancedError(
          clientId: 'client_004',
          category: McpErrorCategory.timeout,
          message: 'Request timed out',
          context: {},
          timestamp: DateTime.now(),
        );

        final str = error.toString();
        expect(str, contains('client_004'));
        expect(str, contains('timeout'));
        expect(str, contains('Request timed out'));
      });
    });

    group('CapabilityUpdateRequest', () {
      test('should create capability update request', () {
        final capabilities = [
          McpCapability(
            type: McpCapabilityType.tools,
            name: 'new_tools',
            version: '2025-03-26',
            enabled: true,
            lastUpdated: DateTime.now(),
          ),
        ];

        final request = CapabilityUpdateRequest(
          clientId: 'client_001',
          capabilities: capabilities,
          requestId: 'req_123',
          timestamp: DateTime(2025, 3, 26),
        );

        expect(request.clientId, equals('client_001'));
        expect(request.capabilities.length, equals(1));
        expect(request.requestId, equals('req_123'));
      });
    });

    group('LifecycleEvent', () {
      test('should create lifecycle event', () {
        final event = LifecycleEvent(
          serverId: 'server_001',
          previousState: ServerLifecycleState.stopped,
          newState: ServerLifecycleState.starting,
          reason: LifecycleTransitionReason.userRequest,
          timestamp: DateTime(2025, 3, 26),
        );

        expect(event.serverId, equals('server_001'));
        expect(event.previousState, equals(ServerLifecycleState.stopped));
        expect(event.newState, equals(ServerLifecycleState.starting));
        expect(event.reason, equals(LifecycleTransitionReason.userRequest));
      });

      test('should serialize to JSON correctly', () {
        final event = LifecycleEvent(
          serverId: 'server_002',
          previousState: ServerLifecycleState.running,
          newState: ServerLifecycleState.paused,
          reason: LifecycleTransitionReason.healthFailure,
          timestamp: DateTime(2025, 3, 26, 12, 0, 0),
        );

        final json = event.toJson();
        expect(json['serverId'], equals('server_002'));
        expect(json['previousState'], equals('running'));
        expect(json['newState'], equals('paused'));
        expect(json['reason'], equals('healthFailure'));
        expect(json['timestamp'], equals('2025-03-26T12:00:00.000'));
      });
    });
  });
}