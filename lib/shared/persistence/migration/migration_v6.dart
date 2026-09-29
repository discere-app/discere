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
    // The v6 shape, frozen inline rather than taken from the current schema
    // asset: v9 adds name_type to flashcard_stats (and to its primary key)
    // the same way, by rebuilding from what is here. Creating today's
    // already-widened table instead would leave v9 copying a column into
    // itself. A migration describes the schema as it was.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS flashcard_stats (
        species_id       TEXT NOT NULL,
        deck_id          TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
        learning_mode    TEXT NOT NULL DEFAULT 'species',
        next_review_date INTEGER,
        stability        REAL    DEFAULT 0.0,
        difficulty       REAL    DEFAULT 0.0,
        last_review_date INTEGER,
        card_state       INTEGER DEFAULT 0,
        step_index       INTEGER DEFAULT 0,
        PRIMARY KEY (deck_id, species_id, learning_mode)
      )
      ''');
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
    // The v6 shape, frozen inline — v9 widens it again by name_type, and the
    // table has had no schema asset since v11 dropped it.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_counts (
        deck_id      TEXT    NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
        date         TEXT    NOT NULL,
        learning_mode TEXT   NOT NULL DEFAULT 'species',
        new_count    INTEGER DEFAULT 0,
        review_count INTEGER DEFAULT 0,
        PRIMARY KEY (deck_id, date, learning_mode)
      )
      ''');
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
