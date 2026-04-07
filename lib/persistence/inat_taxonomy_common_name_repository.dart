import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Persists imported iNaturalist common names for higher taxonomy ranks.
///
/// Keys use taxonomic rank + scientific name so imported names can be merged
/// into classification data without changing the public Classification model.
class INatTaxonomyCommonNameRepository {
  static const tableName = 'inat_taxonomy_common_names';

  final Database? _injectedDb;

  INatTaxonomyCommonNameRepository({Database? database})
    : _injectedDb = database;

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
    Map<String, String> commonNamesByLanguage,
  ) async {
    await saveCommonNamesBatch({entityKey: commonNamesByLanguage});
  }

  /// Persists multiple taxonomy enrichments in chunked batches.
  ///
  /// Uses small batch commits instead of one large transaction to avoid holding
  /// the user DB lock for too long, which would block concurrent search reads.
  Future<void> saveCommonNamesBatch(
    Map<String, Map<String, String>> commonNamesByEntity,
  ) async {
    if (commonNamesByEntity.isEmpty) return;

    final db = await _database;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final entries = commonNamesByEntity.entries.toList();
    final stopwatch = Stopwatch()..start();
    _logDebug(
      'User DB write: iNat taxonomy names start (entities=${entries.length})',
    );

    const chunkSize = 25;
    try {
      for (var i = 0; i < entries.length; i += chunkSize) {
        final end = i + chunkSize < entries.length
            ? i + chunkSize
            : entries.length;
        final chunk = entries.sublist(i, end);

        _logDebug(
          'User DB write: iNat taxonomy names chunk '
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

          for (final entry in entityEntry.value.entries) {
            final languageCode = entry.key.trim();
            final names = entry.value.trim();
            if (languageCode.isEmpty || names.isEmpty) continue;

            batch.insert(tableName, {
              'entity_key': entityKey,
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
        'User DB write: iNat taxonomy names done '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
    }
  }

  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
