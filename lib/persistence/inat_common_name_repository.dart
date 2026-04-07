import 'package:flutter/foundation.dart';
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
    await saveCommonNamesBatch({speciesId: commonNamesByLanguage});
  }

  /// Persists multiple species enrichments in chunked batches.
  ///
  /// Uses small batch commits instead of one large transaction to avoid holding
  /// the user DB lock for too long, which would block concurrent search reads.
  Future<void> saveCommonNamesBatch(
    Map<String, Map<String, String>> commonNamesBySpecies,
  ) async {
    if (commonNamesBySpecies.isEmpty) return;

    final db = await _database;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final entries = commonNamesBySpecies.entries.toList();
    final stopwatch = Stopwatch()..start();
    _logDebug(
      'User DB write: iNat common names start (species=${entries.length})',
    );

    const chunkSize = 25;
    try {
      for (var i = 0; i < entries.length; i += chunkSize) {
        final end = i + chunkSize < entries.length
            ? i + chunkSize
            : entries.length;
        final chunk = entries.sublist(i, end);

        _logDebug(
          'User DB write: iNat common names chunk '
          '(${i ~/ chunkSize + 1}/${(entries.length / chunkSize).ceil()}, '
          'size=${chunk.length})',
        );

        final batch = db.batch();
        for (final speciesEntry in chunk) {
          final speciesId = speciesEntry.key.trim();
          if (speciesId.isEmpty) continue;

          batch.delete(
            tableName,
            where: 'species_id = ?',
            whereArgs: [speciesId],
          );

          for (final entry in speciesEntry.value.entries) {
            final languageCode = entry.key.trim();
            final names = entry.value.trim();
            if (languageCode.isEmpty || names.isEmpty) continue;

            batch.insert(tableName, {
              'species_id': speciesId,
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
        'User DB write: iNat common names done '
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
