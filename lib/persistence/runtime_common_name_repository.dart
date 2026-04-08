import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../model/biology/species.dart';
import '../model/language.dart';
import 'database_helper.dart';
import 'runtime_common_name_search_repository.dart';

class RuntimeTaxonomyCommonNameRecord {
  final String entityKey;
  final String entityType;
  final String scientificName;
  final Map<Language, String> referenceCommonNames;
  final Map<String, String> runtimeCommonNames;

  const RuntimeTaxonomyCommonNameRecord({
    required this.entityKey,
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
  static const tableName = 'runtime_common_names';

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

  Future<Map<String, Map<String, String>>> getCommonNamesForEntities(
    Set<String> entityKeys,
  ) async {
    if (entityKeys.isEmpty) return {};

    final db = await _database;
    final result = <String, Map<String, String>>{};
    const chunkSize = 900;

    for (var i = 0; i < entityKeys.length; i += chunkSize) {
      final chunk = entityKeys.skip(i).take(chunkSize).toList();
      final whereClause = List.filled(
        chunk.length,
        'entity_key = ?',
      ).join(' OR ');

      final rows = await db.query(
        tableName,
        columns: ['entity_key', 'language_code', 'names'],
        where: whereClause,
        whereArgs: chunk,
      );

      for (final row in rows) {
        final entityKey = row['entity_key'] as String;
        final languageCode = row['language_code'] as String;
        final names = row['names'] as String? ?? '';
        if (names.trim().isEmpty) continue;
        result.putIfAbsent(entityKey, () => {})[languageCode] = names;
      }
    }

    return result;
  }

  Future<void> saveCommonNames(
    String entityKey,
    Map<String, String> commonNamesByLanguage, {
    String? entityType,
  }) async {
    await saveCommonNamesBatch({
      entityKey: (
        entityType: entityType ?? _entityTypeForKey(entityKey),
        namesByLanguage: commonNamesByLanguage,
      ),
    });
  }

  Future<void> saveCommonNamesBatch(
    Map<String, ({String entityType, Map<String, String> namesByLanguage})>
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

          batch.delete(
            tableName,
            where: 'entity_key = ?',
            whereArgs: [entityKey],
          );

          for (final entry in entityEntry.value.namesByLanguage.entries) {
            final languageCode = entry.key.trim();
            final names = entry.value.trim();
            if (languageCode.isEmpty || names.isEmpty) continue;

            batch.insert(tableName, {
              'entity_key': entityKey,
              'entity_type': entityEntry.value.entityType,
              'language_code': languageCode,
              'names': names,
              'fetched_at': timestamp,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
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
    Map<Species, Map<String, String>> commonNamesBySpecies,
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

  String _entityTypeForKey(String entityKey) {
    if (entityKey.startsWith('species:')) return 'species';
    final separatorIndex = entityKey.indexOf(':');
    if (separatorIndex > 0) {
      return entityKey.substring(0, separatorIndex);
    }
    return 'unknown';
  }

  RuntimeCommonNameSearchDocument _buildSpeciesSearchDocument(
    Species species,
    Map<String, String> runtimeCommonNames,
  ) {
    final mergedCommonNames = _mergeLocalizedCommonNames(
      species.commonNames,
      runtimeCommonNames,
    );

    return RuntimeCommonNameSearchDocument(
      entityKey: _speciesEntityKey(species.id),
      entityId: species.id,
      entityType: 'species',
      scientificName: species.getBinomialName(),
      commonNameEn: mergedCommonNames[Language.en],
      commonNameDe: mergedCommonNames[Language.de],
      commonNameFr: mergedCommonNames[Language.fr],
      commonNameEs: mergedCommonNames[Language.es],
    );
  }

  RuntimeCommonNameSearchDocument _buildTaxonomySearchDocument(
    RuntimeTaxonomyCommonNameRecord record,
  ) {
    final mergedCommonNames = _mergeLocalizedCommonNames(
      record.referenceCommonNames,
      record.runtimeCommonNames,
    );

    return RuntimeCommonNameSearchDocument(
      entityKey: record.entityKey,
      entityId: record.entityKey,
      entityType: record.entityType,
      scientificName: record.scientificName,
      commonNameEn: mergedCommonNames[Language.en],
      commonNameDe: mergedCommonNames[Language.de],
      commonNameFr: mergedCommonNames[Language.fr],
      commonNameEs: mergedCommonNames[Language.es],
    );
  }

  Map<Language, String> _mergeLocalizedCommonNames(
    Map<Language, String> referenceCommonNames,
    Map<String, String> runtimeCommonNames,
  ) {
    final mergedCommonNames = <Language, String>{
      for (final language in Language.values)
        language: referenceCommonNames[language] ?? '',
    };

    for (final language in Language.values) {
      final runtimeNames = runtimeCommonNames[language.name];
      if (runtimeNames == null || runtimeNames.trim().isEmpty) continue;
      mergedCommonNames[language] = _mergeNameStrings(
        runtimeNames,
        mergedCommonNames[language] ?? '',
      );
    }

    return mergedCommonNames;
  }

  String _mergeNameStrings(String primary, String additional) {
    final mergedNames = <String>[];
    final seen = <String>{};

    for (final source in [primary, additional]) {
      final parts = source
          .split(';')
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty);
      for (final name in parts) {
        final normalized = name
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ')
            .toLowerCase();
        if (normalized.isEmpty || seen.contains(normalized)) continue;
        seen.add(normalized);
        mergedNames.add(name);
      }
    }

    return mergedNames.join(';');
  }

  String _speciesEntityKey(String speciesId) => 'species:$speciesId';

  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
