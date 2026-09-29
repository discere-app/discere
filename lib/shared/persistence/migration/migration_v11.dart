part of '../user_db_schema.dart';

/// Migration v10 → v11: Remove the daily new-card/review limits
/// (new_cards_per_day, max_reviews_per_day on deck_config; the whole
/// daily_counts table). These were never surfaced in any settings UI, so a
/// deck could silently hit its cap and leave the "activate more cards?"
/// dialog looping with no feedback once the default budget was exhausted.
Future<void> migrateUserDbToV11(Database db) async {
  _log.debug(
    'Migrating user DB v10 → v11: removing daily new-card/review limits',
  );

  if (await _tableExists(db, 'deck_config')) {
    await db.execute('ALTER TABLE deck_config RENAME TO deck_config_old');
    // The v11 shape, frozen inline. It happens to match the current schema
    // asset — deck_config has not changed since — but it is written out
    // anyway: this rebuild copies a fixed column list, so a column added to
    // that asset later would arrive here unpopulated and a column removed
    // from it would break the INSERT. A migration describes the schema as it
    // was.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS deck_config (
        deck_id              TEXT PRIMARY KEY REFERENCES decks(id) ON DELETE CASCADE,
        desired_retention    REAL    DEFAULT 0.9,
        maximum_interval     INTEGER DEFAULT 36500,
        learning_steps       TEXT    DEFAULT '1,10',
        relearning_steps     TEXT    DEFAULT '10',
        learning_mode        TEXT    NOT NULL DEFAULT 'species',
        name_type            TEXT    NOT NULL DEFAULT 'commonName',
        review_mode          TEXT    NOT NULL DEFAULT 'flip'
      )
      ''');
    await db.execute('''
      INSERT INTO deck_config (
        deck_id,
        desired_retention,
        maximum_interval,
        learning_steps,
        relearning_steps,
        learning_mode,
        name_type,
        review_mode
      )
      SELECT
        deck_id,
        desired_retention,
        maximum_interval,
        learning_steps,
        relearning_steps,
        learning_mode,
        name_type,
        review_mode
      FROM deck_config_old
      ''');
    await db.execute('DROP TABLE deck_config_old');
  }

  await db.execute('DROP TABLE IF EXISTS daily_counts');
}
