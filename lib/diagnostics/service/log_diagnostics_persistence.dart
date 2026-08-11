import 'package:discere/diagnostics/service/diagnostics_log_file.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogDiagnosticsPersistence {
  static const preferenceKey = 'diagnostics.persist_error_logs';

  final SharedPreferences _preferences;
  final DiagnosticsLogFile _logFile;

  LogDiagnosticsPersistence(
    this._preferences, {
    required DiagnosticsLogFile logFile,
  }) : _logFile = logFile;

  Future<void> initialize({bool defaultEnabled = true}) async {
    if (!_preferences.containsKey(preferenceKey)) {
      await _preferences.setBool(preferenceKey, defaultEnabled);
    }

    Logger.configurePersistence(
      enabled: isEnabled,
      sink: (level, scope, message) {
        return _logFile.appendLine(
          '${DateTime.now().toIso8601String()} ${_levelLabel(level)} [$scope] $message',
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
