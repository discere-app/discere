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
    final db = await _database;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.delete(
        tableName,
        where: 'entity_key = ?',
        whereArgs: [entityKey],
      );

      for (final entry in commonNamesByLanguage.entries) {
        final languageCode = entry.key.trim();
        final names = entry.value.trim();
        if (languageCode.isEmpty || names.isEmpty) continue;

        await txn.insert(tableName, {
          'entity_key': entityKey,
          'language_code': languageCode,
          'names': names,
          'fetched_at': timestamp,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
