part of '../user_db_schema.dart';

/// Migration v12 → v13: prune deck_config/flashcard_stats rows whose
/// deck_id no longer exists in decks, then (see DatabaseHelper.userDb's
/// onOpen, applied right after this migration completes) switch on
/// `PRAGMA foreign_keys`. deck_config/flashcard_stats already declare
/// `ON DELETE CASCADE` to decks, but that constraint is only enforced once
/// the pragma is on — until now, deleting a deck left its config/stat rows
/// behind. Enabling the pragma only affects writes from this point forward,
/// so any orphans already sitting in the database need a one-time sweep
/// first, before enforcement can be turned on safely.
///
/// Both tables are swept only if they are there: `flashcard_stats` is absent
/// for a database coming from v1 or v2, where v5 drops it (removing the
/// legacy SM-2 columns) and nothing recreates it until the current schema is
/// rebuilt after the last migration. There are then no orphans to sweep, and
/// nothing for the pragma to enforce against either.
Future<void> migrateUserDbToV13(Database db) async {
  _log.debug(
    'Migrating user DB v12 → v13: pruning deck_config/flashcard_stats rows '
    'orphaned before FK enforcement existed',
  );
  final prunedDeckConfigs = await _deleteOrphanedDeckRows(db, 'deck_config');
  final prunedFlashcardStats = await _deleteOrphanedDeckRows(
    db,
    'flashcard_stats',
  );
  _log.debug(
    'Pruned orphaned rows: deck_config=$prunedDeckConfigs '
    'flashcard_stats=$prunedFlashcardStats',
  );
}

Future<int> _deleteOrphanedDeckRows(Database db, String table) async {
  if (!await _tableExists(db, table)) return 0;
  return db.delete(table, where: 'deck_id NOT IN (SELECT id FROM decks)');
}
