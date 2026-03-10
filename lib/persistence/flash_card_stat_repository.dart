import '../model/learning/deck_stat.dart';
import '../model/learning/flash_card_stat.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class FlashCardStatRepository {
  static const String totalCards = 'total_cards';
  static const String newCards = 'new_cards';

  late final Database _database;

  FlashCardStatRepository(Database database) {
    _database = database;
  }

  Future<void> insertOrUpdateFlashCardStats(
      Set<FlashCardStat> flashCardStats) async {
    await _database.transaction((txn) async {
      for (var stat in flashCardStats) {
        if (kDebugMode) {
          print('''Updated FlashCardStat: 
             Species: ${stat.speciesId}
             Interval: ${stat.interval}
             Repetition: ${stat.repetition} 
             Next Review: ${stat.nextReviewDate?.toIso8601String()}
        ''');
        }
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
    final List<Map<String, dynamic>> maps = await _database.query(
      'flashcard_stats',
      where: 'deck_id = ? AND next_review_date <= ?',
      whereArgs: [deckId, currentDate.millisecondsSinceEpoch],
    );

    return maps.map((map) => _fromMap(map)).toList();
  }

  Future<Set<FlashCardStat>> getUninitializedFlashCardStats(
      String deckId, int limit) async {
    final List<Map<String, dynamic>> result = await _database.rawQuery('''
      SELECT * FROM flashcard_stats
      WHERE deck_id = ? AND repetition = 0
      LIMIT ?
    ''', [deckId, limit]);

    if (kDebugMode) {
      print('Uninitialized flashcards: ${result.length}');
    }
    return result.map((map) => _fromMap(map)).toSet();
  }

  Future<void> deleteFlashCardStats(
      String deckId, Set<String> speciesIds) async {
    if (speciesIds.isEmpty) return;
    final placeholders = List.generate(speciesIds.length, (_) => '?').join(',');
    await _database.delete(
      'flashcard_stats',
      where: 'deck_id = ? AND species_id IN ($placeholders)',
      whereArgs: [deckId, ...speciesIds],
    );
  }

  Future<Set<String>> getSpeciesIdsByDeckId(String deckId) async {
    final List<Map<String, dynamic>> result = await _database.query(
      'flashcard_stats',
      columns: ['species_id'],
      where: 'deck_id = ?',
      whereArgs: [deckId],
    );

    return result.map((map) => map['species_id'] as String).toSet();
  }

  Future<DeckStat> getDeckStat(String deckId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final List<Map<String, dynamic>> result = await _database.rawQuery('''
      SELECT 
        COUNT(*) AS total_count,
        SUM(CASE WHEN repetition = 0 THEN 1 ELSE 0 END) AS uninitialized_count,
        SUM(CASE WHEN repetition > 0 AND next_review_date <= ? THEN 1 ELSE 0 END) AS due_count
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
      'next_review_date': flashCardStat.nextReviewDate?.millisecondsSinceEpoch,
    };
  }

  FlashCardStat _fromMap(Map<String, dynamic> map) {
    return FlashCardStat(
      speciesId: map['species_id'],
      deckId: map['deck_id'],
      interval: map['interval'],
      repetition: map['repetition'],
      easeFactor: map['ease_factor'],
      nextReviewDate: map['next_review_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['next_review_date'])
          : null,
    );
  }
}
