/// What the diagnostics page can do, gathered in one object.
///
/// The section list needs seven callbacks; passing them individually would
/// give it an eleven-parameter constructor. Grouping them also puts the
/// page's whole action surface in one place to read.
library;

import 'package:flutter/widgets.dart';

class DiagnosticsActions {
  final ValueChanged<bool> setPersistLogs;
  final VoidCallback openLogViewer;
  final VoidCallback clearLog;
  final VoidCallback resetStuckJobs;
  final VoidCallback closeAllEnrichment;
  final VoidCallback checkDeckUpdates;
  final VoidCallback resetAllSettings;

  const DiagnosticsActions({
    required this.setPersistLogs,
    required this.openLogViewer,
    required this.clearLog,
    required this.resetStuckJobs,
    required this.closeAllEnrichment,
    required this.checkDeckUpdates,
    required this.resetAllSettings,
  });
}
