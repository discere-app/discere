part of '../user_db_schema.dart';

/// Migration v3 → v4: Add daily_counts table and new_cards_per_day /
/// max_reviews_per_day columns to deck_config.
Future<void> migrateUserDbToV4(Database db) async {
  _log.debug(
    'Migrating user DB v3 → v4: adding daily_counts table and daily-limit columns',
  );
  await _executeSqlAsset(db, _createDailyCountsSqlAsset);
  await db.execute(
    'ALTER TABLE deck_config ADD COLUMN new_cards_per_day INTEGER DEFAULT 20',
  );
  await db.execute(
    'ALTER TABLE deck_config ADD COLUMN max_reviews_per_day INTEGER DEFAULT 200',
  );
}
