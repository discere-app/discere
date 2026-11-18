import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// The rows that keep a species' image files: its cached iNat photos, whose
/// URLs name files, and its image work rows, which say the files are there.
///
/// Spans the photo cache, the external-id cache and the work queue, because
/// letting a species go has to take all of them in one transaction: files
/// deleted under a work row still marked done would never come back.
class SpeciesImageRetentionRepository {
  static const _photos = INatPhotoCacheRepository.tableName;
  static const _capabilityState = EnrichmentWorkTables.capabilityState;

  /// The capabilities that fetch image files. `speciesCommonNames` is not
  /// one: names stay when a species is let go, and its row says they are
  /// there.
  static final _imageCapabilities = [
    EnrichmentCapability.base.wireName,
    EnrichmentCapability.inatPrimary.wireName,
    EnrichmentCapability.inatBackfill.wireName,
  ];

  final Database? _injectedDb;

  SpeciesImageRetentionRepository({Database? database})
    : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  /// Every species with cached iNat photos or an image work row.
  Future<Set<String>> speciesWithImageData() async {
    final rows = await (await _database).rawQuery(
      'SELECT species_id FROM $_photos '
      'UNION SELECT species_id FROM $_capabilityState '
      'WHERE capability IN (${_placeholders(_imageCapabilities)})',
      _imageCapabilities,
    );
    return {for (final row in rows) row['species_id'] as String};
  }

  /// Lets [speciesIds] go, in one transaction: their cached photos go with
  /// what came with them ([INatPhotoCacheRepository.discardPhotos]), and
  /// their image work rows are deleted.
  ///
  /// Deleted rather than reset to pending: a species without rows is one
  /// never enriched, and entering a deck again treats it so — the deck seeds
  /// `base`, and `BaseWorker` the iNat capabilities under that deck's
  /// consent. A pending iNat row would be claimed whether or not the new
  /// deck consented.
  Future<void> release(Set<String> speciesIds) async {
    await (await _database).transaction((txn) async {
      final batch = txn.batch();
      for (final speciesId in speciesIds) {
        INatPhotoCacheRepository.discardPhotos(batch, speciesId);
        batch.delete(
          _capabilityState,
          where:
              'species_id = ? AND capability IN '
              '(${_placeholders(_imageCapabilities)})',
          whereArgs: [speciesId, ..._imageCapabilities],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  static String _placeholders(List<Object> values) =>
      List.filled(values.length, '?').join(', ');
}
