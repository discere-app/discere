part of '../user_db_schema.dart';

/// Migration v9 → v10: Add sourceId and updatedAt to decks, populated for
/// decks imported from the online catalog (discere-data). sourceId is a
/// stable catalog identifier; updatedAt is the catalog entry's last-edited
/// timestamp. Both are null for locally-created decks and for existing
/// decks on upgrade.
Future<void> migrateUserDbToV10(Database db) async {
  _log.debug('Migrating user DB v9 → v10: adding sourceId, updatedAt to decks');
  await _ensureColumnExists(db, 'decks', 'sourceId', 'TEXT');
  await _ensureColumnExists(db, 'decks', 'updatedAt', 'INTEGER');
}
