import 'package:flutter/foundation.dart';

import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:sqflite/sqflite.dart';

import 'package:discere/shared/persistence/database_helper.dart';

class FlashcardStatRepository {
  static const String totalCards = 'total_cards';
  static const String newCards = 'new_cards';

  FlashcardStatRepository();

  Future<Database> get _database async => await DatabaseHelper.userDb;

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
        for (var stat in flashcardStats) {
          await txn.insert(
            'flashcard_stats',
            _toMap(stat),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
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
    DateTime currentDate,
  ) async {
    final db = await _database;
    final List<Map<String, dynamic>> maps = await db.query(
      'flashcard_stats',
      where: 'deck_id = ? AND next_review_date <= ?',
      whereArgs: [deckId, currentDate.millisecondsSinceEpoch],
    );

    return maps.map((map) => _fromMap(map)).toList();
  }

  Future<Set<FlashcardStat>> getUninitializedFlashcardStats(
    String deckId,
    int limit,
  ) async {
    final db = await _database;
    final List<Map<String, dynamic>> result = await db.rawQuery(
      '''
      SELECT * FROM flashcard_stats
      WHERE deck_id = ? AND next_review_date IS NULL
      LIMIT ?
    ''',
      [deckId, limit],
    );

    return result.map((map) => _fromMap(map)).toSet();
  }

  Future<List<FlashcardStat>> getAllStats() async {
    final db = await _database;
    final List<Map<String, dynamic>> maps = await db.query('flashcard_stats');
    return maps.map((map) => _fromMap(map)).toList();
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
        for (var speciesId in speciesIds) {
          await txn.delete(
            'flashcard_stats',
            where: 'deck_id = ? AND species_id = ?',
            whereArgs: [deckId, speciesId],
          );
        }
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
    );

    return result.map((map) => map['species_id'] as String).toSet();
  }

  Future<FlashcardStat?> getFlashcardStat(
    String speciesId,
    String deckId,
  ) async {
    final db = await _database;
    final List<Map<String, dynamic>> result = await db.query(
      'flashcard_stats',
      where: 'species_id = ? AND deck_id = ?',
      whereArgs: [speciesId, deckId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return _fromMap(result.first);
  }

  Future<DeckStat> getDeckStat(String deckId) async {
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
      WHERE deck_id = ?
    ''',
      [now, deckId],
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

  Map<String, dynamic> _toMap(FlashcardStat flashcardStat) {
    return {
      'species_id': flashcardStat.speciesId,
      'deck_id': flashcardStat.deckId,
      'interval': flashcardStat.interval,
      'repetition': flashcardStat.repetition,
      'ease_factor': flashcardStat.easeFactor,
      'stability': flashcardStat.stability,
      'difficulty': flashcardStat.difficulty,
      'last_review_date': flashcardStat.lastReviewDate?.millisecondsSinceEpoch,
      'next_review_date': flashcardStat.nextReviewDate?.millisecondsSinceEpoch,
    };
  }

  FlashcardStat _fromMap(Map<String, dynamic> map) {
    return FlashcardStat(
      speciesId: map['species_id'],
      deckId: map['deck_id'],
      interval: map['interval'] ?? 1,
      repetition: map['repetition'] ?? 0,
      easeFactor: map['ease_factor'] ?? 2.5,
      stability: map['stability'] ?? 0.0,
      difficulty: map['difficulty'] ?? 0.0,
      lastReviewDate: map['last_review_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_review_date'])
          : null,
      nextReviewDate: map['next_review_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['next_review_date'])
          : null,
    );
  }

  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
