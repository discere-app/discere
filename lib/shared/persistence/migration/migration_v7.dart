part of '../user_db_schema.dart';

/// Migration v6 → v7: Add review_mode to deck_config (flip vs. multiple
/// choice review). Existing decks keep the flip behavior.
Future<void> migrateUserDbToV7(Database db) async {
  _log.debug('Migrating user DB v6 → v7: adding review_mode to deck_config');
  await _ensureColumnExists(
    db,
    'deck_config',
    'review_mode',
    "TEXT NOT NULL DEFAULT 'flip'",
  );
}
