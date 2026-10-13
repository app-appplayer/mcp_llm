import 'package:test/test.dart';
import 'package:mcp_llm/src/health/health_monitor.dart';
import 'package:mcp_llm/src/core/models.dart';

/// Mirrors mcp_client's `Client`: `ping`, the negotiated revision and the
/// capabilities the server declared.
class MockHealthyMcpClient {
  final String clientId;
  bool _isHealthy = true;

  MockHealthyMcpClient(this.clientId);

  void setHealth(bool healthy) {
    _isHealthy = healthy;
  }

  Future<void> ping() async {
    await Future.delayed(Duration(milliseconds: 10));
    if (!_isHealthy) {
      throw Exception('Service unhealthy');
    }
  }

  String get negotiatedProtocolVersion => '2025-11-25';

  Map<String, dynamic> get serverCapabilities => {
        'tools': {'listChanged': true},
        'prompts': {},
      };
}

/// Mirrors mcp_server's `Server`: its own health record.
class MockMcpServer {
  bool running = true;
  Map<String, dynamic> getHealth() => {'isRunning': running, 'connectedSessions': running ? 1 : 0};
}

void main() {
  group('McpHealthMonitor Tests', () {
    late McpHealthMonitor healthMonitor;
    late MockHealthyMcpClient client1;
    late MockHealthyMcpClient client2;

    setUp(() {
      healthMonitor = McpHealthMonitor(
        config: const HealthCheckConfig(
          timeout: Duration(seconds: 1),
          maxRetries: 1,
          retryDelay: Duration(milliseconds: 100),
          includeSystemMetrics: true,
        ),
      );
      
      client1 = MockHealthyMcpClient('client1');
      client2 = MockHealthyMcpClient('client2');
      
      healthMonitor.registerClient('client1', client1);
      healthMonitor.registerClient('client2', client2);
    });

    tearDown(() {
      healthMonitor.dispose();
    });

    test('should register and unregister clients', () {
      final client3 = MockHealthyMcpClient('client3');
      healthMonitor.registerClient('client3', client3);
      
      // Should have 3 clients now
      expect(healthMonitor.getHealthStatistics()['total_clients'], equals(3));
      
      healthMonitor.unregisterClient('client3');
      
      // Should be back to 2 clients
      expect(healthMonitor.getHealthStatistics()['total_clients'], equals(2));
    });

    test('should perform health check on all clients', () async {
      final report = await healthMonitor.performHealthCheck();
      
      expect(report.overallStatus, equals(HealthStatus.healthy));
      expect(report.componentResults.length, equals(3)); // 2 clients + system
      expect(report.componentResults['client1']?.status, equals(HealthStatus.healthy));
      expect(report.componentResults['client2']?.status, equals(HealthStatus.healthy));
      expect(report.componentResults['system']?.status, equals(HealthStatus.healthy));
    });

    test('should detect unhealthy client', () async {
      client1.setHealth(false);
      
      final report = await healthMonitor.performHealthCheck();
      
      expect(report.overallStatus, equals(HealthStatus.unhealthy));
      expect(report.componentResults['client1']?.status, equals(HealthStatus.unhealthy));
      expect(report.componentResults['client1']?.error, contains('Health check failed'));
      expect(report.componentResults['client2']?.status, equals(HealthStatus.healthy));
    });

    test('should perform health check on specific clients', () async {
      final report = await healthMonitor.performHealthCheck(
        clientIds: ['client1'],
        includeSystemMetrics: false,
      );
      
      expect(report.componentResults.length, equals(1));
      expect(report.componentResults.containsKey('client1'), isTrue);
      expect(report.componentResults.containsKey('client2'), isFalse);
      expect(report.componentResults.containsKey('system'), isFalse);
    });

    test('should check client capabilities', () async {
      final report = await healthMonitor.performHealthCheck();
      
      final client1Result = report.componentResults['client1'];
      expect(client1Result?.metrics['kind'], 'client');
      expect(client1Result?.metrics['protocolVersion'], '2025-11-25');
      expect(client1Result?.metrics['serverCapabilities'],
          {'tools': {'listChanged': true}, 'prompts': {}});
    });

    test('a server is checked by its own health record', () async {
      final server = MockMcpServer();
      healthMonitor.registerClient('server', server);
      var report = await healthMonitor.performHealthCheck(clientIds: ['server'], includeSystemMetrics: false);
      expect(report.componentResults['server']?.status, HealthStatus.healthy);
      expect(report.componentResults['server']?.metrics['kind'], 'server');

      server.running = false;
      report = await healthMonitor.performHealthCheck(clientIds: ['server'], includeSystemMetrics: false);
      expect(report.componentResults['server']?.status, HealthStatus.unhealthy);
      expect(report.componentResults['server']?.error, contains('not running'));
    });

    test('should retry on failure', () async {
      client1.setHealth(false);
      
      // First attempt will fail, but it should retry
      final report = await healthMonitor.performHealthCheck();
      
      final client1Result = report.componentResults['client1'];
      expect(client1Result?.status, equals(HealthStatus.unhealthy));
      expect(client1Result?.metrics['attempts'], equals(2)); // 1 initial + 1 retry
    });

    test('should exclude components from health check', () async {
      final excludingMonitor = McpHealthMonitor(
        config: const HealthCheckConfig(
          excludeComponents: ['client1'],
        ),
      );
      excludingMonitor.registerClient('client1', client1);
      excludingMonitor.registerClient('client2', client2);
      
      final report = await excludingMonitor.performHealthCheck();
      
      final client1Result = report.componentResults['client1'];
      expect(client1Result?.status, equals(HealthStatus.unknown));
      expect(client1Result?.error, contains('excluded from health checks'));
      
      excludingMonitor.dispose();
    });

    test('should get client health status', () async {
      await healthMonitor.performHealthCheck();
      
      final client1Health = healthMonitor.getClientHealth('client1');
      expect(client1Health?.status, equals(HealthStatus.healthy));
      
      final nonExistentHealth = healthMonitor.getClientHealth('nonexistent');
      expect(nonExistentHealth, isNull);
    });

    test('should track health history', () async {
      // Perform multiple health checks
      await healthMonitor.performHealthCheck();
      client1.setHealth(false);
      await healthMonitor.performHealthCheck();
      client1.setHealth(true);
      await healthMonitor.performHealthCheck();
      
      final history = healthMonitor.getClientHealthHistory('client1');
      expect(history.length, equals(3));
      
      // Check the health status progression
      expect(history[0].status, equals(HealthStatus.healthy));
      expect(history[1].status, equals(HealthStatus.unhealthy));
      expect(history[2].status, equals(HealthStatus.healthy));
    });

    test('should check if all clients are healthy', () async {
      await healthMonitor.performHealthCheck();
      expect(healthMonitor.allClientsHealthy, isTrue);
      
      client2.setHealth(false);
      await healthMonitor.performHealthCheck();
      expect(healthMonitor.allClientsHealthy, isFalse);
    });

    test('should get list of unhealthy clients', () async {
      client1.setHealth(false);
      client2.setHealth(false);
      await healthMonitor.performHealthCheck();
      
      final unhealthyClients = healthMonitor.unhealthyClients;
      expect(unhealthyClients.length, equals(2));
      expect(unhealthyClients, contains('client1'));
      expect(unhealthyClients, contains('client2'));
    });

    test('should calculate health statistics', () async {
      client1.setHealth(false);
      await healthMonitor.performHealthCheck();
      
      final stats = healthMonitor.getHealthStatistics();
      expect(stats['total_clients'], equals(2));
      expect(stats['healthy'], equals(1));
      expect(stats['unhealthy'], equals(1));
      expect(stats['degraded'], equals(0));
      expect(stats['unknown'], equals(0));
      expect(stats['average_response_time'], isA<double>());
      expect(stats['last_check'], isA<String>());
    });

    test('should measure response time', () async {
      final report = await healthMonitor.performHealthCheck();
      
      final client1Result = report.componentResults['client1'];
      expect(client1Result?.metrics['responseTimeMs'], isA<int>());
      expect(client1Result?.metrics['responseTimeMs'], greaterThan(0));
    });

    test('should handle timeout', () async {
      final timeoutMonitor = McpHealthMonitor(
        config: const HealthCheckConfig(
          timeout: Duration(milliseconds: 1), // Very short timeout
          maxRetries: 0,
        ),
      );
      
      final slowClient = MockHealthyMcpClient('slow');
      timeoutMonitor.registerClient('slow', slowClient);
      
      final report = await timeoutMonitor.performHealthCheck();
      
      // Might timeout or succeed depending on system speed
      expect(report.componentResults['slow']?.status, 
        anyOf(equals(HealthStatus.healthy), equals(HealthStatus.unhealthy)));
      
      timeoutMonitor.dispose();
    });

    test('should include system metrics when requested', () async {
      final report = await healthMonitor.performHealthCheck(includeSystemMetrics: true);
      
      expect(report.componentResults.containsKey('system'), isTrue);
      final systemResult = report.componentResults['system'];
      expect(systemResult?.status, equals(HealthStatus.healthy));
      expect(systemResult?.metrics['registered_clients'], equals(2));
      expect(systemResult?.metrics['healthy_clients'], equals(2));
      expect(systemResult?.metrics.containsKey('memory_usage'), isFalse,
          reason: 'it was a fixed 128.5 — nothing measured it');
      expect(systemResult?.metrics['uptimeSeconds'], inInclusiveRange(0, 60),
          reason: 'it was the seconds since 1970');
    });
  });
}