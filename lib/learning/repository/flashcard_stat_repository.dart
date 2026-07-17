import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:sqflite/sqflite.dart';

import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/util/logger.dart';

class FlashcardStatRepository {
  static final _log = Logger.forType(FlashcardStatRepository);
  static const String totalCards = 'total_cards';
  static const String newCards = 'new_cards';

  final Database? _injectedDb;

  FlashcardStatRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async => _injectedDb ?? await DatabaseHelper.userDb;

  Future<void> insertOrUpdateFlashcardStats(
    Set<FlashcardStat> flashcardStats,
  ) async {
    if (flashcardStats.isEmpty) return;

    final db = await _database;
    final stopwatch = Stopwatch()..start();
    _logDebug(
      'User DB write: flashcard stats upsert start '
      '(count=${flashcardStats.length})',
    );
    try {
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (var stat in flashcardStats) {
          batch.insert(
            'flashcard_stats',
            _toMap(stat),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    } finally {
      stopwatch.stop();
      _logDebug(
        'User DB write: flashcard stats upsert done '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
    }
  }

  Future<List<FlashcardStat>> getFlashcardStatsForReview(
    String deckId,
    DateTime currentDate, [
    LearningMode learningMode = LearningMode.species,
    NameType nameType = NameType.commonName,
  ]) async {
    final db = await _database;
    final List<Map<String, dynamic>> maps = await db.query(
      'flashcard_stats',
      where:
          'deck_id = ? AND learning_mode = ? AND name_type = ? '
          'AND next_review_date <= ?',
      whereArgs: [
        deckId,
        learningMode.storageValue,
        nameType.storageValue,
        currentDate.millisecondsSinceEpoch,
      ],
    );

    return maps.map((map) => _fromMap(map)).toList();
  }

  Future<Set<FlashcardStat>> getUninitializedFlashcardStats(
    String deckId,
    int limit, [
    LearningMode learningMode = LearningMode.species,
    NameType nameType = NameType.commonName,
  ]) async {
    final db = await _database;
    final List<Map<String, dynamic>> result = await db.rawQuery(
      '''
      SELECT * FROM flashcard_stats
      WHERE deck_id = ? AND learning_mode = ? AND name_type = ?
        AND next_review_date IS NULL
      LIMIT ?
    ''',
      [deckId, learningMode.storageValue, nameType.storageValue, limit],
    );

    return result.map((map) => _fromMap(map)).toSet();
  }

  Future<List<DateTime?>> getAllNextReviewDates() async {
    final db = await _database;
    final List<Map<String, dynamic>> maps = await db.query(
      'flashcard_stats',
      columns: ['next_review_date'],
    );
    return maps
        .map(
          (map) => map['next_review_date'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  map['next_review_date'] as int,
                )
              : null,
        )
        .toList();
  }

  Future<void> deleteFlashcardStats(
    String deckId,
    Set<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) return;

    final db = await _database;
    final stopwatch = Stopwatch()..start();
    _logDebug(
      'User DB write: flashcard stats delete start '
      '(deck=$deckId, count=${speciesIds.length})',
    );
    try {
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (var speciesId in speciesIds) {
          batch.delete(
            'flashcard_stats',
            where: 'deck_id = ? AND species_id = ?',
            whereArgs: [deckId, speciesId],
          );
        }
        await batch.commit(noResult: true);
      });
    } finally {
      stopwatch.stop();
      _logDebug(
        'User DB write: flashcard stats delete done '
        '(deck=$deckId, ${stopwatch.elapsedMilliseconds}ms)',
      );
    }
  }

  Future<Set<String>> getDeckIdsBySpeciesId(String speciesId) async {
    final db = await _database;
    final List<Map<String, dynamic>> result = await db.query(
      'flashcard_stats',
      columns: ['deck_id'],
      where: 'species_id = ?',
      whereArgs: [speciesId],
      distinct: true,
    );
    return result.map((map) => map['deck_id'] as String).toSet();
  }

  Future<Set<String>> getSpeciesIdsByDeckId(String deckId) async {
    final db = await _database;
    final List<Map<String, dynamic>> result = await db.query(
      'flashcard_stats',
      columns: ['species_id'],
      where: 'deck_id = ?',
      whereArgs: [deckId],
      distinct: true,
    );

    return result.map((map) => map['species_id'] as String).toSet();
  }

  Future<FlashcardStat?> getFlashcardStat(
    String speciesId,
    String deckId, [
    LearningMode learningMode = LearningMode.species,
    NameType nameType = NameType.commonName,
  ]) async {
    final db = await _database;
    final List<Map<String, dynamic>> result = await db.query(
      'flashcard_stats',
      where:
          'species_id = ? AND deck_id = ? AND learning_mode = ? '
          'AND name_type = ?',
      whereArgs: [
        speciesId,
        deckId,
        learningMode.storageValue,
        nameType.storageValue,
      ],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return _fromMap(result.first);
  }

  Future<DeckStat> getDeckStat(
    String deckId, {
    LearningMode learningMode = LearningMode.species,
    NameType nameType = NameType.commonName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final db = await _database;
    final stopwatch = Stopwatch()..start();
    final List<Map<String, dynamic>> result = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS total_count,
        SUM(CASE WHEN next_review_date IS NULL THEN 1 ELSE 0 END) AS uninitialized_count,
        SUM(CASE WHEN next_review_date IS NOT NULL AND next_review_date <= ? THEN 1 ELSE 0 END) AS due_count
      FROM flashcard_stats
      WHERE deck_id = ? AND learning_mode = ? AND name_type = ?
    ''',
      [now, deckId, learningMode.storageValue, nameType.storageValue],
    );
    stopwatch.stop();
    _logDebug(
      'User DB read: flashcard getDeckStat deck=$deckId '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );

    final int totalCount = result.first['total_count'] as int? ?? 0;
    final int uninitializedCount =
        result.first['uninitialized_count'] as int? ?? 0;
    final int dueCount = result.first['due_count'] as int? ?? 0;

    return DeckStat(totalCount, uninitializedCount, dueCount);
  }

  /// Ensures a `flashcard_stats` row exists for every species already tracked
  /// in [deckId], for the given [learningMode] + [nameType] combination.
  /// Each (learningMode, nameType) pair gets its own independent FSRS
  /// progress track, seeded blank (no review history) on first use.
  Future<void> ensureStatsForLearningMode(
    String deckId,
    LearningMode learningMode, [
    NameType nameType = NameType.commonName,
  ]) async {
    final db = await _database;
    await db.rawInsert(
      '''
      INSERT OR IGNORE INTO flashcard_stats (species_id, deck_id, learning_mode, name_type)
      SELECT DISTINCT species_id, deck_id, ?, ?
      FROM flashcard_stats
      WHERE deck_id = ?
      ''',
      [learningMode.storageValue, nameType.storageValue, deckId],
    );
  }

  Map<String, dynamic> _toMap(FlashcardStat flashcardStat) {
    return {
      'species_id': flashcardStat.speciesId,
      'deck_id': flashcardStat.deckId,
      'learning_mode': flashcardStat.learningMode.storageValue,
      'name_type': flashcardStat.nameType.storageValue,
      'stability': flashcardStat.stability,
      'difficulty': flashcardStat.difficulty,
      'last_review_date': flashcardStat.lastReviewDate?.millisecondsSinceEpoch,
      'next_review_date': flashcardStat.nextReviewDate?.millisecondsSinceEpoch,
      'card_state': flashcardStat.cardState.index,
      'step_index': flashcardStat.stepIndex,
    };
  }

  FlashcardStat _fromMap(Map<String, dynamic> map) {
    return FlashcardStat(
      speciesId: map['species_id'],
      deckId: map['deck_id'],
      learningMode: LearningMode.fromStorage(map['learning_mode'] as String?),
      nameType: NameType.fromStorage(map['name_type'] as String?),
      stability: map['stability'] ?? 0.0,
      difficulty: map['difficulty'] ?? 0.0,
      lastReviewDate: map['last_review_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_review_date'])
          : null,
      nextReviewDate: map['next_review_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['next_review_date'])
          : null,
      cardState: CardState.values[map['card_state'] ?? 0],
      stepIndex: map['step_index'] ?? 0,
    );
  }

  void _logDebug(String message) {
    _log.debug(message);
  }
}
