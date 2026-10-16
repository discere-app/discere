import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration_run.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _log = ScopedLogger('bootstrap');

/// The bootstrap step that runs [ReferenceIdMigration] for the installed
/// reference database — after the reference database is in place, whether
/// it was already there or was just downloaded, and before any service that
/// reads or writes user data is built. Running on every start, not only
/// after an install, is what covers a crash between installing a database
/// and rewriting the user data for it.
///
/// A failure does not stop the start. The migration has rolled its
/// transaction back and recorded nothing, so the next start tries again; the
/// error goes to the diagnostics log, and the failed attempt is recorded as
/// the last [ReferenceIdMigrationRun] for the diagnostics page. Until then
/// the app runs with the IDs the user data had — learning progress on
/// species whose ID changed is not found, but it is not lost either: saving
/// a deck or applying a deck update removes only the species the user
/// removed (see `DecksService.updateDeck`).
/// A start that fails every time would leave the user with no app at all.
Future<void> applyReferenceIdAliases({
  DateTime Function() now = DateTime.now,
}) async {
  int? installedVersion;
  try {
    installedVersion = await ReferenceDatabaseProvisioner.currentVersion();
    if (installedVersion == null) {
      _log.warn('No reference database version stamped; aliases not applied');
      return;
    }
    await ReferenceIdMigration(
      userDb: await DatabaseHelper.userDb,
      referenceDb: await DatabaseHelper.referenceDb,
      preferences: await SharedPreferences.getInstance(),
      idListPreferenceKeys: const {WatchlistService.watchlistKey},
      now: now,
    ).applyIfNeeded(installedVersion: installedVersion);
  } catch (error, stackTrace) {
    _log.error(
      'Reference ID migration failed; start continues, retried next start',
      error: error,
      stackTrace: stackTrace,
    );
    if (installedVersion != null) {
      await _recordFailure(installedVersion, now());
    }
  }
}

/// Best effort: the start goes on either way, and the failure it would
/// record is already in the log.
Future<void> _recordFailure(int referenceDbVersion, DateTime ranAt) async {
  try {
    await ReferenceIdMigrationFailed(
      referenceDbVersion: referenceDbVersion,
      ranAt: ranAt,
    ).save(await SharedPreferences.getInstance());
  } catch (error) {
    _log.warn('Could not record the failed reference ID migration: $error');
  }
}
