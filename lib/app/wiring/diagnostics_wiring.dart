import 'package:discere/diagnostics/repository/local_diagnostics_repository.dart';
import 'package:discere/diagnostics/service/diagnostics_log_file.dart';
import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/diagnostics/service/log_diagnostics_persistence.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds the `diagnostics` slice's services.
///
/// [logDiagnosticsPersistence] comes back un-initialized: its
/// `initialize()` installs the `Logger` persistence sink and has to be
/// awaited, which the composition root does right after this call. Keeping
/// the await there rather than making this function async is deliberate —
/// the bootstrap's order is load-bearing and only visible if every step
/// that waits for something stays in one place.
({
  LocalDiagnostics localDiagnostics,
  DiagnosticsLogFile diagnosticsLogFile,
  LogDiagnosticsPersistence logDiagnosticsPersistence,
  List<SingleChildWidget> providers,
})
buildDiagnosticsServices({required SharedPreferences sharedPreferences}) {
  // Single shared instance: LocalDiagnostics buffers/queues writes
  // internally, so every consumer needs the same one rather than its own.
  final localDiagnostics = LocalDiagnostics(
    repository: const LocalDiagnosticsRepository(),
  );
  final diagnosticsLogFile = DiagnosticsLogFile();

  return (
    localDiagnostics: localDiagnostics,
    diagnosticsLogFile: diagnosticsLogFile,
    logDiagnosticsPersistence: LogDiagnosticsPersistence(
      sharedPreferences,
      logFile: diagnosticsLogFile,
    ),
    providers: [
      Provider<LocalDiagnostics>.value(value: localDiagnostics),
      Provider<DiagnosticsLogFile>.value(value: diagnosticsLogFile),
    ],
  );
}
