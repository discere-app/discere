import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Tracks, per deck, which species the user has already been informed about
/// after enrichment confirmed no photo could be found — so the "no photo"
/// gaps dialog doesn't ask about the same species again once the user has
/// decided to keep it.
class SpeciesPhotoGapAckRepository {
  final Database? _injectedDb;

  SpeciesPhotoGapAckRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  Future<Set<String>> getAcknowledgedSpeciesIds(String deckId) async {
    final db = await _database;
    final rows = await db.query(
      'species_photo_gap_ack',
      columns: ['species_id'],
      where: 'deck_id = ?',
      whereArgs: [deckId],
    );
    return rows.map((row) => row['species_id'] as String).toSet();
  }

  Future<void> acknowledge(String deckId, Set<String> speciesIds) async {
    if (speciesIds.isEmpty) return;
    final db = await _database;
    final acknowledgedAt = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final speciesId in speciesIds) {
        batch.insert(
          'species_photo_gap_ack',
          {
            'deck_id': deckId,
            'species_id': speciesId,
            'acknowledged_at': acknowledgedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }
}
