part of '../user_db_schema.dart';

/// Migration v16 → v17: adds `reference_db_version` to
/// `enrichment_species_capability_state`, stamped by `BaseWorker` whenever it
/// marks a species' `base` capability terminal. Lets the app detect which
/// species' reference images were resolved against an older reference-DB
/// version than the one currently installed, so the user can be offered a
/// refresh — either globally right after a reference-DB update, or later,
/// per deck, from the Edit Deck page. Existing rows are left `NULL` —
/// treated as stale by the staleness comparison, since there's no record of
/// which reference-DB version was current when they last completed.
Future<void> migrateUserDbToV17(Database db) async {
  _log.debug(
    'Migrating user DB v16 → v17: adding reference_db_version to '
    'enrichment_species_capability_state',
  );
  await _ensureColumnExists(
    db,
    'enrichment_species_capability_state',
    'reference_db_version',
    'INTEGER',
  );
}
