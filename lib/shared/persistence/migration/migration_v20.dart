part of '../user_db_schema.dart';

/// Migration v19 → v20: discards what the old iNaturalist lookup recorded for
/// higher taxa it resolved by name, and queues them to be fetched again.
///
/// A genus, family, order or class without an iNaturalist id in the
/// reference database used to be resolved by a name search that also took a
/// synonym hit or, failing any match, the search's first result — Sebastidae
/// came back as Scorpaenidae, "Mollu" as a plant family — and never looked
/// beyond the taxon's own rank, so a class iNaturalist files as a subclass
/// (Elasmobranchii) ended as "no names". Both outcomes are final for the work
/// queue: the names are kept, the marker counts as done, and a new deck
/// reuses the finished row rather than queueing its own.
///
/// Which taxa this touches follows from how those outcomes were stored. A
/// search-resolved id is the only thing that writes a higher taxon into
/// `external_identifier_cache` (a reference-database id never lands there),
/// so every cached id marks a taxon whose names may belong to another one;
/// and every `__none__` marker may be a taxon the old search could not see.
/// For those, the names, the marker, the cached id and the search document
/// go, the document's full-text row first — the FTS table has no trigger,
/// and a left-over row would keep the wrong name findable. Taxa whose names
/// came through a reference id, and every species, stay as they are.
///
/// The taxonomy work rows are reset, not deleted: they are only created when
/// a species finishes its own enrichment, which for existing decks happened
/// long ago, so a deleted row would never come back. Their `work_key` stays;
/// later plans merge into the row by `runtime_entity_key`.
Future<void> migrateUserDbToV20(Database db) async {
  // Before reconciliation a database may lack any of these — one from an old
  // enough version, or one whose runtime_common_names v19 just dropped — so
  // each step only touches the tables that are there.
  final present = <String>{
    for (final table in const [
      'runtime_common_names',
      'runtime_common_name_search_documents',
      'runtime_common_name_search_fts',
      'external_identifier_cache',
      'enrichment_taxonomy_work',
    ])
      if (await _tableExists(db, table)) table,
  };
  final sources = [
    if (present.contains('external_identifier_cache'))
      'SELECT entity_id AS key FROM external_identifier_cache '
          "WHERE provider = 'inaturalist'",
    if (present.contains('runtime_common_names'))
      'SELECT entity_key AS key FROM runtime_common_names '
          "WHERE language_code = '__none__'",
  ];
  if (sources.isEmpty) return;

  await db.transaction((txn) async {
    final rows = await txn.rawQuery(
      'SELECT key FROM (${sources.join(' UNION ')}) '
      "WHERE key LIKE 'genus:%' OR key LIKE 'family:%' "
      "OR key LIKE 'order:%' OR key LIKE 'class:%'",
    );
    final entityKeys = [for (final row in rows) row['key'] as String];
    _log.debug(
      'Migrating user DB v19 → v20: re-queueing ${entityKeys.length} '
      'search-resolved or unnamed higher taxa',
    );

    final batch = txn.batch();
    for (final entityKey in entityKeys) {
      if (present.contains('runtime_common_name_search_documents')) {
        if (present.contains('runtime_common_name_search_fts')) {
          batch.rawDelete(
            'DELETE FROM runtime_common_name_search_fts WHERE rowid IN '
            '(SELECT rowid FROM runtime_common_name_search_documents '
            'WHERE entity_key = ?)',
            [entityKey],
          );
        }
        batch.delete(
          'runtime_common_name_search_documents',
          where: 'entity_key = ?',
          whereArgs: [entityKey],
        );
      }
      if (present.contains('runtime_common_names')) {
        batch.delete(
          'runtime_common_names',
          where: 'entity_key = ?',
          whereArgs: [entityKey],
        );
      }
      if (present.contains('external_identifier_cache')) {
        batch.delete(
          'external_identifier_cache',
          where: "entity_id = ? AND provider = 'inaturalist'",
          whereArgs: [entityKey],
        );
      }
      if (present.contains('enrichment_taxonomy_work')) {
        batch.update(
          'enrichment_taxonomy_work',
          {
            'common_names_state': 'pending',
            'attempt_count': 0,
            'next_attempt_at': null,
            'last_error': null,
            'last_failure_kind': null,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'runtime_entity_key = ?',
          whereArgs: [entityKey],
        );
      }
    }
    await batch.commit(noResult: true);
  });
}
