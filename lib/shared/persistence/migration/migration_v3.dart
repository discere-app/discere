part of '../user_db_schema.dart';

/// Migration v2 → v3: Add deck_config table for per-deck SRS settings.
Future<void> migrateUserDbToV3(Database db) async {
  _log.debug('Migrating user DB v2 → v3: adding deck_config table');
  // The v3 shape, frozen inline rather than taken from the current schema
  // asset: deck_config has changed four times since (learning_mode in v6,
  // review_mode in v7, name_type in v9, daily limits removed in v11), and
  // the later migrations add exactly those columns. Running today's asset
  // here would create them up front, and the migration that adds one would
  // then work on a table that already has it. A migration describes the
  // schema as it was.
  //
  // The daily-limit columns are deliberately absent although the asset
  // shipped in the very same commit as this migration already carried them:
  // v4 adds new_cards_per_day/max_reviews_per_day with a bare `ALTER TABLE
  // … ADD COLUMN`, which fails on a table that already has them. Where the
  // asset history and the ALTER chain disagree, the ALTER chain decides —
  // it is the only reading under which v3 → v4 runs at all.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS deck_config (
      deck_id              TEXT PRIMARY KEY REFERENCES decks(id) ON DELETE CASCADE,
      desired_retention    REAL    DEFAULT 0.9,
      maximum_interval     INTEGER DEFAULT 36500,
      learning_steps       TEXT    DEFAULT '1,10',
      relearning_steps     TEXT    DEFAULT '10'
    )
    ''');
}
