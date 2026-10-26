import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// `flashcard_stats` rows of a learning mode, taken as a whole: which of a
/// deck's to initialize next, when each is due, and which across all decks
/// a reminder counts — what leaving out the species that are no card in
/// the mode takes (see `AnswerableCardsService`). The per-card reads and
/// writes are `FlashcardStatRepository`'s.
class FlashcardStatModeRepository {
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

  /// The review date of every initialized row, across all decks, that
  /// belongs to its deck's active learning mode and name type — the rows a
  /// reminder can be about. A deck without a configuration row counts in the
  /// defaults `deck_config` would give it.
  Future<
    List<
      ({
        String deckId,
        String speciesId,
        LearningMode learningMode,
        DateTime due,
      })
    >
  >
  getActiveModeReviewDates() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT s.deck_id, s.species_id, s.learning_mode, s.next_review_date
      FROM flashcard_stats s
      LEFT JOIN deck_config c ON c.deck_id = s.deck_id
      WHERE s.next_review_date IS NOT NULL
        AND s.learning_mode =
          COALESCE(c.learning_mode, '${LearningMode.species.storageValue}')
        AND s.name_type =
          COALESCE(c.name_type, '${NameType.commonName.storageValue}')
    ''');
    return [
      for (final row in rows)
        (
          deckId: row['deck_id'] as String,
          speciesId: row['species_id'] as String,
          learningMode: LearningMode.fromStorage(
            row['learning_mode'] as String?,
          ),
          due: DateTime.fromMillisecondsSinceEpoch(
            row['next_review_date'] as int,
          ),
        ),
    ];
  }
}
