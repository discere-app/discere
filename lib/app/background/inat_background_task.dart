import 'package:discere/shared/util/logger.dart';
import 'package:workmanager/workmanager.dart';

/// Minimal Workmanager callback kept for backwards compatibility.
///
/// Enrichment now runs entirely in the UI isolate, kept alive on Android by a
/// `flutter_foreground_task` foreground service (see
/// [EnrichmentForegroundServiceKeeper]). This dispatcher is only reached when
/// Workmanager wakes the process for a task that was scheduled by a previous
/// app version. It does nothing and returns success so that Workmanager does
/// not retry.
@pragma('vm:entry-point')
void inatEnrichmentBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    Logger.debug('INatBackgroundTask', 'Legacy wakeup task=$task (no-op)');
    return true;
  });
}
