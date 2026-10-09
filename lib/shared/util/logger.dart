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

  /// [error] and [stackTrace], when given, are appended to [message] — see
  /// [_describe] for the shape — so the console and the persisted diagnostics
  /// log show the same entry.
  static void warn(
    String scope,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.warning, scope, _describe(message, error, stackTrace));
  }

  /// See [warn] for [error] and [stackTrace].
  static void error(
    String scope,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(LogLevel.error, scope, _describe(message, error, stackTrace));
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

  /// Error text beyond this is cut. A `DatabaseException` carries its full
  /// SQL statement and arguments, which can run to kilobytes; the message
  /// and the start of the statement say what failed.
  static const _maxErrorTextLength = 500;

  /// Stack frames kept per entry. A database error raised through sqflite
  /// spends its first six to eight frames inside sqflite itself; twelve
  /// still reach the repository, its service and the caller above. Together
  /// with the capped error text an entry stays around 2 KB, so the half of
  /// the diagnostics log that survives a trim still holds a few hundred.
  static const _maxStackFrames = 12;

  static String _describe(
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    final buffer = StringBuffer(message);
    if (error != null) {
      var errorText = error.toString();
      if (errorText.length > _maxErrorTextLength) {
        errorText = '${errorText.substring(0, _maxErrorTextLength)}…';
      }
      buffer.write(' — ${error.runtimeType}: $errorText');
    }
    if (stackTrace != null) {
      // `<asynchronous suspension>` markers carry no location, so they
      // neither count towards the limit nor get written.
      final frames = stackTrace
          .toString()
          .split('\n')
          .where(
            (line) =>
                line.trim().isNotEmpty && line != '<asynchronous suspension>',
          )
          .toList();
      for (final frame in frames.take(_maxStackFrames)) {
        buffer.write('\n    $frame');
      }
      if (frames.length > _maxStackFrames) {
        buffer.write(
          '\n    … ${frames.length - _maxStackFrames} more frames',
        );
      }
    }
    return buffer.toString();
  }

  static bool _shouldLog(LogLevel level) {
    if (kDebugMode) return true;
    return level == LogLevel.warning || level == LogLevel.error;
  }

  static bool _shouldPersist(LogLevel level, String scope) {
    if (!_persistenceEnabled || _persistenceSink == null) return false;
    if (level != LogLevel.warning && level != LogLevel.error) return false;
    if (scope == 'LocalDiagnostics' ||
        scope == 'Logger' ||
        scope == 'DiagnosticsLogFile') {
      return false;
    }
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

  void warn(String message, {Object? error, StackTrace? stackTrace}) =>
      Logger.warn(scope, message, error: error, stackTrace: stackTrace);

  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      Logger.error(scope, message, error: error, stackTrace: stackTrace);
}
