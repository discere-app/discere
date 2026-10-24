import 'package:discere/catalog/repository/external_id_rejection_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/enrichment/pipeline/repository/inat_provenance_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_provenance_reconciler.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _log = ScopedLogger('bootstrap');

/// The bootstrap step that runs [INatProvenanceReconciler] for the installed
/// reference database — after its reference IDs are applied to the user
/// data, and before any service that fetches or shows iNat data is built.
///
/// Only once those IDs are applied: held against the reference database
/// under IDs it has superseded, data would find no reference id and be
/// discarded. A failed alias step therefore skips this one too, and both run
/// again on the next start.
///
/// A failure does not stop the start. The reconciler has rolled its
/// transaction back and not recorded the version, so the next start tries
/// again; until then the app shows the iNat data it had.
Future<void> reconcileINatProvenance() async {
  try {
    final installedVersion =
        await ReferenceDatabaseProvisioner.currentVersion();
    if (installedVersion == null) {
      _log.warn(
        'No reference database version stamped; iNat data not reconciled',
      );
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getInt(ReferenceIdMigration.prefKeyAppliedVersion) !=
        installedVersion) {
      _log.warn(
        'Reference IDs not applied for reference database $installedVersion; '
        'iNat data not reconciled',
      );
      return;
    }
    final referenceDb = await DatabaseHelper.referenceDb;
    await INatProvenanceReconciler(
      provenance: INatProvenanceRepository(
        database: await DatabaseHelper.userDb,
      ),
      referenceIds: ExternalIdRepository(referenceDatabase: referenceDb),
      rejections: ExternalIdRejectionRepository(referenceDatabase: referenceDb),
      preferences: preferences,
    ).reconcileIfNeeded(installedVersion: installedVersion);
  } catch (error, stackTrace) {
    _log.error(
      'iNat provenance reconciliation failed; start continues, retried next '
      'start',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
