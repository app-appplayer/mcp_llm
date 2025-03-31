import '../../mcp_llm.dart';

/// 텍스트의 토큰 수를 계산하는 유틸리티
class TokenCounter {
  // 싱글톤 코드 제거

  // 모델별 토크나이저
  final Map<String, Tokenizer> _tokenizers = {};

  // 일반 생성자
  TokenCounter() {
    // 기본 토크나이저 등록
    _tokenizers['gpt-3.5-turbo'] = GPTTokenizer();
    _tokenizers['gpt-4'] = GPTTokenizer();
    _tokenizers['claude'] = ClaudeTokenizer();
  }

  /// 모델별 토큰 수 계산
  int countTokens(String text, String model) {
    final tokenizer = _getTokenizer(model);
    return tokenizer.countTokens(text);
  }

  /// 메시지 목록의 토큰 수 계산
  int countMessageTokens(List<LlmMessage> messages, String model) {
    final tokenizer = _getTokenizer(model);

    int total = 0;
    for (final message in messages) {
      // 역할별 토큰 추가
      total += tokenizer.countMessageTokens(message);
    }

    // 모델별 기본 토큰 추가
    total += tokenizer.getBaseTokens();

    return total;
  }

  /// 사용자 정의 토크나이저 등록
  void registerTokenizer(String modelPrefix, Tokenizer tokenizer) {
    _tokenizers[modelPrefix] = tokenizer;
  }

  // 적절한 토크나이저 가져오기
  Tokenizer _getTokenizer(String model) {
    // 정확한 모델명 일치 확인
    if (_tokenizers.containsKey(model)) {
      return _tokenizers[model]!;
    }

    // 모델명 접두사 기반 확인
    for (final entry in _tokenizers.entries) {
      if (model.startsWith(entry.key)) {
        return entry.value;
      }
    }

    // 기본 토크나이저
    return DefaultTokenizer();
  }
}

/// 토크나이저 인터페이스
abstract class Tokenizer {
  int countTokens(String text);
  int countMessageTokens(LlmMessage message);
  int getBaseTokens();
}

/// 기본 토크나이저 구현 (휴리스틱 기반)
class DefaultTokenizer implements Tokenizer {
  @override
  int countTokens(String text) {
    // 휴리스틱: 영어 텍스트에서 대략 단어당 1.5 토큰
    return (text.split(RegExp(r'\s+')).length * 1.5).ceil();
  }

  @override
  int countMessageTokens(LlmMessage message) {
    int tokens = 0;

    // 역할 토큰
    tokens += 4; // 기본 역할 토큰 수

    // 내용 토큰
    if (message.content is String) {
      tokens += countTokens(message.content as String);
    } else if (message.content is Map) {
      final contentMap = message.content as Map;
      if (contentMap['type'] == 'text') {
        tokens += countTokens(contentMap['text'] as String);
      } else if (contentMap['type'] == 'image') {
        // 이미지 추정 토큰
        tokens += 1000; // 대략적인 추정
      }
    }

    return tokens;
  }

  @override
  int getBaseTokens() {
    return 3; // 기본 요청 토큰
  }
}

/// GPT 토크나이저 (단순화된 구현)
class GPTTokenizer implements Tokenizer {
  // 실제 구현에서는 tiktoken 등 실제 토큰화 알고리즘을 사용합니다

  @override
  int countTokens(String text) {
    // 휴리스틱: 평균적으로 영어 텍스트에서 1 토큰 = 4 글자
    return (text.length / 4).ceil();
  }

  @override
  int countMessageTokens(LlmMessage message) {
    int tokens = 0;

    // 역할 토큰
    tokens += 3;

    // 내용 토큰
    if (message.content is String) {
      tokens += countTokens(message.content as String);
    } else if (message.content is Map) {
      final contentMap = message.content as Map;
      if (contentMap['type'] == 'text') {
        tokens += countTokens(contentMap['text'] as String);
      } else if (contentMap['type'] == 'image') {
        // 이미지 토큰 계산 (크기에 따라 달라짐)
        tokens += 850; // 기본값
      }
    }

    return tokens + 3; // 3은 메시지 형식 토큰
  }

  @override
  int getBaseTokens() {
    return 3;
  }
}

/// Claude 토크나이저 (단순화된 구현)
class ClaudeTokenizer implements Tokenizer {
  @override
  int countTokens(String text) {
    // Claude의 경우 휴리스틱: 평균적으로 1 토큰 = 3.5 글자
    return (text.length / 3.5).ceil();
  }

  @override
  int countMessageTokens(LlmMessage message) {
    int tokens = 0;

    // 역할 토큰
    tokens += 5;

    // 내용 토큰
    if (message.content is String) {
      tokens += countTokens(message.content as String);
    } else if (message.content is Map) {
      final contentMap = message.content as Map;
      if (contentMap['type'] == 'text') {
        tokens += countTokens(contentMap['text'] as String);
      } else if (contentMap['type'] == 'image') {
        // 이미지 토큰 계산
        tokens += 1024; // 기본값
      }
    }

    return tokens;
  }

  @override
  int getBaseTokens() {
    return 10;
  }
}