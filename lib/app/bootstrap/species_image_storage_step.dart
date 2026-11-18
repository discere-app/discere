import 'package:discere/enrichment/media/service/species_image_storage_sweeper.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_provenance_reconciler.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/service/cached_image_store.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _log = ScopedLogger('bootstrap');

/// The bootstrap step that runs [SpeciesImageStorageSweeper] for the installed
/// reference database — after the iNat data is reconciled with it, and
/// before any service that downloads or shows iNat images is built.
///
/// Only once that reconciliation is done: the photos it discards would
/// otherwise still keep their files, and with the version recorded nothing
/// would sweep them before the next reference database. A failed
/// reconciliation therefore skips this step too, and both run again on the
/// next start.
///
/// A failure does not stop the start. The pruner has not recorded the
/// version, so the next start tries again; until then the files stay.
Future<void> sweepSpeciesImageStorage() async {
  try {
    final installedVersion =
        await ReferenceDatabaseProvisioner.currentVersion();
    if (installedVersion == null) {
      _log.warn(
        'No reference database version stamped; iNat image files not pruned',
      );
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getInt(INatProvenanceReconciler.prefKeyReconciledVersion) !=
        installedVersion) {
      _log.warn(
        'iNat data not reconciled with reference database $installedVersion; '
        'iNat image files not pruned',
      );
      return;
    }
    await SpeciesImageStorageSweeper(
      photoCache: INatPhotoCacheRepository(
        database: await DatabaseHelper.userDb,
      ),
      store: CachedImageStore(),
      preferences: preferences,
    ).pruneIfNeeded(installedVersion: installedVersion);
  } catch (error, stackTrace) {
    _log.error(
      'Pruning iNat image files failed; start continues, retried next start',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
