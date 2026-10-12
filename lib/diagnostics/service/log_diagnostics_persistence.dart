import 'package:discere/diagnostics/service/diagnostics_log_file.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LogDiagnosticsPersistence {
  static const preferenceKey = 'diagnostics.persist_warnings_and_errors';

  /// The key the setting had while it defaulted to off. Every install
  /// started back then had `false` written under it at its first start,
  /// so a stored `false` cannot tell a deliberate choice from the default;
  /// it is dropped, and the setting starts over at on under [preferenceKey].
  static const _legacyPreferenceKey = 'diagnostics.persist_error_logs';

  final SharedPreferences _preferences;
  final DiagnosticsLogFile _logFile;

  LogDiagnosticsPersistence(
    this._preferences, {
    required DiagnosticsLogFile logFile,
  }) : _logFile = logFile;

  /// Installs the `Logger` persistence sink. Needs neither database, so the
  /// bootstrap runs it before anything that could fail on one.
  Future<void> initialize() async {
    await _preferences.remove(_legacyPreferenceKey);

    Logger.configurePersistence(
      enabled: isEnabled,
      sink: (level, scope, message) {
        return _logFile.appendLine(
          '${DateTime.now().toIso8601String()} ${_levelLabel(level)} [$scope] $message',
        );
      },
    );
  }

  /// On unless switched off: warnings and errors are what a diagnosis needs
  /// after the fact, when it is too late to switch them on.
  bool get isEnabled => _preferences.getBool(preferenceKey) ?? true;

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
