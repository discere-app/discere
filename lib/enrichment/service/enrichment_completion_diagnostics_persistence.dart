import 'package:discere/shared/service/local_diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EnrichmentCompletionDiagnosticsPersistence {
  static const preferenceKey = 'diagnostics.enrichment_completion_summary';

  final SharedPreferences _preferences;
  final LocalDiagnostics _diagnostics;

  EnrichmentCompletionDiagnosticsPersistence(
    this._preferences, {
    required LocalDiagnostics diagnostics,
  }) : _diagnostics = diagnostics;

  Future<void> initialize({bool defaultEnabled = false}) async {
    if (!_preferences.containsKey(preferenceKey)) {
      await _preferences.setBool(preferenceKey, defaultEnabled);
    }
    _diagnostics.configureEnrichmentCompletionSummary(enabled: isEnabled);
  }

  bool get isEnabled => _preferences.getBool(preferenceKey) ?? false;

  Future<void> setEnabled(bool enabled) async {
    await _preferences.setBool(preferenceKey, enabled);
    _diagnostics.configureEnrichmentCompletionSummary(enabled: enabled);
  }
}
