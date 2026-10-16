import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// A deck's `flashcard_stats` rows of one learning mode, taken as a whole:
/// which to initialize next, when each is due, and resetting some of them —
/// what leaving out the species without an answer in the mode takes (see
/// `AnswerableCardsService`). The per-card reads and writes are
/// `FlashcardStatRepository`'s.
class FlashcardStatModeRepository {
  /// Below SQLite's oldest limit on bound parameters, with room for the
  /// deck and mode next to the species.
  static const _chunkSize = 900;

  final Database? _injectedDb;

  FlashcardStatModeRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  /// The next review date of every species with a row for [learningMode]
  /// and [nameType] in [deckId], `null` for a row not yet initialized.
  Future<Map<String, DateTime?>> getNextReviewDates(
    String deckId,
    LearningMode learningMode,
    NameType nameType,
  ) async {
    final db = await _database;
    final rows = await db.query(
      'flashcard_stats',
      columns: ['species_id', 'next_review_date'],
      where: 'deck_id = ? AND learning_mode = ? AND name_type = ?',
      whereArgs: [deckId, learningMode.storageValue, nameType.storageValue],
    );
    return {
      for (final row in rows)
        row['species_id'] as String: switch (row['next_review_date']) {
          final int millis => DateTime.fromMillisecondsSinceEpoch(millis),
          _ => null,
        },
    };
  }

  /// Up to [limit] rows for [learningMode] and [nameType] in [deckId] that
  /// are not yet initialized, none of [excludedSpeciesIds].
  ///
  /// The excluded species stay uninitialized, so a limit applied in SQL
  /// alone would keep returning them ahead of the rest; reading as many rows
  /// more as there are excluded ones always leaves [limit] others where they
  /// exist.
  Future<Set<FlashcardStat>> getUninitializedStats(
    String deckId,
    LearningMode learningMode,
    NameType nameType, {
    required int limit,
    Set<String> excludedSpeciesIds = const {},
  }) async {
    final db = await _database;
    final rows = await db.query(
      'flashcard_stats',
      where:
          'deck_id = ? AND learning_mode = ? AND name_type = ? '
          'AND next_review_date IS NULL',
      whereArgs: [deckId, learningMode.storageValue, nameType.storageValue],
      limit: limit + excludedSpeciesIds.length,
    );
    return rows
        .map(FlashcardStat.fromMap)
        .where((stat) => !excludedSpeciesIds.contains(stat.speciesId))
        .take(limit)
        .toSet();
  }

  /// Returns the rows of [speciesIds] in [deckId] for [learningMode] — of
  /// every name type, none of another mode — to uninitialized: no review
  /// date, no FSRS state. A row that already is stays untouched. One
  /// transaction, so a reset is never half done.
  Future<void> resetStats(
    String deckId,
    LearningMode learningMode,
    Set<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) return;
    final db = await _database;
    final ids = speciesIds.toList(growable: false);
    await db.transaction((txn) async {
      for (var start = 0; start < ids.length; start += _chunkSize) {
        final chunk = ids.skip(start).take(_chunkSize).toList();
        await txn.rawUpdate(
          '''
          UPDATE flashcard_stats
          SET next_review_date = NULL, last_review_date = NULL,
            stability = 0.0, difficulty = 0.0,
            card_state = ${CardState.newCard.index}, step_index = 0
          WHERE deck_id = ? AND learning_mode = ?
            AND (next_review_date IS NOT NULL OR last_review_date IS NOT NULL)
            AND species_id IN (${List.filled(chunk.length, '?').join(', ')})
          ''',
          [deckId, learningMode.storageValue, ...chunk],
        );
      }
    });
  }
}
