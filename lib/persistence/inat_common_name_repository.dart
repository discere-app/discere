import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Persists imported iNaturalist common-name enrichments in the user database.
///
/// Rows are keyed by species ID and BCP-47-style language code so future
/// variants like `de-CH` can coexist with base languages such as `de`.
class INatCommonNameRepository {
  static const tableName = 'inat_common_names';

  final Database? _injectedDb;

  INatCommonNameRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  Future<Map<String, Map<String, String>>> getCommonNamesForSpecies(
    Set<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) return {};

    final db = await _database;
    final result = <String, Map<String, String>>{};
    const chunkSize = 900;

    for (var i = 0; i < speciesIds.length; i += chunkSize) {
      final chunk = speciesIds.skip(i).take(chunkSize).toList();
      final whereClause = List.filled(
        chunk.length,
        'species_id = ?',
      ).join(' OR ');

      final rows = await db.query(
        tableName,
        columns: ['species_id', 'language_code', 'names'],
        where: whereClause,
        whereArgs: chunk,
      );

      for (final row in rows) {
        final speciesId = row['species_id'] as String;
        final languageCode = row['language_code'] as String;
        final names = row['names'] as String? ?? '';
        if (names.trim().isEmpty) continue;
        result.putIfAbsent(speciesId, () => {})[languageCode] = names;
      }
    }

    return result;
  }

  Future<void> saveCommonNames(
    String speciesId,
    Map<String, String> commonNamesByLanguage,
  ) async {
    final db = await _database;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.delete(
        tableName,
        where: 'species_id = ?',
        whereArgs: [speciesId],
      );

      for (final entry in commonNamesByLanguage.entries) {
        final languageCode = entry.key.trim();
        final names = entry.value.trim();
        if (languageCode.isEmpty || names.isEmpty) continue;

        await txn.insert(tableName, {
          'species_id': speciesId,
          'language_code': languageCode,
          'names': names,
          'fetched_at': timestamp,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
