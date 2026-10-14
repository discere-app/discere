import 'package:discere/shared/persistence/reference_id/keyed_id_rewrite.dart';
import 'package:discere/shared/persistence/reference_id/reference_alias_map.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_rewrite_report.dart';
import 'package:discere/shared/persistence/reference_id/search_document_merge.dart';
import 'package:sqflite/sqflite.dart';

/// Every user-database column that holds an ID of the reference database,
/// with the rule for rows that collide once two IDs become one — the matrix
/// in `etl/docs/datenquellen.md` ("Aliase führen Entitäten zusammen").
///
/// A table that starts storing reference IDs belongs here, and in that
/// matrix. Tables that refer to taxa by name (`genus:gobio`) or to decks by
/// deck ID are not affected by an alias and are not listed.
///
/// The order matters once: `enrichment_species_work` recounts its decks from
/// `enrichment_species_deck_membership`, so the membership comes first.
final referenceIdTables = <KeyedIdTable>[
  _speciesIdTable(
    'flashcard_stats',
    keyColumns: const ['deck_id', 'learning_mode', 'name_type'],
    valueColumns: const ['last_review_date', 'next_review_date'],
    onCollision: keepMostRecentlyReviewed,
  ),
  _speciesIdTable('species_photo_gap_ack', keyColumns: const ['deck_id']),
  _speciesIdTable(
    'enrichment_species_deck_membership',
    keyColumns: const ['deck_id'],
  ),
  _speciesIdTable(
    'enrichment_species_work',
    keyColumns: const [],
    valueColumns: _consentColumns,
    onCollision: keepExistingWithCombinedConsent,
    afterRewrite: _recountSpeciesWorkDecks,
  ),
  _speciesIdTable(
    'enrichment_species_capability_state',
    keyColumns: const ['capability'],
    valueColumns: const ['state'],
    onCollision: keepDoneElseExisting,
  ),
  _speciesIdTable(
    'enrichment_taxonomy_work_species',
    keyColumns: const ['work_key'],
  ),
  _speciesIdTable('inat_photo_cache', keyColumns: const ['photo_url']),
  KeyedIdTable(
    table: 'external_identifier_cache',
    idSql: '{t}.entity_id',
    setIdSql: (newId) => 'entity_id = $newId',
    keyColumns: const ['provider'],
    onCollision: _keepExisting,
  ),
  KeyedIdTable(
    table: 'runtime_common_names',
    idSql: _speciesKeyIdSql,
    scopeSql: _speciesKeyScopeSql,
    setIdSql: _setSpeciesKey,
    keyColumns: const ['language_code', 'name', 'place_id'],
    valueColumns: const ['fetched_at'],
    onCollision: keepMostRecentlyFetched,
  ),
  KeyedIdTable(
    table: searchDocumentsTable,
    idSql: _speciesKeyIdSql,
    scopeSql: _speciesKeyScopeSql,
    setIdSql: _setSpeciesKey,
    keyColumns: const [],
    valueColumns: searchDocumentValueColumns,
    onCollision: mergeSearchDocuments,
    afterRewrite: syncSearchIndex,
  ),
];

/// The ID inside a `species:<id>` entity key.
const _speciesKeyIdSql = 'substr({t}.entity_key, 9)';
const _speciesKeyScopeSql = "substr({t}.entity_key, 1, 8) = 'species:'";
String _setSpeciesKey(String newId) => "entity_key = 'species:' || $newId";

const _consentColumns = ['wants_inat_photos', 'wants_common_names'];

KeyedIdTable _speciesIdTable(
  String table, {
  required List<String> keyColumns,
  List<String> valueColumns = const [],
  CollisionRule onCollision = _keepExisting,
  AfterRewrite? afterRewrite,
}) => KeyedIdTable(
  table: table,
  idSql: '{t}.species_id',
  setIdSql: (newId) => 'species_id = $newId',
  keyColumns: keyColumns,
  valueColumns: valueColumns,
  onCollision: onCollision,
  afterRewrite: afterRewrite,
);

/// The user database's reference IDs, over every column [referenceIdTables]
/// rewrites plus the entity IDs of the search documents, which hold IDs of
/// every rank.
Future<Set<String>> collectReferencedIds(DatabaseExecutor userDb) async {
  final selects = [
    for (final table in referenceIdTables)
      'SELECT ${table.idSql.replaceAll('{t}', table.table)} AS id '
          'FROM ${table.table} '
          'WHERE ${table.scopeSql.replaceAll('{t}', table.table)}',
    'SELECT entity_id AS id FROM $searchDocumentsTable',
  ];
  final rows = await userDb.rawQuery(selects.join(' UNION '));
  return {for (final row in rows) row['id'] as String};
}

/// Rewrites the search documents' `entity_id`. Not a key, so nothing can
/// collide; a genus document's ID changes like a species document's.
Future<void> rewriteSearchDocumentEntityIds(
  Transaction txn,
  ReferenceIdRewriteReport report,
) async {
  const alias = ReferenceAliasMap.tempTable;
  final rewritten = await txn.rawUpdate('''
    UPDATE $searchDocumentsTable
       SET entity_id = (SELECT new_id FROM $alias
                         WHERE old_id = $searchDocumentsTable.entity_id)
     WHERE entity_id IN (SELECT old_id FROM $alias)
  ''');
  report.record(
    '$searchDocumentsTable.entity_id',
    rewritten: rewritten,
    dropped: 0,
  );
}

CollisionOutcome _keepExisting(List<IdRow> group) =>
    CollisionOutcome(existingRowOrSmallestOldId(group));

/// `flashcard_stats`: the card reviewed last stays, then the one due last,
/// and among equals the one with the smaller old ID. A missing date ranks
/// below any date.
CollisionOutcome keepMostRecentlyReviewed(List<IdRow> group) {
  final ranked = List.of(group)
    ..sort((a, b) {
      for (final column in const ['last_review_date', 'next_review_date']) {
        final byDate = _descendingNullsLast(
          a.values[column] as int?,
          b.values[column] as int?,
        );
        if (byDate != 0) return byDate;
      }
      return a.oldId.compareTo(b.oldId);
    });
  return CollisionOutcome(ranked.first);
}

/// `runtime_common_names`: of identical names, the one fetched last stays.
CollisionOutcome keepMostRecentlyFetched(List<IdRow> group) {
  final ranked = List.of(group)
    ..sort((a, b) {
      final byFetch = _descendingNullsLast(
        a.values['fetched_at'] as int?,
        b.values['fetched_at'] as int?,
      );
      if (byFetch != 0) return byFetch;
      if (a.isAliased != b.isAliased) return a.isAliased ? 1 : -1;
      final byOldId = a.oldId.compareTo(b.oldId);
      return byOldId != 0 ? byOldId : a.rowId.compareTo(b.rowId);
    });
  return CollisionOutcome(ranked.first);
}

/// `enrichment_species_capability_state`: a capability one of the merged
/// species already completed stays completed — its result (photos, names)
/// moved to the valid ID with the cache tables. Otherwise the existing row
/// stays. No row is dropped: a missing capability is only seeded again when
/// the user schedules the deck, so the merged species would never get it.
CollisionOutcome keepDoneElseExisting(List<IdRow> group) {
  final done = [
    for (final row in group)
      if (row.values['state'] == 'done') row,
  ];
  return CollisionOutcome(
    existingRowOrSmallestOldId(done.isEmpty ? group : done),
  );
}

/// `enrichment_species_work`: the existing row stays, and a deck's consent
/// to photos or names given under either ID still holds.
CollisionOutcome keepExistingWithCombinedConsent(List<IdRow> group) {
  final survivor = existingRowOrSmallestOldId(group);
  final update = <String, Object?>{};
  for (final column in _consentColumns) {
    final combined = group.any((row) => row.values[column] == 1) ? 1 : 0;
    if (combined != survivor.values[column]) update[column] = combined;
  }
  return CollisionOutcome(survivor, update);
}

/// `deck_count` is the number of membership rows, which a merge changes.
Future<void> _recountSpeciesWorkDecks(
  Transaction txn, {
  required List<int> droppedRowIds,
  required List<int> mergedRowIds,
}) => txn.execute('''
  UPDATE enrichment_species_work
     SET deck_count = (SELECT COUNT(*) FROM enrichment_species_deck_membership m
                        WHERE m.species_id = enrichment_species_work.species_id)
   WHERE species_id IN (SELECT new_id FROM ${ReferenceAliasMap.tempTable})
''');

int _descendingNullsLast(int? a, int? b) {
  if (a == b) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}
