import '../../mcp_llm.dart';
import '../core/models.dart';

/// 다중 MCP 클라이언트를 관리하는 클래스
class MultiClientManager {
  final Map<String, LlmClient> _clients = {};
  final ClientRouter _router = ClientRouter();
  final LoadBalancer _loadBalancer = LoadBalancer();
  final Logger _logger = Logger.getLogger('mcp_llm.client_manager');

  /// 새 클라이언트 추가
  void addClient(String clientId, LlmClient client, {
    Map<String, dynamic>? routingProperties,
    double loadWeight = 1.0,
  }) {
    _clients[clientId] = client;

    if (routingProperties != null) {
      _router.registerClient(clientId, routingProperties);
    }

    _loadBalancer.registerClient(clientId, weight: loadWeight);
    _logger.info('Added client: $clientId');
  }

  /// 클라이언트 제거
  Future<void> removeClient(String clientId) async {
    final client = _clients.remove(clientId);
    if (client != null) {
      await client.close();
      _router.unregisterClient(clientId);
      _loadBalancer.unregisterClient(clientId);
      _logger.info('Removed client: $clientId');
    }
  }

  LlmClient? getClient(String clientId) {
    return _clients[clientId];
  }

  /// 쿼리에 가장 적합한 클라이언트 선택
  LlmClient? selectClient(String query, {Map<String, dynamic>? properties}) {
    // 쿼리 특성에 따라 라우팅
    String? clientId = _router.routeQuery(query, properties);

    // 라우팅 결과가 없으면 로드 밸런서 사용
    if (clientId == null || !_clients.containsKey(clientId)) {
      clientId = _loadBalancer.getNextClient();
    }

    return clientId != null ? _clients[clientId] : null;
  }

  /// 모든 클라이언트에 동일 작업 실행 (팬아웃)
  Future<Map<String, LlmResponse>> fanOutQuery(String query, {
    bool enableTools = true,
    Map<String, dynamic> parameters = const {},
  }) async {
    final results = <String, LlmResponse>{};
    final futures = <Future<void>>[];

    for (final entry in _clients.entries) {
      futures.add(_executeClientQuery(
          entry.key,
          entry.value,
          query,
          enableTools,
          parameters
      ).then((response) {
        results[entry.key] = response;
      }));
    }

    await Future.wait(futures);
    return results;
  }

  // 개별 클라이언트 쿼리 실행 헬퍼 메서드
  Future<LlmResponse> _executeClientQuery(
      String clientId,
      LlmClient client,
      String query,
      bool enableTools,
      Map<String, dynamic> parameters
      ) async {
    try {
      return await client.chat(
        query,
        enableTools: enableTools,
        parameters: parameters,
      );
    } catch (e) {
      _logger.error('Error in client $clientId: $e');
      return LlmResponse(
        text: 'Error from client $clientId: $e',
        metadata: {'error': e.toString(), 'clientId': clientId},
      );
    }
  }

  /// 모든 클라이언트 닫기
  Future<void> closeAll() async {
    final futures = <Future<void>>[];
    for (final client in _clients.values) {
      futures.add(client.close());
    }
    await Future.wait(futures);
    _clients.clear();
    _router.clear();
    _loadBalancer.clear();
  }
}

