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
Future<void> migrateUserDbToV13(Database db) async {
  _log.debug(
    'Migrating user DB v12 → v13: pruning deck_config/flashcard_stats rows '
    'orphaned before FK enforcement existed',
  );
  final prunedDeckConfigs = await db.delete(
    'deck_config',
    where: 'deck_id NOT IN (SELECT id FROM decks)',
  );
  final prunedFlashcardStats = await db.delete(
    'flashcard_stats',
    where: 'deck_id NOT IN (SELECT id FROM decks)',
  );
  _log.debug(
    'Pruned orphaned rows: deck_config=$prunedDeckConfigs '
    'flashcard_stats=$prunedFlashcardStats',
  );
}
