import 'package:discere/diagnostics/repository/local_diagnostics_repository.dart';
import 'package:discere/diagnostics/service/diagnostics_log_file.dart';
import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/diagnostics/service/log_diagnostics_persistence.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The `diagnostics` slice's services, as the composition root hands them on.
typedef DiagnosticsServices = ({
  LocalDiagnostics localDiagnostics,
  List<SingleChildWidget> providers,
});

/// Builds the `diagnostics` slice's services and installs the `Logger`
/// persistence sink.
///
/// The one setup step the bootstrap runs before the reference database is
/// provisioned, so a warning from that provisioning already lands in the
/// diagnostics log. It needs only [SharedPreferences] and the log file,
/// neither database. The [DiagnosticsLogFile] the sink writes to is the one
/// [DiagnosticsServices.providers] hands to the diagnostics page.
Future<DiagnosticsServices> startDiagnosticsServices() async {
  final sharedPreferences = await SharedPreferences.getInstance();
  // Single shared instance: LocalDiagnostics buffers/queues writes
  // internally, so every consumer needs the same one rather than its own.
  final localDiagnostics = LocalDiagnostics(
    repository: const LocalDiagnosticsRepository(),
  );
  final diagnosticsLogFile = DiagnosticsLogFile();
  await LogDiagnosticsPersistence(
    sharedPreferences,
    logFile: diagnosticsLogFile,
  ).initialize();

  return (
    localDiagnostics: localDiagnostics,
    providers: [
      Provider<LocalDiagnostics>.value(value: localDiagnostics),
      Provider<DiagnosticsLogFile>.value(value: diagnosticsLogFile),
    ],
  );
}
