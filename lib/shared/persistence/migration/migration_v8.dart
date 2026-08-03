part of '../user_db_schema.dart';

/// Migration v7 → v8: Add sortOrder to decks so the deck list has a stable,
/// user-controllable order. Editing a deck (which upserts via
/// `INSERT OR REPLACE`) previously reshuffled the rowid-based scan order;
/// existing decks are backfilled by their current rowid order so the
/// visible order does not jump on upgrade.
Future<void> migrateUserDbToV8(Database db) async {
  _log.debug('Migrating user DB v7 → v8: adding sortOrder to decks');
  await _ensureColumnExists(
    db,
    'decks',
    'sortOrder',
    'INTEGER NOT NULL DEFAULT 0',
  );
  await db.execute('''
    UPDATE decks SET sortOrder = (
      SELECT COUNT(*) FROM decks AS earlier
      WHERE earlier.rowid <= decks.rowid
    )
    ''');
}
