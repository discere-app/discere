part of '../user_db_schema.dart';

/// Migration v15 → v16: remaps the legacy `'succeeded'` value in
/// `enrichment_taxonomy_work.common_names_state` to `'done'`.
///
/// The v11 → v12 producer-consumer cutover (`migration_v12.dart`) remapped
/// this exact old-vocabulary value on `enrichment_species_work`'s four stage
/// columns, but never touched `enrichment_taxonomy_work.common_names_state`
/// — that table only gained retry-bookkeeping columns, its existing values
/// were left as-is. Current code only ever writes `pending`/`running`/
/// `retryScheduled`/`permanentFailure`/`done`/`noResult` to that column (see
/// `_capabilityStateTerminal` in `EnrichmentWorkRepository`), so a lingering
/// `'succeeded'` row is invisible to every terminal-state check and keeps
/// `DeckEnrichmentProjection.allSpeciesWorkTerminal` false forever for any
/// deck referencing it — including decks imported after the cutover, since
/// taxonomy work is deduped globally across all decks by rank+taxon.
Future<void> migrateUserDbToV16(Database db) async {
  _log.debug(
    'Migrating user DB v15 → v16: remapping legacy enrichment_taxonomy_work '
    "common_names_state 'succeeded' -> 'done'",
  );
  final updated = await db.update(
    'enrichment_taxonomy_work',
    {'common_names_state': 'done'},
    where: 'common_names_state = ?',
    whereArgs: ['succeeded'],
  );
  _log.debug('Remapped $updated legacy succeeded taxonomy row(s)');
}
