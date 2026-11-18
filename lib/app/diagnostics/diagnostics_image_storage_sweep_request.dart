import 'package:discere/app/bootstrap/app_restart.dart';
import 'package:discere/app/diagnostics/widgets/diagnostics_confirm_dialogs.dart';
import 'package:discere/enrichment/media/service/species_image_storage_sweeper.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Once confirmed, has the next start sweep the species image storage and
/// restarts the app into it.
///
/// The sweep runs only in the bootstrap, before any service is built, so
/// that nothing downloads into the directories while it clears them — hence
/// asked for here and run by a restart, not run from the page.
Future<void> requestImageStorageSweepOnRestart(BuildContext context) async {
  if (!await showImageStorageSweepConfirmation(context) || !context.mounted) {
    return;
  }
  final restart = context.read<AppRestart>();
  await SpeciesImageStorageSweeper.requestSweep(
    await SharedPreferences.getInstance(),
  );
  restart();
}
