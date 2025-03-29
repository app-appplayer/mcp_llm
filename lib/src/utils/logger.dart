import 'dart:io';

/// 로그 레벨
enum LogLevel {
  none,
  error,
  warning,
  info,
  debug,
  trace,
}

final log = Logger.instance;
/// 로깅 유틸리티
class Logger {
  // 모든 로거 인스턴스를 저장하는 정적 맵
  static final Map<String, Logger> _loggers = {};

  // 싱글톤 인스턴스 - 호환성 유지
  static final Logger _instance = Logger._internal('mcp_llm');
  static Logger get instance => _instance;

  // 로거 이름
  final String name;

  // 로거 설정
  LogLevel _level = LogLevel.none;
  bool _includeTimestamp = true;
  bool _useColor = true;
  IOSink _output = stderr;

  // ANSI color codes
  static const String _resetColor = '\u001b[0m';
  static const String _redColor = '\u001b[31m';
  static const String _yellowColor = '\u001b[33m';
  static const String _blueColor = '\u001b[34m';
  static const String _cyanColor = '\u001b[36m';
  static const String _grayColor = '\u001b[90m';

  // 이름으로 로거 가져오기 (없으면 생성) - 새로운 기능
  static Logger getLogger(String name) {
    return _loggers.putIfAbsent(name, () => Logger._internal(name));
  }

  // 내부 생성자
  Logger._internal(this.name) {
    _loggers[name] = this;
  }

  // 모든 로거 레벨 설정 - 새로운 기능
  static void setAllLevels(LogLevel level) {
    for (final logger in _loggers.values) {
      logger._level = level;
    }
  }

  // 패턴으로 로거 레벨 설정 - 새로운 기능
  static void setLevelByPattern(String pattern, LogLevel level) {
    for (final entry in _loggers.entries) {
      if (entry.key.startsWith(pattern)) {
        entry.value._level = level;
      }
    }
  }

  // 기존 설정 메서드 - 호환성 유지
  void configure({
    LogLevel? level,
    bool? includeTimestamp,
    bool? useColor,
    IOSink? output,
  }) {
    if (level != null) {
      _level = level;
      // 새로운 시스템에 반영
      setAllLevels(level);
    }
    if (includeTimestamp != null) _includeTimestamp = includeTimestamp;
    if (useColor != null) _useColor = useColor;
    if (output != null) _output = output;
  }

  // 레벨 설정 - 호환성 유지
  void setLevel(LogLevel level) {
    _level = level;
  }

  // 기존 로깅 메서드들 - 호환성 유지
  void log(LogLevel level, String message) {
    if (level.index <= _level.index) {
      final timestamp = _includeTimestamp ? '[${DateTime.now()}] ' : '';
      final levelName = level.name.toUpperCase();
      final colorCode = _getColorForLevel(level);
      final namePrefix = name.isNotEmpty ? '[$name] ' : '';

      if (_useColor) {
        _output.writeln('$timestamp$colorCode[$levelName]$_resetColor $namePrefix$message');
      } else {
        _output.writeln('$timestamp[$levelName] $namePrefix$message');
      }
    }
  }

  void error(String message) {
    log(LogLevel.error, message);
  }

  void warning(String message) {
    log(LogLevel.warning, message);
  }

  void info(String message) {
    log(LogLevel.info, message);
  }

  void debug(String message) {
    log(LogLevel.debug, message);
  }

  void trace(String message) {
    log(LogLevel.trace, message);
  }

  // 로그 레벨에 따른 색상 코드 반환
  String _getColorForLevel(LogLevel level) {
    if (!_useColor) return '';

    switch (level) {
      case LogLevel.error:
        return _redColor;
      case LogLevel.warning:
        return _yellowColor;
      case LogLevel.info:
        return _blueColor;
      case LogLevel.debug:
        return _cyanColor;
      case LogLevel.trace:
        return _grayColor;
      default:
        return _resetColor;
    }
  }
}