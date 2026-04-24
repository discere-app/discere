import 'dart:async';

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

typedef LoggerPersistenceSink =
    Future<void> Function(LogLevel level, String scope, String message);

class Logger {
  const Logger._();

  static LoggerPersistenceSink? _persistenceSink;
  static bool _persistenceEnabled = false;

  static ScopedLogger scoped(String scope) => ScopedLogger(scope);

  static ScopedLogger forType(Type type) => ScopedLogger(type.toString());

  static ScopedLogger forObject(Object object) =>
      ScopedLogger(object.runtimeType.toString());

  static void debug(String scope, String message) {
    _log(LogLevel.debug, scope, message);
  }

  static void info(String scope, String message) {
    _log(LogLevel.info, scope, message);
  }

  static void warn(String scope, String message) {
    _log(LogLevel.warning, scope, message);
  }

  static void error(String scope, String message) {
    _log(LogLevel.error, scope, message);
  }

  static void configurePersistence({
    required bool enabled,
    LoggerPersistenceSink? sink,
  }) {
    _persistenceEnabled = enabled;
    if (sink != null) {
      _persistenceSink = sink;
    }
  }

  static void _log(LogLevel level, String scope, String message) {
    if (!_shouldLog(level)) return;
    debugPrint('[${_label(level)}][$scope] $message');
    if (_shouldPersist(level, scope)) {
      unawaited(_persistenceSink?.call(level, scope, message));
    }
  }

  static bool _shouldLog(LogLevel level) {
    if (kDebugMode) return true;
    return level == LogLevel.warning || level == LogLevel.error;
  }

  static bool _shouldPersist(LogLevel level, String scope) {
    if (!_persistenceEnabled || _persistenceSink == null) return false;
    if (level != LogLevel.warning && level != LogLevel.error) return false;
    if (scope == 'LocalDiagnostics' || scope == 'Logger') return false;
    return true;
  }

  static String _label(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }
}

@Deprecated('Use Logger.debug(...) or Logger.scoped(...).debug(...) instead.')
class DebugLog {
  static void log(String scope, String message) {
    Logger.debug(scope, message);
  }
}

@Deprecated(
  'Use Logger.scoped(...) for instance logging or Logger.debug(...) for static logging.',
)
class DebugLogger extends ScopedLogger {
  const DebugLogger(super.scope);
}

class ScopedLogger {
  final String scope;

  const ScopedLogger(this.scope);

  void debug(String message) => Logger.debug(scope, message);

  void info(String message) => Logger.info(scope, message);

  void warn(String message) => Logger.warn(scope, message);

  void error(String message) => Logger.error(scope, message);
}
