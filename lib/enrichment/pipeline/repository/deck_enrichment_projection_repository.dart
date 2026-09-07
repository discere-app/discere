import 'package:discere/enrichment/model/deck_enrichment_projection.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_state_count.dart';
import 'package:discere/enrichment/pipeline/repository/deck_projection_builder.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Reads the enrichment work queue without changing it: the per-deck
/// projection the UI derives its state from, the delta query that says which
/// decks moved, and the aggregate counts behind the diagnostics page.
///
/// Split from the write paths because nothing here participates in their
/// transactions — every method is a query, and the rules applied to what
/// comes back live in [DeckProjectionBuilder] rather than in the SQL.
class DeckEnrichmentProjectionRepository {
  final Database? _injectedDb;

  const DeckEnrichmentProjectionRepository([this._injectedDb]);

  Future<Database> get _db async => _injectedDb ?? DatabaseHelper.userDb;

  /// Builds the [DeckEnrichmentProjection] for [deckId] from every species
  /// currently in the deck's membership (regardless of which deck "owns" a
  /// given shared species), the taxonomy items its species reference, and
  /// the names it could not resolve.
  ///
  /// [currentReferenceDbVersion], when given, also yields
  ///  — species whose  capability is terminal
  /// but was stamped, or never stamped, with an older reference-DB version.
  Future<DeckEnrichmentProjection> loadDeckProjection(
    String deckId, {
    int? currentReferenceDbVersion,
  }) async {
    final db = await _db;

    final speciesRows = await db.rawQuery(
      '''
      SELECT m.species_id AS species_id, c.capability AS capability,
             c.state AS state, c.next_attempt_at AS next_attempt_at,
             c.reference_db_version AS reference_db_version,
             w.wants_inat_photos AS wants_inat_photos,
             w.wants_common_names AS wants_common_names
        FROM ${EnrichmentWorkTables.deckMembership} m
        LEFT JOIN ${EnrichmentWorkTables.capabilityState} c
               ON c.species_id = m.species_id
        LEFT JOIN ${EnrichmentWorkTables.speciesWork} w
               ON w.species_id = m.species_id
       WHERE m.deck_id = ?
      ''',
      [deckId],
    );

    // Taxa referenced by this deck = taxa whose species are members of it.
    // DISTINCT collapses a taxon shared by several of the deck's species into
    // one row (state/next_attempt_at are functionally determined by work_key).
    final taxonomyRows = await db.rawQuery(
      '''
      SELECT DISTINCT t.work_key AS work_key,
             t.common_names_state AS common_names_state,
             t.next_attempt_at AS next_attempt_at
        FROM ${EnrichmentWorkTables.taxonomyWork} t
        JOIN ${EnrichmentWorkTables.taxonomyWorkSpecies} ts
          ON ts.work_key = t.work_key
        JOIN ${EnrichmentWorkTables.deckMembership} m
          ON m.species_id = ts.species_id
       WHERE m.deck_id = ?
      ''',
      [deckId],
    );

    final unresolvedNameRows = await db.query(
      EnrichmentWorkTables.unresolvedNames,
      where: 'deck_id = ?',
      whereArgs: [deckId],
    );

    return DeckProjectionBuilder(
      speciesRows: speciesRows,
      taxonomyRows: taxonomyRows,
      unresolvedNameRows: unresolvedNameRows,
      currentReferenceDbVersion: currentReferenceDbVersion,
    ).build(deckId);
  }

  /// Returns every deck id whose enrichment state changed at or after
  /// [sinceMillis] (epoch milliseconds), across all three queue tables —
  /// the cheap "what changed" query a poller uses to only recompute
  /// [loadDeckProjection] for decks that actually moved, the same way
  /// `EnrichmentJobRepository.loadJobsUpdatedSince`'s delta-loading avoids
  /// reprocessing decks that haven't changed.
  ///
  /// Deliberately `>=`, not `>`: [sinceMillis] is captured (by the caller)
  /// before the query runs, and timestamps here have millisecond resolution
  /// — a write landing in that same millisecond would compare equal, and a
  /// strict `>` would exclude it from this poll *and* every future one
  /// (the cursor never moves backward), silently freezing that deck's state
  /// forever. Matches `EnrichmentJobRepository.loadJobsUpdatedSince`, which
  /// uses `>=` for the same reason.
  Future<Set<String>> loadDeckIdsUpdatedSince(int sinceMillis) async {
    final db = await _db;
    final deckIds = <String>{};

    final capabilityRows = await db.rawQuery(
      '''
      SELECT DISTINCT m.deck_id AS deck_id
        FROM ${EnrichmentWorkTables.capabilityState} c
        JOIN ${EnrichmentWorkTables.deckMembership} m ON m.species_id = c.species_id
       WHERE c.updated_at >= ?
      ''',
      [sinceMillis],
    );
    for (final row in capabilityRows) {
      deckIds.add(row['deck_id'] as String);
    }

    final taxonomyRows = await db.rawQuery(
      '''
      SELECT DISTINCT m.deck_id AS deck_id
        FROM ${EnrichmentWorkTables.taxonomyWork} t
        JOIN ${EnrichmentWorkTables.taxonomyWorkSpecies} ts ON ts.work_key = t.work_key
        JOIN ${EnrichmentWorkTables.deckMembership} m ON m.species_id = ts.species_id
       WHERE t.updated_at >= ?
      ''',
      [sinceMillis],
    );
    for (final row in taxonomyRows) {
      deckIds.add(row['deck_id'] as String);
    }

    final unresolvedRows = await db.query(
      EnrichmentWorkTables.unresolvedNames,
      columns: const ['deck_id'],
      where: 'updated_at >= ?',
      whereArgs: [sinceMillis],
    );
    for (final row in unresolvedRows) {
      deckIds.add(row['deck_id'] as String);
    }

    return deckIds;
  }

  /// Whether any species/taxonomy/unresolved-name work anywhere is still
  /// non-terminal — the aggregate counterpart to
  /// `EnrichmentJobRepository.hasPendingWork` used to decide whether the
  /// background keepalive service needs to stay up.
  Future<bool> hasPendingWork() async {
    final db = await _db;
    final capabilityRows = await db.query(
      EnrichmentWorkTables.capabilityState,
      columns: const ['species_id'],
      where: 'state NOT IN (?, ?, ?)',
      whereArgs: terminalStates,
      limit: 1,
    );
    if (capabilityRows.isNotEmpty) return true;

    final taxonomyRows = await db.query(
      EnrichmentWorkTables.taxonomyWork,
      columns: const ['work_key'],
      where: 'common_names_state NOT IN (?, ?, ?)',
      whereArgs: terminalStates,
      limit: 1,
    );
    if (taxonomyRows.isNotEmpty) return true;

    final unresolvedRows = await db.query(
      EnrichmentWorkTables.unresolvedNames,
      columns: const ['name'],
      where: 'state != ?',
      whereArgs: [EnrichmentWorkState.permanentFailure.wireName],
      limit: 1,
    );
    return unresolvedRows.isNotEmpty;
  }

  /// Species from [speciesIds] whose `speciesCommonNames` capability hasn't
  /// reached a terminal state yet — i.e. common-name enrichment might still
  /// change the primary name a flashcard currently shows for them. A species
  /// with no `speciesCommonNames` row at all (never consented, or not seeded
  /// yet) is treated as nothing-pending rather than guessed at.
  Future<Set<String>> getPendingCommonNameSpeciesIds(
    Set<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) return {};

    final db = await _db;
    final pending = <String>{};
    const chunkSize = 900;
    final idList = speciesIds.toList();

    for (var i = 0; i < idList.length; i += chunkSize) {
      final chunk = idList.skip(i).take(chunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await db.query(
        EnrichmentWorkTables.capabilityState,
        columns: ['species_id', 'state'],
        where: 'species_id IN ($placeholders) AND capability = ?',
        whereArgs: [...chunk, 'speciesCommonNames'],
      );
      for (final row in rows) {
        if (!terminalStates.contains(row['state'] as String?)) {
          pending.add(row['species_id'] as String);
        }
      }
    }

    return pending;
  }

  /// Live counts of species-capability work items grouped by capability and
  /// state — used by the diagnostics page to show what's still outstanding
  /// without reconstructing it from an event log.
  Future<List<EnrichmentWorkStateCount>> loadCapabilityStateCounts() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT capability, state, COUNT(*) as count, '
      'MIN(next_attempt_at) as next_attempt_at FROM ${EnrichmentWorkTables.capabilityState} '
      'GROUP BY capability, state',
    );
    return rows
        .map(
          (row) => EnrichmentWorkStateCount(
            label: row['capability'] as String,
            state: EnrichmentWorkState.fromWire(row['state'] as String),
            count: row['count'] as int,
            nextAttemptAt: _millisToDateTime(row['next_attempt_at'] as int?),
          ),
        )
        .toList(growable: false);
  }

  /// Live counts of taxonomy common-name work items grouped by state.
  Future<List<EnrichmentWorkStateCount>> loadTaxonomyWorkStateCounts() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT common_names_state as state, COUNT(*) as count, '
      'MIN(next_attempt_at) as next_attempt_at '
      'FROM ${EnrichmentWorkTables.taxonomyWork} GROUP BY common_names_state',
    );
    return rows
        .map(
          (row) => EnrichmentWorkStateCount(
            label: 'taxonomyCommonNames',
            state: EnrichmentWorkState.fromWire(row['state'] as String),
            count: row['count'] as int,
            nextAttemptAt: _millisToDateTime(row['next_attempt_at'] as int?),
          ),
        )
        .toList(growable: false);
  }

  /// Live counts of species stuck in [EnrichmentWorkTables.unresolvedNames] (no taxonomy
  /// match yet) grouped by state.
  Future<List<EnrichmentWorkStateCount>>
  loadUnresolvedNamesStateCounts() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT state, COUNT(*) as count, MIN(next_attempt_at) as next_attempt_at '
      'FROM ${EnrichmentWorkTables.unresolvedNames} GROUP BY state',
    );
    return rows
        .map(
          (row) => EnrichmentWorkStateCount(
            label: 'unresolvedNames',
            state: EnrichmentWorkState.fromWire(row['state'] as String),
            count: row['count'] as int,
            nextAttemptAt: _millisToDateTime(row['next_attempt_at'] as int?),
          ),
        )
        .toList(growable: false);
  }

  static DateTime? _millisToDateTime(int? millis) {
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
