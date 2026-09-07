import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/pipeline/model/inat_work_item.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// What work exists in the queue, and who takes it next.
///
/// [seedCapability] puts a species' capability into the queue; the two claim
/// methods hand the oldest runnable row to a worker and flip it to `running`
/// in the same transaction, so two workers can never hold the same item.
///
/// Split from how an attempt *ends* ([EnrichmentWorkOutcomeRepository]) and
/// from the operational resets ([EnrichmentWorkMaintenanceRepository]): a
/// worker's loop asks this what to do, then reports back to the other.
class EnrichmentWorkClaimRepository {
  final Database? _injectedDb;

  const EnrichmentWorkClaimRepository([this._injectedDb]);

  Future<Database> get _db async => _injectedDb ?? DatabaseHelper.userDb;

  /// Idempotently ensures a `pending` queue row exists for [speciesId]/
  /// [capability] at [priorityTier]. A no-op if that (species, capability)
  /// row already exists (regardless of its current state) — this is how
  /// `inatPrimary`/`inatBackfill` get seeded reactively (e.g. by `BaseWorker`
  /// on a download failure) instead of upfront for every species.
  ///
  /// For the two iNat-photo capabilities (`inatPrimary`/`inatBackfill`),
  /// also a no-op if the species hasn't (yet) been granted
  /// `wants_inat_photos` consent — mirrors `_upsertSpeciesWorkAndCapabilities`
  /// only ever seeding `speciesCommonNames` up front when `wantsCommonNames`
  /// is true. Without this, a species belonging only to a deck that declined
  /// iNat photos would still get an iNat photo fetched the moment its
  /// reference-image download failed or was absent (`BaseWorker`'s
  /// fallback), since consent was never checked before reactively seeding
  /// these rows.
  Future<void> seedCapability(
    String speciesId,
    EnrichmentCapability capability, {
    required int priorityTier,
  }) async {
    final capabilityName = capability.wireName;
    final db = await _db;
    if (capabilityName == 'inatPrimary' || capabilityName == 'inatBackfill') {
      final speciesRows = await db.query(
        EnrichmentWorkTables.speciesWork,
        columns: const ['wants_inat_photos'],
        where: 'species_id = ?',
        whereArgs: [speciesId],
        limit: 1,
      );
      final wantsInatPhotos =
          speciesRows.isNotEmpty &&
          (speciesRows.single['wants_inat_photos'] as int? ?? 0) == 1;
      if (!wantsInatPhotos) return;
    }
    await db.insert(EnrichmentWorkTables.capabilityState, {
      'species_id': speciesId,
      'capability': capabilityName,
      'state': pendingState,
      'priority_tier': priorityTier,
      'attempt_count': 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Claims up to [limit] species needing `base` work (reference-image
  /// download), atomically flipping them to `running` so a concurrent call
  /// (there should only ever be one `BaseWorker`, but this keeps the
  /// contract honest) can't claim the same species twice.
  ///
  /// Requires an existing [EnrichmentWorkTables.deckMembership] row — a species can be
  /// seeded here and then have every deck referencing it deleted before this
  /// ever gets claimed (`releaseDeck` deliberately leaves this permanent
  /// dedup-cache row behind); without this check that claim would still go
  /// ahead and burn a real reference-image download for a species nobody
  /// wants anymore.
  Future<List<String>> claimBaseWorkBatch({required int limit}) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''
        SELECT c.species_id AS species_id
          FROM ${EnrichmentWorkTables.capabilityState} c
         WHERE c.capability = 'base'
           AND c.state IN (?, ?)
           AND (c.next_attempt_at IS NULL OR c.next_attempt_at <= ?)
           AND EXISTS (
             SELECT 1 FROM ${EnrichmentWorkTables.deckMembership} m
              WHERE m.species_id = c.species_id
           )
         ORDER BY c.updated_at ASC
         LIMIT ?
        ''',
        [pendingState, retryScheduledState, now, limit],
      );
      final speciesIds = rows
          .map((row) => row['species_id'] as String)
          .toList(growable: false);
      if (speciesIds.isEmpty) return const <String>[];
      await txn.update(
        EnrichmentWorkTables.capabilityState,
        {'state': runningState, 'updated_at': now},
        where:
            "capability = 'base' AND species_id IN "
            '(${List.filled(speciesIds.length, '?').join(', ')})',
        whereArgs: speciesIds,
      );
      return speciesIds;
    });
  }

  /// Claims the single highest-priority pending item across
  /// `inatPrimary`/`speciesCommonNames`/`inatBackfill` (from
  /// [EnrichmentWorkTables.capabilityState]), `taxonomyCommonNames` (from [EnrichmentWorkTables.taxonomyWork])
  /// and `nameResolution` (from [EnrichmentWorkTables.unresolvedNames]) — the shared queue a
  /// single rate-limited `INatWorker` drains. Lower `priority_tier` wins
  /// (species rows carry their own; taxonomy is always 30, name resolution
  /// always 50). Returns `null` when nothing is claimable.
  ///
  /// Runs one query per table rather than a single `UNION ALL`, since each
  /// table needs different columns back (taxonomy needs `runtime_entity_key`
  /// and `species_ids_json` too, not just its key) — three small queries in
  /// one transaction over these tiny tables is simpler than reshaping every
  /// row into a common column set.
  ///
  /// The species query requires an existing [EnrichmentWorkTables.deckMembership] row for
  /// the same reason [claimBaseWorkBatch] does — a species can outlive every
  /// deck that referenced it (its permanent dedup-cache row is deliberately
  /// left behind by `releaseDeck`) before a reactively-seeded item like
  /// `inatBackfill` ever gets claimed; without this check, that claim would
  /// still burn a real, rate-limited iNaturalist request for nothing.
  Future<INatWorkItem?> claimNextINatWorkItem() async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final speciesRows = await txn.rawQuery(
        '''
        SELECT c.species_id AS species_id, c.capability AS capability,
               c.priority_tier AS priority_tier
          FROM ${EnrichmentWorkTables.capabilityState} c
         WHERE c.capability IN ('inatPrimary', 'speciesCommonNames', 'inatBackfill')
           AND c.state IN (?, ?)
           AND (c.next_attempt_at IS NULL OR c.next_attempt_at <= ?)
           AND EXISTS (
             SELECT 1 FROM ${EnrichmentWorkTables.deckMembership} m
              WHERE m.species_id = c.species_id
           )
         ORDER BY c.priority_tier ASC, c.updated_at ASC
         LIMIT 1
        ''',
        [pendingState, retryScheduledState, now],
      );
      // Guard like the species claim: only claim a taxonomy row if at least
      // one of its species still has a deck-membership row, so an orphaned
      // taxon (every referencing deck deleted) never burns an iNat request.
      final taxonomyRows = await txn.rawQuery(
        '''
        SELECT t.work_key AS work_key,
               t.runtime_entity_key AS runtime_entity_key
          FROM ${EnrichmentWorkTables.taxonomyWork} t
         WHERE t.common_names_state IN (?, ?)
           AND (t.next_attempt_at IS NULL OR t.next_attempt_at <= ?)
           AND EXISTS (
             SELECT 1 FROM ${EnrichmentWorkTables.taxonomyWorkSpecies} ts
             JOIN ${EnrichmentWorkTables.deckMembership} m ON m.species_id = ts.species_id
              WHERE ts.work_key = t.work_key
           )
         ORDER BY t.updated_at ASC
         LIMIT 1
        ''',
        [pendingState, retryScheduledState, now],
      );
      final unresolvedRows = await txn.query(
        EnrichmentWorkTables.unresolvedNames,
        where:
            'state IN (?, ?) AND (next_attempt_at IS NULL OR next_attempt_at <= ?)',
        whereArgs: [
          pendingState,
          retryScheduledState,
          now,
        ],
        orderBy: 'updated_at ASC',
        limit: 1,
      );

      final candidates = <(int priorityTier, String source)>[
        if (speciesRows.isNotEmpty)
          (speciesRows.single['priority_tier'] as int, 'species'),
        if (taxonomyRows.isNotEmpty) (30, 'taxonomy'),
        if (unresolvedRows.isNotEmpty) (50, 'unresolvedName'),
      ];
      if (candidates.isEmpty) return null;
      candidates.sort((a, b) => a.$1.compareTo(b.$1));

      switch (candidates.first.$2) {
        case 'species':
          final row = speciesRows.single;
          final speciesId = row['species_id'] as String;
          final capability = row['capability'] as String;
          await txn.update(
            EnrichmentWorkTables.capabilityState,
            {'state': runningState, 'updated_at': now},
            where: 'species_id = ? AND capability = ?',
            whereArgs: [speciesId, capability],
          );
          return INatWorkItem.species(
            _workItemKindFor(EnrichmentCapability.fromWire(capability)),
            speciesId,
            priorityTier: row['priority_tier'] as int,
          );
        case 'taxonomy':
          final row = taxonomyRows.single;
          final workKey = row['work_key'] as String;
          await txn.update(
            EnrichmentWorkTables.taxonomyWork,
            {'common_names_state': runningState, 'updated_at': now},
            where: 'work_key = ?',
            whereArgs: [workKey],
          );
          final taxonomySpeciesRows = await txn.query(
            EnrichmentWorkTables.taxonomyWorkSpecies,
            columns: const ['species_id'],
            where: 'work_key = ?',
            whereArgs: [workKey],
          );
          return INatWorkItem.taxonomy(
            workKey,
            row['runtime_entity_key'] as String,
            {for (final r in taxonomySpeciesRows) r['species_id'] as String},
          );
        case 'unresolvedName':
          final row = unresolvedRows.single;
          final deckId = row['deck_id'] as String;
          final name = row['name'] as String;
          await txn.update(
            EnrichmentWorkTables.unresolvedNames,
            {'state': runningState, 'updated_at': now},
            where: 'deck_id = ? AND name = ?',
            whereArgs: [deckId, name],
          );
          return INatWorkItem.nameResolution(
            deckId,
            name,
            wantsInatPhotos: (row['wants_inat_photos'] as int? ?? 1) == 1,
            wantsCommonNames: (row['wants_common_names'] as int? ?? 1) == 1,
          );
        default:
          return null;
      }
    });
  }

  /// The iNaturalist work item a claimed capability row turns into.
  /// [EnrichmentCapability.base] never reaches this path — it is drained by
  /// `BaseWorker` against the bundled catalog, not by the iNat consumer.
  static INatWorkItemKind _workItemKindFor(EnrichmentCapability capability) {
    switch (capability) {
      case EnrichmentCapability.inatPrimary:
        return INatWorkItemKind.inatPrimary;
      case EnrichmentCapability.speciesCommonNames:
        return INatWorkItemKind.speciesCommonNames;
      case EnrichmentCapability.inatBackfill:
        return INatWorkItemKind.inatBackfill;
      case EnrichmentCapability.base:
        throw ArgumentError.value(
          capability,
          'capability',
          'base is drained by BaseWorker, never claimed as an iNat work item',
        );
    }
  }
}
