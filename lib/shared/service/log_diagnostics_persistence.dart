import 'package:discere/shared/service/local_diagnostics.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogDiagnosticsPersistence {
  static const preferenceKey = 'diagnostics.persist_error_logs';

  final SharedPreferences _preferences;
  final LocalDiagnostics _diagnostics;

  LogDiagnosticsPersistence(
    this._preferences, {
    LocalDiagnostics? diagnostics,
  }) : _diagnostics = diagnostics ?? LocalDiagnostics.instance;

  Future<void> initialize({bool defaultEnabled = true}) async {
    if (!_preferences.containsKey(preferenceKey)) {
      await _preferences.setBool(preferenceKey, defaultEnabled);
    }

    Logger.configurePersistence(
      enabled: isEnabled,
      sink: (level, scope, message) {
        return _diagnostics.recordEvent(
          category: 'log',
          eventType: 'logger_entry',
          level: _levelLabel(level),
          message: message,
          subjectType: 'scope',
          subjectId: scope,
          details: {'scope': scope, 'level': _levelLabel(level)},
        );
      },
    );
  }

  bool get isEnabled => _preferences.getBool(preferenceKey) ?? false;

  Future<void> setEnabled(bool enabled) async {
    await _preferences.setBool(preferenceKey, enabled);
    Logger.configurePersistence(enabled: enabled);
  }

  static String _levelLabel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'debug';
      case LogLevel.info:
        return 'info';
      case LogLevel.warning:
        return 'warning';
      case LogLevel.error:
        return 'error';
    }
  }
}
