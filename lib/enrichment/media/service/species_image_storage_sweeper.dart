import 'package:discere/enrichment/media/service/local_species_image_service.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/shared/service/cached_image_store.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deletes the downloaded iNaturalist images no cached photo names any more,
/// once per installed reference database (docs/enrichment.md, "Herkunft der
/// iNat-Daten").
///
/// An image file is found only through the URL of its row in the photo
/// cache, so a file whose row is gone stays on disk with nothing pointing at
/// it. Rows go in bulk only when the reference database changes — the iNat
/// provenance reconciliation discards them, and rewriting reference IDs
/// drops the ones that collide — so that is when this sweeps. A species
/// whose photos are fetched again in between leaves its old files behind
/// until the next sweep; listing the directory on every start to catch those
/// few would cost more than they do.
///
/// Must run after `INatProvenanceReconciler` has reconciled the same version
/// — the bootstrap checks that — so that the rows it discards no longer keep
/// their files; and before the bootstrap builds any service, so that no
/// download lands while the directory is swept.
///
/// Safe to repeat and to interrupt: it only deletes files no row names, and
/// the reference-database version is recorded under [prefKeyPrunedVersion]
/// only after the sweep. Until then the next start sweeps again.
class SpeciesImageStorageSweeper {
  static final _log = Logger.forType(SpeciesImageStorageSweeper);

  /// The reference-database version the iNat image files were last pruned
  /// for.
  static const prefKeyPrunedVersion = 'inat_image_files_pruned_version';

  final INatPhotoCacheRepository _photoCache;
  final CachedImageStore _store;
  final SharedPreferences _preferences;

  const SpeciesImageStorageSweeper({
    required INatPhotoCacheRepository photoCache,
    required CachedImageStore store,
    required SharedPreferences preferences,
  }) : _photoCache = photoCache,
       _store = store,
       _preferences = preferences;

  /// Prunes for the reference database at [installedVersion], unless that
  /// already happened.
  Future<void> pruneIfNeeded({required int installedVersion}) async {
    if (_preferences.getInt(prefKeyPrunedVersion) == installedVersion) return;
    final stopwatch = Stopwatch()..start();

    final photoUrls = await _photoCache.photoUrls();
    final deleted = await _store.prune(
      LocalSpeciesImageService.externalImagesDirectory,
      keepUrls: photoUrls,
    );

    await _preferences.setInt(prefKeyPrunedVersion, installedVersion);
    _log.info(
      'iNat image files pruned for reference database $installedVersion '
      '(${stopwatch.elapsedMilliseconds}ms): deleted $deleted, '
      'cached photos ${photoUrls.length}',
    );
  }
}
