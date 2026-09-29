part of '../user_db_schema.dart';

/// Migration v18 → v19: drops `runtime_common_names` where it still has the
/// shape it had before iNaturalist common names carried a region.
///
/// The table originally stored one row per entity and language with a JSON
/// list in a `names` column. It now stores one row per *name*, with `name`,
/// `position`, `place_id` and `place_position`, and no primary key. That
/// change shipped without a migration — the user database was still at
/// version 1 with no `onUpgrade` at the time.
///
/// No installation is known to predate it, so this is expected to find
/// nothing. It is here because the cost of being wrong is not proportional:
/// the check is one `PRAGMA` on one upgrade, while a database that does carry
/// the old shape cannot be opened at all (see below), which is not a degraded
/// feature but an app that will not start.
///
/// Reconciliation cannot repair this one: `name` is `NOT NULL` with no
/// default, which SQLite will not add to a table that already has rows, so it
/// raises rather than leave the column missing. Dropping the table here is
/// what lets it rebuild the current shape immediately afterwards.
///
/// Dropping is safe because the content is a cache: runtime common names are
/// fetched from iNaturalist and re-fetched when absent. No user data lives
/// here.
Future<void> migrateUserDbToV19(Database db) async {
  // Keyed on the column that only the old shape has, rather than on the
  // absence of `name`: a table that has neither is not this table.
  if (!await _tableHasColumn(db, 'runtime_common_names', 'names')) return;

  _log.debug(
    'Migrating user DB v18 → v19: dropping the pre-region '
    'runtime_common_names cache so the current shape can be rebuilt',
  );
  await db.execute('DROP TABLE runtime_common_names');
}
