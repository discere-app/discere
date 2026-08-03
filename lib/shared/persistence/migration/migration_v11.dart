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
    await _executeSqlAsset(db, _createDeckConfigSqlAsset);
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
