import 'package:discere/catalog/comparison/repository/comparison_list_repository.dart';
import 'package:discere/catalog/repository/reference_picture_url_repository.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/enrichment/media/repository/species_image_retention_repository.dart';
import 'package:discere/enrichment/media/service/species_image_storage_sweeper.dart';
import 'package:discere/enrichment/pipeline/repository/deck_enrichment_projection_repository.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_provenance_reconciler.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/service/cached_image_store.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _log = ScopedLogger('bootstrap');

/// The bootstrap step that runs [SpeciesImageStorageSweeper] for the
/// installed reference database — after the iNat data is reconciled with it,
/// and before any service that downloads or shows species images is built.
///
/// Gathers the needed species here, in the composition root, because
/// `enrichment` cannot reach the decks in `learning`: the species of every
/// deck (by their cards and by their enrichment memberships), of the
/// watchlist and of every comparison list — every place whose species images
/// the app downloads. A place left out here has its images deleted by the
/// next sweep.
///
/// Only once the iNat data is reconciled: the photos it discards would
/// otherwise still keep their files, and with the fingerprint recorded
/// nothing would sweep them before the next change. A failed reconciliation
/// therefore skips this step too, and a sweep asked for waits for a start
/// that has it.
///
/// A failure does not stop the start. The sweeper has not recorded the
/// fingerprint, so the next start tries again; until then the files stay.
Future<void> sweepSpeciesImageStorage() async {
  try {
    final installedVersion =
        await ReferenceDatabaseProvisioner.currentVersion();
    if (installedVersion == null) {
      _log.warn(
        'No reference database version stamped; species image storage not '
        'swept',
      );
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getInt(INatProvenanceReconciler.prefKeyReconciledVersion) !=
        installedVersion) {
      _log.warn(
        'iNat data not reconciled with reference database $installedVersion; '
        'species image storage not swept',
      );
      return;
    }
    final userDb = await DatabaseHelper.userDb;
    final neededSpeciesIds = {
      ...await FlashcardStatRepository(database: userDb).getAllDeckSpeciesIds(),
      ...await DeckEnrichmentProjectionRepository(
        userDb,
      ).loadDeckMemberSpeciesIds(),
      ...await ComparisonListRepository(database: userDb).getAllSpeciesIds(),
      ...?preferences.getStringList(WatchlistService.watchlistKey),
    };
    await SpeciesImageStorageSweeper(
      retention: SpeciesImageRetentionRepository(database: userDb),
      photoCache: INatPhotoCacheRepository(database: userDb),
      referencePictures: ReferencePictureUrlRepository(
        database: await DatabaseHelper.referenceDb,
      ),
      store: CachedImageStore(),
      preferences: preferences,
    ).sweepIfNeeded(
      neededSpeciesIds: neededSpeciesIds,
      installedVersion: installedVersion,
    );
  } catch (error, stackTrace) {
    _log.error(
      'Sweeping the species image storage failed; start continues, retried '
      'next start',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
