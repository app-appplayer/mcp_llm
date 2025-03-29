

/// 클라이언트 간 로드 밸런싱을 처리하는 클래스
class LoadBalancer {
  final Map<String, double> _clientWeights = {};
  int _currentIndex = 0;
  final List<String> _roundRobinList = [];

  /// 새 클라이언트 등록
  void registerClient(String clientId, {double weight = 1.0}) {
    _clientWeights[clientId] = weight;
    _updateRoundRobinList();
  }

  /// 클라이언트 등록 해제
  void unregisterClient(String clientId) {
    _clientWeights.remove(clientId);
    _updateRoundRobinList();
  }

  /// 가중치 기반 라운드 로빈 목록 업데이트
  void _updateRoundRobinList() {
    _roundRobinList.clear();

    for (final entry in _clientWeights.entries) {
      final String clientId = entry.key;
      final int weightCount = (entry.value * 10).round(); // 가중치를 10배로 스케일링

      for (int i = 0; i < weightCount; i++) {
        _roundRobinList.add(clientId);
      }
    }

    // 목록 섞기
    _roundRobinList.shuffle();
    _currentIndex = 0;
  }

  /// 다음 클라이언트 가져오기
  String? getNextClient() {
    if (_roundRobinList.isEmpty) return null;

    final clientId = _roundRobinList[_currentIndex];
    _currentIndex = (_currentIndex + 1) % _roundRobinList.length;
    return clientId;
  }

  /// 로드 밸런서 초기화
  void clear() {
    _clientWeights.clear();
    _roundRobinList.clear();
    _currentIndex = 0;
  }
}