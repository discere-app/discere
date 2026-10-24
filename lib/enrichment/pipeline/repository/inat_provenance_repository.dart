import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/runtime_common_name_search_repository.dart';
import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/pipeline/repository/inat_provenance_planner.dart';
import 'package:discere/enrichment/pipeline/repository/runtime_common_name_repository.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// The iNaturalist data in the user database, read and changed by where it
/// came from: the stamps of the stored photos and names, the cached taxon
/// ids, and an [INatProvenancePlan] applied to all of them at once.
///
/// Spans tables other repositories own — the photo cache, the runtime names
/// and their search documents, the external-id cache, the work queue —
/// because discarding an entity's data has to take all of it, or none, in
/// one transaction: names without their search document would stay
/// findable, and data without its work row reset would never come back.
class INatProvenanceRepository {
  static const _photos = INatPhotoCacheRepository.tableName;
  static const _names = RuntimeCommonNameRepository.tableName;
  static const _searchDocuments =
      RuntimeCommonNameSearchRepository.documentsTable;
  static const _searchFts = RuntimeCommonNameSearchRepository.ftsTable;
  static const _cache = ExternalIdCacheRepository.tableName;

  /// Wikipedia link and IUCN status come with the photos, from the same iNat
  /// taxon (`INatPhotoApi.fetchPhotos`), and go with them.
  static final _photoTaxonProviders = [
    ExternalIdProvider.wikipedia.name,
    ExternalIdProvider.iucnStatus.name,
  ];

  final Database? _injectedDb;

  INatProvenanceRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  /// The stamp of every species' stored photos, by species id. The rows of
  /// one species are written together and share it.
  Future<Map<String, int?>> photoStamps() async {
    final rows = await (await _database).rawQuery(
      'SELECT species_id, inat_taxon_id FROM $_photos GROUP BY species_id',
    );
    return {
      for (final row in rows)
        row['species_id'] as String: row['inat_taxon_id'] as int?,
    };
  }

  /// The stamp of every entity's stored names, by entity id: a species by
  /// its id rather than its `species:<id>` key, a higher taxon by its name
  /// key. The rows of one entity are written together and share it.
  Future<Map<String, int?>> nameStamps() async {
    final rows = await (await _database).rawQuery(
      "SELECT CASE WHEN substr(entity_key, 1, 8) = 'species:' "
      'THEN substr(entity_key, 9) ELSE entity_key END AS entity_id, '
      'inat_taxon_id FROM $_names GROUP BY entity_key',
    );
    return {
      for (final row in rows)
        row['entity_id'] as String: row['inat_taxon_id'] as int?,
    };
  }

  /// Every cached iNat taxon id, by entity id. One that does not parse is
  /// left out, as the resolvers ignore it too.
  Future<Map<String, int>> cachedTaxonIds() async {
    final rows = await (await _database).query(
      _cache,
      columns: const ['entity_id', 'external_id'],
      where: 'provider = ?',
      whereArgs: [ExternalIdProvider.inaturalist.name],
    );
    return {
      for (final row in rows)
        row['entity_id'] as String: ?int.tryParse(row['external_id'] as String),
    };
  }

  /// Applies [plan] in one transaction. An entity's names sit under its
  /// `species:<id>` key or under its name key, and each statement names
  /// both: an entity id is one kind or the other, so only one can match.
  ///
  /// Discarded data takes its search document along, the full-text row
  /// first — the FTS table has no trigger, and a left-over row would keep a
  /// wrong name findable. The work that fetched it is reset to pending
  /// rather than deleted: a work row is only created when a deck is
  /// enriched, which for existing decks happened long ago, so a deleted row
  /// would never come back. Only existing rows are reset; a species whose
  /// reference picture made `inatPrimary` unnecessary has none, and its
  /// `inatBackfill` row, if any, brings the photos back.
  Future<void> apply(INatProvenancePlan plan) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final pending = {
      'attempt_count': 0,
      'next_attempt_at': null,
      'last_error': null,
      'last_failure_kind': null,
      'updated_at': now,
    };
    await (await _database).transaction((txn) async {
      final batch = txn.batch();
      for (final MapEntry(key: speciesId, value: taxonId)
          in plan.photosToStamp.entries) {
        batch.update(
          _photos,
          {'inat_taxon_id': taxonId},
          where: 'species_id = ?',
          whereArgs: [speciesId],
        );
      }
      for (final speciesId in plan.photosToDiscard) {
        batch.delete(_photos, where: 'species_id = ?', whereArgs: [speciesId]);
        batch.delete(
          _cache,
          where:
              'entity_id = ? AND provider IN '
              '(${List.filled(_photoTaxonProviders.length, '?').join(', ')})',
          whereArgs: [speciesId, ..._photoTaxonProviders],
        );
        batch.update(
          EnrichmentWorkTables.capabilityState,
          {'state': pendingState, ...pending},
          where: 'species_id = ? AND capability IN (?, ?)',
          whereArgs: [
            speciesId,
            EnrichmentCapability.inatPrimary.wireName,
            EnrichmentCapability.inatBackfill.wireName,
          ],
        );
      }
      for (final MapEntry(key: entityId, value: taxonId)
          in plan.namesToStamp.entries) {
        batch.update(
          _names,
          {'inat_taxon_id': taxonId},
          where: 'entity_key IN (?, ?)',
          whereArgs: [entityId, speciesEntityKey(entityId)],
        );
      }
      for (final entityId in plan.namesToDiscard) {
        final namesKeys = [entityId, speciesEntityKey(entityId)];
        batch.rawDelete(
          'DELETE FROM $_searchFts WHERE rowid IN '
          '(SELECT rowid FROM $_searchDocuments WHERE entity_key IN (?, ?))',
          namesKeys,
        );
        batch.delete(
          _searchDocuments,
          where: 'entity_key IN (?, ?)',
          whereArgs: namesKeys,
        );
        batch.delete(
          _names,
          where: 'entity_key IN (?, ?)',
          whereArgs: namesKeys,
        );
        batch.update(
          EnrichmentWorkTables.taxonomyWork,
          {'common_names_state': pendingState, ...pending},
          where: 'runtime_entity_key = ?',
          whereArgs: [entityId],
        );
        batch.update(
          EnrichmentWorkTables.capabilityState,
          {'state': pendingState, ...pending},
          where: 'species_id = ? AND capability = ?',
          whereArgs: [
            entityId,
            EnrichmentCapability.speciesCommonNames.wireName,
          ],
        );
      }
      for (final entityId in plan.cachedTaxonIdsToDrop) {
        batch.delete(
          _cache,
          where: 'entity_id = ? AND provider = ?',
          whereArgs: [entityId, ExternalIdProvider.inaturalist.name],
        );
      }
      await batch.commit(noResult: true);
    });
  }
}
