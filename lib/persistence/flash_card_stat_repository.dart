import '../model/learning/deck_stat.dart';
import '../model/learning/flash_card_stat.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

class FlashCardStatRepository {
  static const String totalCards = 'total_cards';
  static const String newCards = 'new_cards';

  FlashCardStatRepository();

  Future<Database> get _database async => await DatabaseHelper.userDb;

  Future<void> insertOrUpdateFlashCardStats(
      Set<FlashCardStat> flashCardStats) async {
    if (flashCardStats.isEmpty) return;

    final db = await _database;
    await db.transaction((txn) async {
      for (var stat in flashCardStats) {

        await txn.insert(
          'flashcard_stats',
          _toMap(stat),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<FlashCardStat>> getFlashCardStatsForReview(
      String deckId, DateTime currentDate) async {
    final db = await _database;
    final List<Map<String, dynamic>> maps = await db.query(
      'flashcard_stats',
      where: 'deck_id = ? AND next_review_date <= ?',
      whereArgs: [deckId, currentDate.millisecondsSinceEpoch],
    );

    return maps.map((map) => _fromMap(map)).toList();
  }

  Future<Set<FlashCardStat>> getUninitializedFlashCardStats(
      String deckId, int limit) async {
    final db = await _database;
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT * FROM flashcard_stats
      WHERE deck_id = ? AND next_review_date IS NULL
      LIMIT ?
    ''', [deckId, limit]);


    return result.map((map) => _fromMap(map)).toSet();
  }

  Future<List<FlashCardStat>> getAllStats() async {
    final db = await _database;
    final List<Map<String, dynamic>> maps = await db.query('flashcard_stats');
    return maps.map((map) => _fromMap(map)).toList();
  }

  Future<void> deleteFlashCardStats(
      String deckId, Set<String> speciesIds) async {
    if (speciesIds.isEmpty) return;

    final db = await _database;
    await db.transaction((txn) async {
      for (var speciesId in speciesIds) {
        await txn.delete(
          'flashcard_stats',
          where: 'deck_id = ? AND species_id = ?',
          whereArgs: [deckId, speciesId],
        );
      }
    });
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

  Future<FlashCardStat?> getFlashCardStat(
      String speciesId, String deckId) async {
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
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT 
        COUNT(*) AS total_count,
        SUM(CASE WHEN next_review_date IS NULL THEN 1 ELSE 0 END) AS uninitialized_count,
        SUM(CASE WHEN next_review_date IS NOT NULL AND next_review_date <= ? THEN 1 ELSE 0 END) AS due_count
      FROM flashcard_stats
      WHERE deck_id = ?
    ''', [now, deckId]);

    final int totalCount = result.first['total_count'] as int? ?? 0;
    final int uninitializedCount =
        result.first['uninitialized_count'] as int? ?? 0;
    final int dueCount = result.first['due_count'] as int? ?? 0;

    return DeckStat(totalCount, uninitializedCount, dueCount);
  }

  Map<String, dynamic> _toMap(FlashCardStat flashCardStat) {
    return {
      'species_id': flashCardStat.speciesId,
      'deck_id': flashCardStat.deckId,
      'interval': flashCardStat.interval,
      'repetition': flashCardStat.repetition,
      'ease_factor': flashCardStat.easeFactor,
      'stability': flashCardStat.stability,
      'difficulty': flashCardStat.difficulty,
      'last_review_date': flashCardStat.lastReviewDate?.millisecondsSinceEpoch,
      'next_review_date': flashCardStat.nextReviewDate?.millisecondsSinceEpoch,
    };
  }

  FlashCardStat _fromMap(Map<String, dynamic> map) {
    return FlashCardStat(
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
}
