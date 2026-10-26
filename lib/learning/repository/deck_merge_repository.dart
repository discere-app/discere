import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_id/keyed_id_rewrite.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_tables.dart';
import 'package:sqflite/sqflite.dart';

/// Moves learning progress from one deck to another, for a catalog entry
/// that supersedes a local deck (`DeckMergeService`). Spans the tables a
/// species' progress in a deck lives in — `flashcard_stats`,
/// `species_photo_gap_ack`, and its place in the subdecks — because the move
/// has to happen in all of them at once or in none.
class DeckMergeRepository {
  final Database? _injectedDb;

  DeckMergeRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  /// Moves to [toDeckId] the progress [fromDeckId] holds for the species
  /// both decks hold, in one transaction, and returns those species.
  ///
  /// Progress follows the species: its cards and its photo-gap
  /// acknowledgement change deck, and it leaves its subdeck in
  /// [fromDeckId]. A card both decks hold in the same learning mode and name
  /// type is kept once, by the rule a reference-ID merge uses for the same
  /// collision ([keepMostRecentlyReviewed]): the one reviewed last. In
  /// [toDeckId] the subdecks the species are in are switched on — the user
  /// was learning them.
  Future<Set<String>> moveSharedProgress({
    required String fromDeckId,
    required String toDeckId,
  }) async {
    final db = await _database;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''
        SELECT rowid AS row_id, deck_id, species_id, learning_mode, name_type,
               last_review_date, next_review_date
        FROM flashcard_stats
        WHERE deck_id IN (?, ?)
          AND species_id IN (
            SELECT species_id FROM flashcard_stats WHERE deck_id = ?
            INTERSECT
            SELECT species_id FROM flashcard_stats WHERE deck_id = ?)
      ''',
        [fromDeckId, toDeckId, fromDeckId, toDeckId],
      );
      if (rows.isEmpty) return const <String>{};

      final cards = <(Object?, Object?, Object?), List<IdRow>>{};
      for (final row in rows) {
        final key = (row['species_id'], row['learning_mode'], row['name_type']);
        (cards[key] ??= []).add(
          IdRow(
            rowId: row['row_id'] as int,
            oldId: row['deck_id'] as String,
            newId: toDeckId,
            values: row,
          ),
        );
      }

      final batch = txn.batch();
      for (final card in cards.values) {
        if (card.length < 2) continue;
        final survivor = keepMostRecentlyReviewed(card).survivor;
        for (final row in card) {
          if (identical(row, survivor)) continue;
          batch.delete(
            'flashcard_stats',
            where: 'rowid = ?',
            whereArgs: [row.rowId],
          );
        }
      }
      final species = {for (final row in rows) row['species_id'] as String};
      for (final speciesId in species) {
        _moveSpecies(batch, speciesId, fromDeckId, toDeckId);
      }
      await batch.commit(noResult: true);
      return species;
    });
  }

  void _moveSpecies(
    Batch batch,
    String speciesId,
    String fromDeckId,
    String toDeckId,
  ) {
    batch.update(
      'flashcard_stats',
      {'deck_id': toDeckId},
      where: 'deck_id = ? AND species_id = ?',
      whereArgs: [fromDeckId, speciesId],
    );
    // An acknowledgement the target already has stays as it is.
    batch.rawInsert(
      '''
      INSERT OR IGNORE INTO species_photo_gap_ack
        (deck_id, species_id, acknowledged_at)
      SELECT ?, species_id, acknowledged_at FROM species_photo_gap_ack
      WHERE deck_id = ? AND species_id = ?
    ''',
      [toDeckId, fromDeckId, speciesId],
    );
    for (final table in ['species_photo_gap_ack', 'deck_subdeck_species']) {
      batch.delete(
        table,
        where: 'deck_id = ? AND species_id = ?',
        whereArgs: [fromDeckId, speciesId],
      );
    }
    batch.rawUpdate(
      '''
      UPDATE deck_subdecks SET is_active = 1
      WHERE deck_id = ? AND subdeck_id IN (
        SELECT subdeck_id FROM deck_subdeck_species
        WHERE deck_id = ? AND species_id = ?)
    ''',
      [toDeckId, toDeckId, speciesId],
    );
  }

  /// Puts [deckId] where [fromDeckId] is in the deck list — for a merge
  /// target that takes the place of the deck it replaces.
  Future<void> takePosition(String deckId, {required String fromDeckId}) async {
    final db = await _database;
    await db.rawUpdate(
      '''
      UPDATE decks
         SET sortOrder = (SELECT sortOrder FROM decks WHERE id = ?)
       WHERE id = ?
    ''',
      [fromDeckId, deckId],
    );
  }
}
