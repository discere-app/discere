import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Tracks how many new and review cards have been shown per deck per day.
///
/// "New" = card was in [CardState.newCard] before the review.
/// "Review" = card was in [CardState.review] before the review.
/// Learning/Relearning cards do not count against any limit.
class DailyCountRepository {
  Future<Database> get _database async => await DatabaseHelper.userDb;

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Returns today's new-card count for [deckId].
  Future<int> getTodayNewCount(
    String deckId, {
    LearningMode learningMode = LearningMode.species,
  }) async {
    final db = await _database;
    final result = await db.query(
      'daily_counts',
      columns: ['new_count'],
      where: 'deck_id = ? AND date = ? AND learning_mode = ?',
      whereArgs: [deckId, _today(), learningMode.storageValue],
      limit: 1,
    );
    if (result.isEmpty) return 0;
    return result.first['new_count'] as int? ?? 0;
  }

  /// Returns today's review count for [deckId].
  Future<int> getTodayReviewCount(
    String deckId, {
    LearningMode learningMode = LearningMode.species,
  }) async {
    final db = await _database;
    final result = await db.query(
      'daily_counts',
      columns: ['review_count'],
      where: 'deck_id = ? AND date = ? AND learning_mode = ?',
      whereArgs: [deckId, _today(), learningMode.storageValue],
      limit: 1,
    );
    if (result.isEmpty) return 0;
    return result.first['review_count'] as int? ?? 0;
  }

  /// Increments today's new-card counter for [deckId] by 1.
  Future<void> incrementNewCount(
    String deckId, {
    LearningMode learningMode = LearningMode.species,
  }) async {
    final db = await _database;
    await db.rawInsert(
      '''
      INSERT INTO daily_counts (deck_id, date, learning_mode, new_count, review_count)
      VALUES (?, ?, ?, 1, 0)
      ON CONFLICT(deck_id, date, learning_mode)
      DO UPDATE SET new_count = new_count + 1
      ''',
      [deckId, _today(), learningMode.storageValue],
    );
  }

  /// Increments today's review counter for [deckId] by 1.
  Future<void> incrementReviewCount(
    String deckId, {
    LearningMode learningMode = LearningMode.species,
  }) async {
    final db = await _database;
    await db.rawInsert(
      '''
      INSERT INTO daily_counts (deck_id, date, learning_mode, new_count, review_count)
      VALUES (?, ?, ?, 0, 1)
      ON CONFLICT(deck_id, date, learning_mode)
      DO UPDATE SET review_count = review_count + 1
      ''',
      [deckId, _today(), learningMode.storageValue],
    );
  }
}
