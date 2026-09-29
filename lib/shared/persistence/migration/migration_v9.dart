part of '../user_db_schema.dart';

/// Migration v8 → v9: Add name_type to deck_config, flashcard_stats and
/// daily_counts, so common-name and scientific-name progress are tracked
/// independently. Existing progress is preserved as commonName-mode progress.
Future<void> migrateUserDbToV9(Database db) async {
  _log.debug('Migrating user DB v8 → v9: adding per-name-type learning stats');

  await _ensureColumnExists(
    db,
    'deck_config',
    'name_type',
    "TEXT NOT NULL DEFAULT 'commonName'",
  );

  if (await _tableExists(db, 'flashcard_stats')) {
    await db.execute(
      'ALTER TABLE flashcard_stats RENAME TO flashcard_stats_old',
    );
    // The v9 shape, frozen inline. It happens to match the current schema
    // asset — flashcard_stats has not changed since — but it is written out
    // anyway: the next change to that asset must not silently become part of
    // this migration. A migration describes the schema as it was.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS flashcard_stats (
        species_id       TEXT NOT NULL,
        deck_id          TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
        learning_mode    TEXT NOT NULL DEFAULT 'species',
        name_type        TEXT NOT NULL DEFAULT 'commonName',
        next_review_date INTEGER,
        stability        REAL    DEFAULT 0.0,
        difficulty       REAL    DEFAULT 0.0,
        last_review_date INTEGER,
        card_state       INTEGER DEFAULT 0,
        step_index       INTEGER DEFAULT 0,
        PRIMARY KEY (deck_id, species_id, learning_mode, name_type)
      )
      ''');
    await db.execute('''
      INSERT INTO flashcard_stats (
        species_id,
        deck_id,
        learning_mode,
        name_type,
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
        learning_mode,
        'commonName',
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
    // The v9 shape, frozen inline — the table has had no schema asset since
    // v11 dropped it.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_counts (
        deck_id      TEXT    NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
        date         TEXT    NOT NULL,
        learning_mode TEXT   NOT NULL DEFAULT 'species',
        name_type    TEXT    NOT NULL DEFAULT 'commonName',
        new_count    INTEGER DEFAULT 0,
        review_count INTEGER DEFAULT 0,
        PRIMARY KEY (deck_id, date, learning_mode, name_type)
      )
      ''');
    await db.execute('''
      INSERT INTO daily_counts (
        deck_id,
        date,
        learning_mode,
        name_type,
        new_count,
        review_count
      )
      SELECT deck_id, date, learning_mode, 'commonName', new_count, review_count
      FROM daily_counts_old
      ''');
    await db.execute('DROP TABLE daily_counts_old');
  }
}
