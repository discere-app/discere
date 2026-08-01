part of '../user_db_schema.dart';

/// Migration v1 → v2: Add card_state and step_index columns for learning steps.
/// Existing reviewed cards are set to CardState.review (2).
Future<void> migrateUserDbToV2(Database db) async {
  _log.debug('Migrating user DB v1 → v2: adding card_state, step_index');
  await db.execute(
    'ALTER TABLE flashcard_stats ADD COLUMN card_state INTEGER DEFAULT 0',
  );
  await db.execute(
    'ALTER TABLE flashcard_stats ADD COLUMN step_index INTEGER DEFAULT 0',
  );
  // Cards that have been reviewed (have a lastReviewDate) are in Review state
  await db.execute(
    'UPDATE flashcard_stats SET card_state = 2 '
    'WHERE last_review_date IS NOT NULL',
  );
}
