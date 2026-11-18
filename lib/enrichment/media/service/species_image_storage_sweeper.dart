import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:discere/catalog/repository/reference_picture_url_repository.dart';
import 'package:discere/enrichment/media/model/species_image_storage_sweep.dart';
import 'package:discere/enrichment/media/model/species_image_sweep_trigger.dart';
import 'package:discere/enrichment/media/repository/species_image_retention_repository.dart';
import 'package:discere/enrichment/media/service/local_species_image_service.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/shared/service/cached_image_store.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the downloaded species images to the species the app needs
/// (docs/enrichment.md, "Herkunft der iNat-Daten").
///
/// The caller says which species are needed: those whose images the app
/// downloads, which are the species of the decks, the watchlist and the
/// comparison lists. Every other species is let go — its cached iNat photos
/// and image work rows ([SpeciesImageRetentionRepository.release]) — and
/// then both image directories are cut back to what remains: the iNat
/// directory to the cached photos, the reference directory to the reference
/// pictures of the needed species plus the cached photos, which older
/// versions stored there and which are still read from there.
///
/// Sweeps when the needed species or the installed reference database
/// changed since the last sweep — told by a fingerprint of both — or when
/// one was asked for ([requestSweep]). A start with nothing changed reads the
/// needed species and nothing else.
///
/// Must run after `INatProvenanceReconciler` has reconciled the installed
/// version — the bootstrap checks that — so that the photos it discards no
/// longer keep their files; and before the bootstrap builds any service, so
/// that no download lands while the directories are swept.
///
/// Safe to repeat and to interrupt: the rows go in one transaction before
/// any file, every set of URLs to keep is read in full before anything is
/// deleted, and the fingerprint is recorded only after the sweep. Until then
/// the next start sweeps again.
class SpeciesImageStorageSweeper {
  static final _log = Logger.forType(SpeciesImageStorageSweeper);

  /// The fingerprint of the needed species and the reference-database
  /// version the storage was last swept for.
  static const prefKeyFingerprint = 'species_image_storage_fingerprint';

  /// Set when a sweep was asked for, until it ran.
  static const prefKeySweepRequested = 'species_image_storage_sweep_requested';

  /// The last [SpeciesImageStorageSweep], as JSON.
  static const prefKeyLastSweep = 'species_image_storage_last_sweep';

  final SpeciesImageRetentionRepository _retention;
  final INatPhotoCacheRepository _photoCache;
  final ReferencePictureUrlRepository _referencePictures;
  final CachedImageStore _store;
  final SharedPreferences _preferences;

  const SpeciesImageStorageSweeper({
    required SpeciesImageRetentionRepository retention,
    required INatPhotoCacheRepository photoCache,
    required ReferencePictureUrlRepository referencePictures,
    required CachedImageStore store,
    required SharedPreferences preferences,
  }) : _retention = retention,
       _photoCache = photoCache,
       _referencePictures = referencePictures,
       _store = store,
       _preferences = preferences;

  /// Has the next sweep run regardless of the fingerprint.
  static Future<void> requestSweep(SharedPreferences preferences) =>
      preferences.setBool(prefKeySweepRequested, true);

  /// The last sweep, or null before the first. Unreadable content reads as
  /// none rather than failing the diagnostics page.
  static SpeciesImageStorageSweep? lastSweep(SharedPreferences preferences) {
    final raw = preferences.getString(prefKeyLastSweep);
    if (raw == null) return null;
    try {
      return SpeciesImageStorageSweep.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Sweeps for [neededSpeciesIds] and the reference database at
  /// [installedVersion], unless the last sweep was for the same and none is
  /// asked for.
  Future<void> sweepIfNeeded({
    required Set<String> neededSpeciesIds,
    required int installedVersion,
  }) async {
    final fingerprint = _fingerprintOf(neededSpeciesIds, installedVersion);
    final trigger = _triggerFor(fingerprint);
    if (trigger == null) return;
    final stopwatch = Stopwatch()..start();

    final referencePictureUrls = await _referencePictures.urlsOf(
      neededSpeciesIds,
    );
    final released = (await _retention.speciesWithImageData()).difference(
      neededSpeciesIds,
    );
    if (released.isNotEmpty) await _retention.release(released);
    // Read after the release, so that the photos it discarded keep no file.
    final photoUrls = await _photoCache.photoUrls();
    final external = await _store.prune(
      LocalSpeciesImageService.externalImagesDirectory,
      keepUrls: photoUrls,
    );
    final reference = await _store.prune(
      LocalSpeciesImageService.referenceImagesDirectory,
      keepUrls: {...referencePictureUrls, ...photoUrls},
    );

    final sweep = SpeciesImageStorageSweep(
      sweptAt: DateTime.now(),
      trigger: trigger,
      directories: {
        LocalSpeciesImageService.externalImagesDirectory: ImageDirectorySweep(
          deletedFiles: external.deletedFiles,
          freedBytes: external.freedBytes,
        ),
        LocalSpeciesImageService.referenceImagesDirectory: ImageDirectorySweep(
          deletedFiles: reference.deletedFiles,
          freedBytes: reference.freedBytes,
        ),
      },
      neededSpeciesCount: neededSpeciesIds.length,
      releasedSpeciesCount: released.length,
      duration: stopwatch.elapsed,
    );
    await _preferences.setString(prefKeyLastSweep, jsonEncode(sweep.toJson()));
    await _preferences.setString(prefKeyFingerprint, fingerprint);
    await _preferences.remove(prefKeySweepRequested);
    _log.info(
      'Species image storage swept for reference database $installedVersion '
      '(${trigger.wireName}, ${sweep.duration.inMilliseconds}ms): '
      'needed ${sweep.neededSpeciesCount}, '
      'released ${sweep.releasedSpeciesCount}; '
      'iNat files deleted ${external.deletedFiles} '
      '(${external.freedBytes} bytes), '
      'reference files deleted ${reference.deletedFiles} '
      '(${reference.freedBytes} bytes)',
    );
  }

  SpeciesImageSweepTrigger? _triggerFor(String fingerprint) {
    if (_preferences.getBool(prefKeySweepRequested) ?? false) {
      return SpeciesImageSweepTrigger.manual;
    }
    if (_preferences.getString(prefKeyFingerprint) != fingerprint) {
      return SpeciesImageSweepTrigger.automatic;
    }
    return null;
  }

  /// Stable across starts: the ids sorted, so the order a set happens to
  /// hold them in does not count as a change.
  static String _fingerprintOf(Set<String> speciesIds, int version) {
    final sorted = speciesIds.toList()..sort();
    return sha256
        .convert(utf8.encode([version, ...sorted].join('\n')))
        .toString();
  }
}
