import '../../mcp_llm.dart';
import '../core/models.dart';

/// 동적으로 LLM 제공자를 등록하고 관리하는 레지스트리
class LlmRegistry {
  // 싱글톤 코드 제거

  // 등록된 제공자 맵
  final Map<String, LlmProviderFactory> _providers = {};

  // 일반 생성자
  LlmRegistry();

  /// 새 LLM 제공자 등록
  void registerProvider(String name, LlmProviderFactory factory) {
    _providers[name] = factory;
    // 로그 출력 (Logger를 인스턴스로 받거나 필요 시 생성)
    final logger = Logger.getLogger('mcp_llm.llm_registry');
    logger.info('LLM provider registered: $name');
  }

  /// 이름으로 제공자 팩토리 가져오기
  LlmProviderFactory? getProviderFactory(String providerName) {
    return _providers[providerName];
  }

  /// 모든 등록된 제공자 이름 가져오기
  List<String> getAvailableProviders() {
    return _providers.keys.toList();
  }

  /// 특정 기능을 지원하는 제공자 필터링
  List<String> getProvidersWithCapability(LlmCapability capability) {
    return _providers.entries
        .where((entry) => entry.value.capabilities.contains(capability))
        .map((entry) => entry.key)
        .toList();
  }

  /// 모든 등록된 제공자 지우기 (주로 테스트용)
  void clear() {
    _providers.clear();
  }
}

