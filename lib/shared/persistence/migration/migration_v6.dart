part of '../user_db_schema.dart';

/// Migration v5 → v6: Add learning_mode to deck_config, flashcard_stats and
/// daily_counts. Existing progress is preserved as species-mode progress.
Future<void> migrateUserDbToV6(Database db) async {
  _log.debug('Migrating user DB v5 → v6: adding per-mode learning stats');

  if (!await _tableHasColumn(db, 'deck_config', 'learning_mode')) {
    await db.execute(
      "ALTER TABLE deck_config ADD COLUMN learning_mode TEXT NOT NULL DEFAULT 'species'",
    );
  }

  if (await _tableExists(db, 'flashcard_stats')) {
    await db.execute(
      'ALTER TABLE flashcard_stats RENAME TO flashcard_stats_old',
    );
    await _executeSqlAsset(db, _createFlashcardStatsSqlAsset);
    await db.execute('''
      INSERT INTO flashcard_stats (
        species_id,
        deck_id,
        learning_mode,
        next_review_date,
        stability,
        difficulty,
        last_review_date,
        card_state,
        step_index
      )
      SELECT
        species_id,
        deck_id,
        'species',
        next_review_date,
        stability,
        difficulty,
        last_review_date,
        card_state,
        step_index
      FROM flashcard_stats_old
      ''');
    await db.execute('DROP TABLE flashcard_stats_old');
  }

  if (await _tableExists(db, 'daily_counts')) {
    await db.execute('ALTER TABLE daily_counts RENAME TO daily_counts_old');
    await _executeSqlAsset(db, _createDailyCountsSqlAsset);
    await db.execute('''
      INSERT INTO daily_counts (
        deck_id,
        date,
        learning_mode,
        new_count,
        review_count
      )
      SELECT deck_id, date, 'species', new_count, review_count
      FROM daily_counts_old
      ''');
    await db.execute('DROP TABLE daily_counts_old');
  }
}
