import 'package:sqflite/sqflite.dart';
import 'package:discere/shared/util/logger.dart';

import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/repository/runtime_common_name_search_repository.dart';
import 'package:discere/shared/external/models/inat_common_name.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/persistence/database_helper.dart';

class RuntimeTaxonomyCommonNameRecord {
  final String entityKey;
  final String? entityId;
  final String entityType;
  final String scientificName;
  final Map<Language, List<String>> referenceCommonNames;
  final Map<String, List<INatCommonName>> runtimeCommonNames;

  const RuntimeTaxonomyCommonNameRecord({
    required this.entityKey,
    this.entityId,
    required this.entityType,
    required this.scientificName,
    required this.referenceCommonNames,
    required this.runtimeCommonNames,
  });
}

/// Persists runtime-fetched common names in a generic user-DB table.
///
/// The cache stores both species and taxonomy enrichments in one table using a
/// stable entity key:
/// - species:  `species:<discere species id>`
/// - taxonomy: `genus:barbus`, `family:cyprinidae`, ...
class RuntimeCommonNameRepository {
  static final _log = Logger.forType(RuntimeCommonNameRepository);
  static const tableName = 'runtime_common_names';
  static const noResultLanguageCode = '__none__';
  static const noResultName = '__empty__';

  final Database? _injectedDb;
  final RuntimeCommonNameSearchRepository _searchRepository;

  RuntimeCommonNameRepository({
    Database? database,
    RuntimeCommonNameSearchRepository? searchRepository,
  }) : _injectedDb = database,
       _searchRepository =
           searchRepository ??
           RuntimeCommonNameSearchRepository(database: database);

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  /// Returns the set of entity keys that have at least one stored common name.
  Future<Set<String>> getEntitiesWithCommonNames(Set<String> entityKeys) async {
    if (entityKeys.isEmpty) return {};

    final db = await _database;
    final result = <String>{};
    const chunkSize = 900;

    for (var i = 0; i < entityKeys.length; i += chunkSize) {
      final chunk = entityKeys.skip(i).take(chunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(', ');

      final rows = await db.rawQuery(
        'SELECT DISTINCT entity_key FROM $tableName WHERE entity_key IN ($placeholders)',
        chunk,
      );

      for (final row in rows) {
        result.add(row['entity_key'] as String);
      }
    }

    return result;
  }

  /// Returns the entity keys that have any terminal runtime common-name
  /// outcome recorded.
  ///
  /// This includes real common names as well as the explicit no-result marker
  /// written when iNaturalist resolves a taxon successfully but returns no
  /// common names. The enrichment queue uses this to distinguish "not processed
  /// yet" from "processed and genuinely empty".
  Future<Set<String>> getEntitiesWithStoredOutcome(
    Set<String> entityKeys,
  ) async {
    return getEntitiesWithCommonNames(entityKeys);
  }

  /// Records that [entityKey] was looked up successfully but iNaturalist had
  /// no common names for it.
  ///
  /// We intentionally store a sentinel row in the same table instead of adding
  /// a second status table. Read paths ignore the synthetic language code, but
  /// the enrichment pipeline can still observe a terminal "empty" outcome and
  /// avoid retrying forever.
  Future<void> markNoCommonNames({
    required String entityKey,
    required String entityType,
  }) async {
    final db = await _database;
    final existing = await db.query(
      tableName,
      columns: ['entity_key'],
      where: 'entity_key = ?',
      whereArgs: [entityKey],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return;
    }

    await db.insert(tableName, {
      'entity_key': entityKey,
      'entity_type': entityType,
      'language_code': noResultLanguageCode,
      'name': noResultName,
      'position': null,
      'place_id': null,
      'place_position': null,
      'fetched_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> saveCommonNamesBatch(
    Map<
      String,
      ({String entityType, Map<String, List<INatCommonName>> namesByLanguage})
    >
    commonNamesByEntity,
  ) async {
    if (commonNamesByEntity.isEmpty) return;

    final db = await _database;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final entries = commonNamesByEntity.entries.toList();
    final stopwatch = Stopwatch()..start();
    _logDebug(
      'User DB write: runtime common names start (entities=${entries.length})',
    );

    const chunkSize = 25;
    try {
      for (var i = 0; i < entries.length; i += chunkSize) {
        final end = i + chunkSize < entries.length
            ? i + chunkSize
            : entries.length;
        final chunk = entries.sublist(i, end);

        _logDebug(
          'User DB write: runtime common names chunk '
          '(${i ~/ chunkSize + 1}/${(entries.length / chunkSize).ceil()}, '
          'size=${chunk.length})',
        );

        final batch = db.batch();
        for (final entityEntry in chunk) {
          final entityKey = entityEntry.key.trim();
          if (entityKey.isEmpty) continue;

          // Delete all existing rows for this entity before re-inserting.
          batch.delete(
            tableName,
            where: 'entity_key = ?',
            whereArgs: [entityKey],
          );

          for (final langEntry in entityEntry.value.namesByLanguage.entries) {
            final languageCode = langEntry.key.trim();
            if (languageCode.isEmpty) continue;

            for (final cn in langEntry.value) {
              final name = cn.name.trim();
              if (name.isEmpty) continue;

              if (cn.places.isEmpty) {
                // Global name — one row with place_id = NULL
                batch.insert(tableName, {
                  'entity_key': entityKey,
                  'entity_type': entityEntry.value.entityType,
                  'language_code': languageCode,
                  'name': name,
                  'position': cn.position,
                  'place_id': null,
                  'place_position': null,
                  'fetched_at': timestamp,
                });
              } else {
                // One row per place
                for (final place in cn.places) {
                  batch.insert(tableName, {
                    'entity_key': entityKey,
                    'entity_type': entityEntry.value.entityType,
                    'language_code': languageCode,
                    'name': name,
                    'position': cn.position,
                    'place_id': place.placeId,
                    'place_position': place.position,
                    'fetched_at': timestamp,
                  });
                }
              }
            }
          }
        }
        await batch.commit(noResult: true);
      }
    } finally {
      stopwatch.stop();
      _logDebug(
        'User DB write: runtime common names done '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
    }
  }

  Future<void> saveSpeciesCommonNamesBatch(
    Map<Species, Map<String, List<INatCommonName>>> commonNamesBySpecies,
  ) async {
    if (commonNamesBySpecies.isEmpty) return;

    await saveCommonNamesBatch({
      for (final entry in commonNamesBySpecies.entries)
        _speciesEntityKey(entry.key.id): (
          entityType: 'species',
          namesByLanguage: entry.value,
        ),
    });

    await _searchRepository.upsertDocuments(
      commonNamesBySpecies.entries.map(
        (entry) => _buildSpeciesSearchDocument(entry.key, entry.value),
      ),
    );
  }

  Future<void> saveTaxonomyCommonNamesBatch(
    Iterable<RuntimeTaxonomyCommonNameRecord> records,
  ) async {
    final recordList = records.toList();
    if (recordList.isEmpty) return;

    await saveCommonNamesBatch({
      for (final record in recordList)
        record.entityKey: (
          entityType: record.entityType,
          namesByLanguage: record.runtimeCommonNames,
        ),
    });

    await _searchRepository.upsertDocuments(
      recordList.map(_buildTaxonomySearchDocument),
    );
  }

  RuntimeCommonNameSearchDocument _buildSpeciesSearchDocument(
    Species species,
    Map<String, List<INatCommonName>> runtimeCommonNames,
  ) {
    return RuntimeCommonNameSearchDocument(
      entityKey: _speciesEntityKey(species.id),
      entityId: species.id,
      entityType: 'species',
      scientificName: species.getBinomialName(),
      commonNameEn: _bestNameForLanguage(
        species.commonNames[Language.en] ?? const [],
        runtimeCommonNames['en'],
      ),
      commonNameDe: _bestNameForLanguage(
        species.commonNames[Language.de] ?? const [],
        runtimeCommonNames['de'],
      ),
      commonNameFr: _bestNameForLanguage(
        species.commonNames[Language.fr] ?? const [],
        runtimeCommonNames['fr'],
      ),
      commonNameEs: _bestNameForLanguage(
        species.commonNames[Language.es] ?? const [],
        runtimeCommonNames['es'],
      ),
    );
  }

  RuntimeCommonNameSearchDocument _buildTaxonomySearchDocument(
    RuntimeTaxonomyCommonNameRecord record,
  ) {
    return RuntimeCommonNameSearchDocument(
      entityKey: record.entityKey,
      entityId: record.entityId ?? record.entityKey,
      entityType: record.entityType,
      scientificName: record.scientificName,
      commonNameEn: _bestNameForLanguage(
        record.referenceCommonNames[Language.en] ?? const [],
        record.runtimeCommonNames['en'],
      ),
      commonNameDe: _bestNameForLanguage(
        record.referenceCommonNames[Language.de] ?? const [],
        record.runtimeCommonNames['de'],
      ),
      commonNameFr: _bestNameForLanguage(
        record.referenceCommonNames[Language.fr] ?? const [],
        record.runtimeCommonNames['fr'],
      ),
      commonNameEs: _bestNameForLanguage(
        record.referenceCommonNames[Language.es] ?? const [],
        record.runtimeCommonNames['es'],
      ),
    );
  }

  /// Returns all names for a language as a semicolon-separated string for FTS
  /// indexing: iNat names first (top-ranked), then reference DB names.
  String? _bestNameForLanguage(
    List<String> referenceNames,
    List<INatCommonName>? runtimeNames,
  ) {
    if (runtimeNames != null && runtimeNames.isNotEmpty) {
      return runtimeNames.map((n) => n.name).join(';');
    }
    if (referenceNames.isEmpty) return null;
    return referenceNames.join(';');
  }

  String _speciesEntityKey(String speciesId) => 'species:$speciesId';

  void _logDebug(String message) {
    _log.debug(message);
  }
}
