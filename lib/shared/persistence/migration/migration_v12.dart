part of '../user_db_schema.dart';

/// Migration v11 → v12: additive groundwork for the producer-consumer
/// enrichment rewrite (species/taxonomy work is moving from one job with
/// six sequential stages per deck to two independent workers draining a
/// shared per-species priority queue — see the enrichment-optimization
/// plan). Adds the per-capability species queue table
/// (enrichment_species_capability_state), a species/deck junction table
/// (enrichment_species_deck_membership), a retryable unresolved-name table
/// (enrichment_unresolved_names), retry-bookkeeping columns on
/// enrichment_taxonomy_work, and OR'd-across-decks consent flags
/// (wants_inat_photos/wants_common_names) on enrichment_species_work.
///
/// Migration v11 → v12: replaces the old job-based enrichment system with the
/// producer-consumer queue. Done as a single version bump composed of four
/// ordered steps (each independently testable). Run in sequence, a v11
/// database reaches the final schema directly — there are no intermediate
/// shipped versions between the last release (v11) and this one.
Future<void> migrateUserDbToV12(Database db) async {
  _log.debug(
    'Migrating user DB v11 → v12: enrichment producer-consumer rewrite',
  );
  await v12SeedQueueTables(db);
  await v12CutoverSpeciesWorkAndJobs(db);
  await v12DropTaxonomyOwnerDeckId(db);
  await v12NormalizeTaxonomySpecies(db);
}

/// Step 1/4 — seed the new queue tables (species-capability state,
/// deck-membership, unresolved names) and backfill them from the still-intact
/// enrichment_jobs/enrichment_species_work data. Additive only: nothing is
/// renamed or dropped here — the old per-stage columns
/// (base_state/inat_primary_state/species_common_names_state/
/// inat_backfill_state/deck_ids_json) are still readable, and the later steps
/// do the cutover.
Future<void> v12SeedQueueTables(Database db) async {
  _log.debug(
    'v11 → v12 (1/4): seed species-capability/deck-membership/'
    'unresolved-names queue tables (additive)',
  );

  // Ensure every table this migration reads from/writes to exists first.
  // Idempotent (CREATE TABLE IF NOT EXISTS) — a no-op for a normal v11
  // upgrade where these tables already hold real data, but makes this safe
  // even for a very old install jumping straight past whatever version
  // first introduced the enrichment feature: in that case the tables are
  // created here empty, so the backfill loops below simply find nothing to
  // migrate.
  await _executeSqlAsset(db, _createEnrichmentJobsSqlAsset);
  await _executeSqlAsset(db, _createEnrichmentJobStagesSqlAsset);
  await _executeSqlAsset(db, _createEnrichmentSpeciesWorkSqlAsset);
  await _executeSqlAsset(db, _createEnrichmentTaxonomyWorkSqlAsset);

  await _executeSqlAsset(db, _createEnrichmentSpeciesCapabilityStateSqlAsset);
  await _executeSqlAsset(db, _createEnrichmentSpeciesDeckMembershipSqlAsset);
  await _executeSqlAsset(db, _createEnrichmentUnresolvedNamesSqlAsset);

  await _ensureColumnExists(
    db,
    'enrichment_species_work',
    'wants_inat_photos',
    'INTEGER NOT NULL DEFAULT 0',
  );
  await _ensureColumnExists(
    db,
    'enrichment_species_work',
    'wants_common_names',
    'INTEGER NOT NULL DEFAULT 0',
  );
  await _ensureColumnExists(
    db,
    'enrichment_taxonomy_work',
    'attempt_count',
    'INTEGER NOT NULL DEFAULT 0',
  );
  await _ensureColumnExists(
    db,
    'enrichment_taxonomy_work',
    'next_attempt_at',
    'INTEGER',
  );
  await _ensureColumnExists(
    db,
    'enrichment_taxonomy_work',
    'last_error',
    'TEXT',
  );
  await _ensureColumnExists(
    db,
    'enrichment_taxonomy_work',
    'last_failure_kind',
    'TEXT',
  );
  await _ensureColumnExists(
    db,
    'enrichment_unresolved_names',
    'wants_inat_photos',
    'INTEGER NOT NULL DEFAULT 1',
  );
  await _ensureColumnExists(
    db,
    'enrichment_unresolved_names',
    'wants_common_names',
    'INTEGER NOT NULL DEFAULT 1',
  );

  // Per-deck consent (includeINatPhotos/includeCommonNames) and unresolved
  // names, read out of enrichment_jobs' still-unchanged payload shape.
  final jobRows = await db.query(
    'enrichment_jobs',
    columns: ['deck_id', 'payload_json'],
  );
  final includeInatPhotosByDeck = <String, bool>{};
  final includeCommonNamesByDeck = <String, bool>{};
  final unresolvedNamesByDeck = <String, List<String>>{};
  for (final row in jobRows) {
    final deckId = row['deck_id'] as String;
    final payload =
        jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
    includeInatPhotosByDeck[deckId] =
        payload['includeINatPhotos'] as bool? ?? true;
    includeCommonNamesByDeck[deckId] =
        payload['includeCommonNames'] as bool? ?? true;
    final stillUnresolved =
        (payload['stillUnresolvedNames'] as List<dynamic>? ?? const [])
            .cast<String>();
    final unresolved =
        (payload['unresolvedSpeciesNames'] as List<dynamic>? ?? const [])
            .cast<String>();
    unresolvedNamesByDeck[deckId] = stillUnresolved.isNotEmpty
        ? stillUnresolved
        : unresolved;
  }

  // Backfill per-species membership, OR'd consent, and per-capability
  // queue rows from the still-intact enrichment_species_work columns.
  // This backfill can touch one membership row plus up to four capability
  // rows per species. Issued as individual `await db.insert`/`db.update`
  // calls, each is a separate platform-channel round-trip, so a large
  // library could take long enough to overrun the bounded `openDatabase`
  // timeout while still mid-onUpgrade. Collect every write into a single
  // batch and commit once (one round-trip, executed natively).
  final speciesWorkRows = await db.query('enrichment_species_work');
  final batch = db.batch();
  for (final row in speciesWorkRows) {
    final speciesId = row['species_id'] as String;
    final deckIds = _decodeStringListForMigration(row['deck_ids_json']);
    final updatedAt =
        row['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch;

    for (final deckId in deckIds) {
      batch.insert(
        'enrichment_species_deck_membership',
        {'species_id': speciesId, 'deck_id': deckId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    final wantsPhotos = deckIds.any(
      (deckId) => includeInatPhotosByDeck[deckId] ?? true,
    );
    final wantsNames = deckIds.any(
      (deckId) => includeCommonNamesByDeck[deckId] ?? true,
    );
    batch.update(
      'enrichment_species_work',
      {
        'wants_inat_photos': wantsPhotos ? 1 : 0,
        'wants_common_names': wantsNames ? 1 : 0,
      },
      where: 'species_id = ?',
      whereArgs: [speciesId],
    );

    void insertCapability(
      String capability,
      Object? oldState,
      int priorityTier,
    ) {
      final state = oldState == 'succeeded' ? 'done' : 'pending';
      batch.insert(
        'enrichment_species_capability_state',
        {
          'species_id': speciesId,
          'capability': capability,
          'state': state,
          'priority_tier': priorityTier,
          'attempt_count': 0,
          'updated_at': updatedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    insertCapability('base', row['base_state'], 0);
    insertCapability('inatPrimary', row['inat_primary_state'], 10);
    insertCapability(
      'speciesCommonNames',
      row['species_common_names_state'],
      20,
    );
    insertCapability('inatBackfill', row['inat_backfill_state'], 40);
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  for (final entry in unresolvedNamesByDeck.entries) {
    final deckId = entry.key;
    for (final name in entry.value) {
      batch.insert('enrichment_unresolved_names', {
        'deck_id': deckId,
        'name': name,
        'state': 'pending',
        'wants_inat_photos': (includeInatPhotosByDeck[deckId] ?? true) ? 1 : 0,
        'wants_common_names': (includeCommonNamesByDeck[deckId] ?? true)
            ? 1
            : 0,
        'attempt_count': 0,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  await batch.commit(noResult: true);
}

/// Step 2/4 — the enrichment cutover. `BaseWorker`/`INatWorker`
/// now read/write only `enrichment_species_capability_state` and
/// `enrichment_species_deck_membership` — species/taxonomy enrichment no
/// longer goes through a job at all, so this drops what only the retired
/// `EnrichmentJobExecutor` used: the four old per-stage columns and
/// `deck_ids_json` on `enrichment_species_work`, every `enrichment_job_stages`
/// row except `cover`, and shrinks `enrichment_jobs.payload_json` down to
/// just `{coverImageUrl}` — `cover` is the only stage a job ever runs now.
///
/// Also discards any `enrichment_jobs` row left by the old executor in a
/// non-terminal status (`queued`/`runningForeground`/`runningBackground`/
/// `pausedBySystem`/`retryScheduled`/`failedTemporary` — the
/// `EnrichmentJobStatus` enum's non-terminal values). After the cutover,
/// `EnrichmentJobRepository.claimNextJob` only reclaims a job that still
/// has a `pending`/`running` stage row, and every `enrichment_job_stages`
/// row but `cover` gets pruned regardless (see below) — so a job
/// interrupted mid-flight in an old stage *after* `cover` already ran (the
/// common case: the old stage order was `nameResolution → cover → base →
/// inatPrimary → names → inatBackfill`) would otherwise never be
/// reclaimable again, freezing its
/// status forever and permanently blocking `computeDeckEnrichmentState`'s
/// `coverTerminal` check (which requires `completed`/`failedPermanent`/no
/// job at all) — the deck would show as still loading even once every
/// species/taxonomy capability genuinely finishes. Deleting the row
/// entirely (rather than trying to reset it to a fresh, claimable state)
/// sidesteps needing a `coverImageUrl` to reschedule with — that is
/// resolved by service-layer/catalog logic this migration has no access
/// to. `coverJob == null` already reads as trivially cover-terminal, and
/// local data (cached photos, common names, capability state) is
/// untouched — the only visible effect is that a deck whose cover image
/// genuinely hadn't been fetched yet stays without one until enrichment is
/// re-triggered for it (manually, or the next time it naturally would be).
Future<void> v12CutoverSpeciesWorkAndJobs(Database db) async {
  _log.debug(
    'v11 → v12 (2/4): enrichment cutover to producer-consumer workers '
    '(base/inatPrimary/speciesCommonNames/inatBackfill no longer go through '
    'a job)',
  );

  // Only rename-recreate-copy if the table is still in the old, pre-cutover
  // shape — step 1 leaves it additive, but a fresh table created by
  // _createEnrichmentJobTables is already shrunk, with nothing to copy.
  if (await _tableHasColumn(db, 'enrichment_species_work', 'base_state')) {
    await db.execute(
      'ALTER TABLE enrichment_species_work RENAME TO enrichment_species_work_old',
    );
    await _executeSqlAsset(db, _createEnrichmentSpeciesWorkSqlAsset);
    await db.execute('''
      INSERT INTO enrichment_species_work (
        species_id,
        owner_deck_id,
        deck_count,
        wants_inat_photos,
        wants_common_names,
        updated_at
      )
      SELECT
        species_id,
        owner_deck_id,
        deck_count,
        wants_inat_photos,
        wants_common_names,
        updated_at
      FROM enrichment_species_work_old
      ''');
    await db.execute('DROP TABLE enrichment_species_work_old');
  }

  if (await _tableExists(db, 'enrichment_jobs')) {
    final staleJobRows = await db.query(
      'enrichment_jobs',
      columns: ['deck_id'],
      where: 'status NOT IN (?, ?, ?)',
      whereArgs: ['completed', 'cancelled', 'failedPermanent'],
    );
    if (staleJobRows.isNotEmpty) {
      final staleDeckIds = [
        for (final row in staleJobRows) row['deck_id'] as String,
      ];
      final placeholders = List.filled(staleDeckIds.length, '?').join(',');
      await db.delete(
        'enrichment_job_stages',
        where: 'deck_id IN ($placeholders)',
        whereArgs: staleDeckIds,
      );
      await db.delete(
        'enrichment_jobs',
        where: 'deck_id IN ($placeholders)',
        whereArgs: staleDeckIds,
      );
      _log.debug(
        'Discarded ${staleDeckIds.length} stale non-terminal enrichment '
        'job(s) left by the old executor',
      );
    }
  }

  if (await _tableExists(db, 'enrichment_job_stages')) {
    await db.delete(
      'enrichment_job_stages',
      where: 'stage != ?',
      whereArgs: ['cover'],
    );
  }

  if (await _tableExists(db, 'enrichment_jobs')) {
    final jobRows = await db.query(
      'enrichment_jobs',
      columns: ['deck_id', 'payload_json'],
    );
    final batch = db.batch();
    for (final row in jobRows) {
      final deckId = row['deck_id'] as String;
      final payloadJson = row['payload_json'] as String?;
      String? coverImageUrl;
      if (payloadJson != null) {
        final decoded = jsonDecode(payloadJson);
        if (decoded is Map<String, dynamic>) {
          coverImageUrl = decoded['coverImageUrl'] as String?;
        }
      }
      batch.update(
        'enrichment_jobs',
        {
          'payload_json': jsonEncode({'coverImageUrl': coverImageUrl}),
        },
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
    }
    await batch.commit(noResult: true);
  }
}

/// Step 3/4 — drops `owner_deck_id` from `enrichment_taxonomy_work`. The
/// shared `INatWorker` queue claims a taxonomy row purely by
/// `common_names_state`/`work_key` — it never reads `owner_deck_id` — so the
/// column had no effect on processing and only invited a `releaseDeck` bug
/// where releasing the "owning" deck deleted a taxonomy item outright even
/// though other decks still depended on it. `deck_ids_json`/`species_ids_json`
/// survive this step; step 4 replaces them.
Future<void> v12DropTaxonomyOwnerDeckId(Database db) async {
  _log.debug(
    'v11 → v12 (3/4): drop unused owner_deck_id from enrichment_taxonomy_work',
  );

  // Only rename-recreate-copy if the table still has the column — a freshly
  // created table is already in the shrunk shape, with nothing to copy.
  if (await _tableHasColumn(db, 'enrichment_taxonomy_work', 'owner_deck_id')) {
    await db.execute(
      'ALTER TABLE enrichment_taxonomy_work RENAME TO enrichment_taxonomy_work_old',
    );
    // Recreate the pre-normalization shape inline rather than from the
    // current asset: the asset is the final slim shape (no deck_ids_json/
    // species_ids_json/rank/scientific_name), which the INSERT SELECT below
    // still needs. Freezing the DDL here keeps this step correct as the
    // asset evolves; step 4 does the actual column drop.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS enrichment_taxonomy_work (
        work_key                     TEXT PRIMARY KEY,
        runtime_entity_key           TEXT NOT NULL UNIQUE,
        deck_ids_json                TEXT NOT NULL,
        species_ids_json             TEXT NOT NULL,
        rank                         TEXT NOT NULL,
        scientific_name              TEXT NOT NULL,
        common_names_state           TEXT NOT NULL DEFAULT 'pending',
        attempt_count                INTEGER NOT NULL DEFAULT 0,
        next_attempt_at              INTEGER,
        last_error                   TEXT,
        last_failure_kind            TEXT,
        updated_at                   INTEGER NOT NULL
      )
      ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_enrichment_taxonomy_work_runtime_entity
        ON enrichment_taxonomy_work(runtime_entity_key)
      ''');
    await db.execute('''
      INSERT INTO enrichment_taxonomy_work (
        work_key,
        runtime_entity_key,
        deck_ids_json,
        species_ids_json,
        rank,
        scientific_name,
        common_names_state,
        attempt_count,
        next_attempt_at,
        last_error,
        last_failure_kind,
        updated_at
      )
      SELECT
        work_key,
        runtime_entity_key,
        deck_ids_json,
        species_ids_json,
        rank,
        scientific_name,
        common_names_state,
        attempt_count,
        next_attempt_at,
        last_error,
        last_failure_kind,
        updated_at
      FROM enrichment_taxonomy_work_old
      ''');
    await db.execute('DROP TABLE enrichment_taxonomy_work_old');
  }
}

/// Step 4/4 — normalizes taxonomy work's species membership into
/// `enrichment_taxonomy_work_species` and drops the now-redundant columns
/// from `enrichment_taxonomy_work`: `deck_ids_json` (deck scoping is derived
/// from the species junction joined against
/// `enrichment_species_deck_membership`), `species_ids_json` (moved to the
/// junction), and `rank`/`scientific_name` (write-only, already encoded in
/// `runtime_entity_key`).
Future<void> v12NormalizeTaxonomySpecies(Database db) async {
  _log.debug(
    'v11 → v12 (4/4): taxonomy species junction + drop '
    'deck_ids_json/species_ids_json/rank/scientific_name',
  );

  await _executeSqlAsset(db, _createEnrichmentTaxonomyWorkSpeciesSqlAsset);

  // A very old install that created enrichment_taxonomy_work fresh in the
  // already-slim shape has nothing to backfill or drop.
  if (!await _tableHasColumn(
    db,
    'enrichment_taxonomy_work',
    'species_ids_json',
  )) {
    return;
  }

  // Backfill the junction from species_ids_json. Batched: a large library
  // could otherwise issue thousands of awaited inserts and overrun the
  // bounded openDatabase timeout mid-onUpgrade.
  final rows = await db.query(
    'enrichment_taxonomy_work',
    columns: ['work_key', 'species_ids_json'],
  );
  final batch = db.batch();
  for (final row in rows) {
    final workKey = row['work_key'] as String;
    for (final speciesId in _decodeStringListForMigration(
      row['species_ids_json'],
    )) {
      batch.insert(
        'enrichment_taxonomy_work_species',
        {'work_key': workKey, 'species_id': speciesId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }
  await batch.commit(noResult: true);

  // Drop deck_ids_json/species_ids_json/rank/scientific_name via
  // rename-recreate-copy (the final shape, frozen inline). DROP INDEX first:
  // RENAME carries the index (keeping its name) onto the _old table, so
  // recreating it by the same name would otherwise no-op and leave the new
  // table unindexed.
  await db.execute(
    'ALTER TABLE enrichment_taxonomy_work RENAME TO enrichment_taxonomy_work_old',
  );
  await db.execute(
    'DROP INDEX IF EXISTS idx_enrichment_taxonomy_work_runtime_entity',
  );
  await db.execute('''
    CREATE TABLE IF NOT EXISTS enrichment_taxonomy_work (
      work_key                     TEXT PRIMARY KEY,
      runtime_entity_key           TEXT NOT NULL UNIQUE,
      common_names_state           TEXT NOT NULL DEFAULT 'pending',
      attempt_count                INTEGER NOT NULL DEFAULT 0,
      next_attempt_at              INTEGER,
      last_error                   TEXT,
      last_failure_kind            TEXT,
      updated_at                   INTEGER NOT NULL
    )
    ''');
  await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_enrichment_taxonomy_work_runtime_entity
      ON enrichment_taxonomy_work(runtime_entity_key)
    ''');
  await db.execute('''
    INSERT INTO enrichment_taxonomy_work (
      work_key,
      runtime_entity_key,
      common_names_state,
      attempt_count,
      next_attempt_at,
      last_error,
      last_failure_kind,
      updated_at
    )
    SELECT
      work_key,
      runtime_entity_key,
      common_names_state,
      attempt_count,
      next_attempt_at,
      last_error,
      last_failure_kind,
      updated_at
    FROM enrichment_taxonomy_work_old
    ''');
  await db.execute('DROP TABLE enrichment_taxonomy_work_old');
}
