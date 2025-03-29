/// 쿼리를 기반으로 적절한 클라이언트로 라우팅하는 클래스
class ClientRouter {
  final Map<String, Map<String, dynamic>> _clientProperties = {};

  /// 라우팅 속성으로 클라이언트 등록
  void registerClient(String clientId, Map<String, dynamic> properties) {
    _clientProperties[clientId] = properties;
  }

  /// 클라이언트 등록 해제
  void unregisterClient(String clientId) {
    _clientProperties.remove(clientId);
  }

  /// 쿼리에 적합한 클라이언트 찾기
  String? routeQuery(String query, [Map<String, dynamic>? queryProperties]) {
    if (queryProperties == null || queryProperties.isEmpty) {
      // 간단한 키워드 기반 라우팅
      for (final entry in _clientProperties.entries) {
        final keywords = entry.value['keywords'] as List<String>?;
        if (keywords != null &&
            keywords.any((keyword) => query.toLowerCase().contains(keyword.toLowerCase()))) {
          return entry.key;
        }
      }
      return null;
    }

    // 속성 기반 라우팅
    String? bestMatch;
    int highestMatches = 0;

    for (final entry in _clientProperties.entries) {
      int matches = 0;
      for (final prop in queryProperties.entries) {
        if (entry.value.containsKey(prop.key) &&
            entry.value[prop.key] == prop.value) {
          matches++;
        }
      }

      if (matches > highestMatches) {
        highestMatches = matches;
        bestMatch = entry.key;
      }
    }

    return bestMatch;
  }

  /// 라우터 초기화
  void clear() {
    _clientProperties.clear();
  }
}