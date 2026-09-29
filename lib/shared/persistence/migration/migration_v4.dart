part of '../user_db_schema.dart';

/// Migration v3 → v4: Add daily_counts table and new_cards_per_day /
/// max_reviews_per_day columns to deck_config.
Future<void> migrateUserDbToV4(Database db) async {
  _log.debug(
    'Migrating user DB v3 → v4: adding daily_counts table and daily-limit columns',
  );
  // The v4 shape, frozen inline: daily_counts grew a learning_mode column in
  // v6 and a name_type column in v9, both of which those migrations add by
  // rebuilding the table from what is here. It has no schema asset any more
  // — v11 dropped the table outright — so there is nothing left to copy
  // from either. A migration describes the schema as it was.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS daily_counts (
      deck_id      TEXT    NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
      date         TEXT    NOT NULL,
      new_count    INTEGER DEFAULT 0,
      review_count INTEGER DEFAULT 0,
      PRIMARY KEY (deck_id, date)
    )
    ''');
  await db.execute(
    'ALTER TABLE deck_config ADD COLUMN new_cards_per_day INTEGER DEFAULT 20',
  );
  await db.execute(
    'ALTER TABLE deck_config ADD COLUMN max_reviews_per_day INTEGER DEFAULT 200',
  );
}
