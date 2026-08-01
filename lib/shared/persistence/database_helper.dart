import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final _log = Logger.forType(DatabaseHelper);
  static const _createDecksSqlAsset =
      'assets/sql/user_db/tables/create_decks.sql';
  static const _createFlashcardStatsSqlAsset =
      'assets/sql/user_db/tables/create_flashcard_stats.sql';
  static const _createINatPhotoCacheSqlAsset =
      'assets/sql/user_db/tables/create_inat_photo_cache.sql';
  static const _createRuntimeCommonNamesSqlAsset =
      'assets/sql/user_db/tables/create_runtime_common_names.sql';
  static const _createRuntimeCommonNameSearchDocumentsSqlAsset =
      'assets/sql/user_db/tables/create_runtime_common_name_search_documents.sql';
  static const _createRuntimeCommonNameSearchFtsSqlAsset =
      'assets/sql/user_db/fts/create_runtime_common_name_search_fts.sql';
  static const _createExternalIdentifierCacheSqlAsset =
      'assets/sql/user_db/tables/create_external_identifier_cache.sql';
  static const _createEnrichmentJobsSqlAsset =
      'assets/sql/user_db/tables/create_enrichment_jobs.sql';
  static const _createEnrichmentJobStagesSqlAsset =
      'assets/sql/user_db/tables/create_enrichment_job_stages.sql';
  static const _createEnrichmentSpeciesWorkSqlAsset =
      'assets/sql/user_db/tables/create_enrichment_species_work.sql';
  static const _createEnrichmentTaxonomyWorkSqlAsset =
      'assets/sql/user_db/tables/create_enrichment_taxonomy_work.sql';
  static const _createEnrichmentTaxonomyWorkSpeciesSqlAsset =
      'assets/sql/user_db/tables/create_enrichment_taxonomy_work_species.sql';
  static const _createEnrichmentSpeciesCapabilityStateSqlAsset =
      'assets/sql/user_db/tables/create_enrichment_species_capability_state.sql';
  static const _createEnrichmentSpeciesDeckMembershipSqlAsset =
      'assets/sql/user_db/tables/create_enrichment_species_deck_membership.sql';
  static const _createEnrichmentUnresolvedNamesSqlAsset =
      'assets/sql/user_db/tables/create_enrichment_unresolved_names.sql';
  static const _createLocalDiagnosticsEventsSqlAsset =
      'assets/sql/user_db/tables/create_local_diagnostics_events.sql';
  static const _createLocalDiagnosticsNetworkFailuresSqlAsset =
      'assets/sql/user_db/tables/create_local_diagnostics_network_failures.sql';
  static const _createDeckConfigSqlAsset =
      'assets/sql/user_db/tables/create_deck_config.sql';
  // Only used by the historical v3→v4/v5→v6/v8→v9 migration steps below —
  // fresh installs and upgrades past v11 no longer create this table (see
  // _migrateUserSchemaV10ToV11).
  static const _createDailyCountsSqlAsset =
      'assets/sql/user_db/tables/create_daily_counts.sql';

  static Database? _referenceDb;
  static Database? _userDb;
  static Future<Database>? _referenceInitialization;
  static Future<Database>? _userInitialization;

  /// Bounds the native `openDatabase()` call so a wedged native handle (the
  /// same process-wide-singleton-keyed-by-path hazard `main.dart`'s
  /// `AppLifecycleState.detached` handler works around on close — see
  /// `DatabaseHelper.close()`) surfaces as a catchable error instead of
  /// hanging forever with no way to recover short of force-killing the app.
  /// `referenceDb`/`userDb` already reset their cached initialization future
  /// on any error, so a timeout here makes a subsequent access (a bootstrap
  /// retry, or a later repository call) a genuine fresh attempt rather than
  /// re-awaiting the same dead future indefinitely.
  static const _openTimeout = Duration(seconds: 8);

  @visibleForTesting
  static const int userDbVersion = 12;

  // ---------------------------------------------------------------------------
  // Reference DB (read-only)
  // ---------------------------------------------------------------------------

  static Future<Database> get referenceDb async {
    if (_referenceDb != null) return _referenceDb!;
    _referenceInitialization ??= _openReferenceDb().catchError((e) {
      _referenceInitialization = null;
      throw e;
    });
    _referenceDb = await _referenceInitialization!;
    return _referenceDb!;
  }

  static Future<void> prepareReferenceDb() async {
    await referenceDb;
  }

  /// Opens the reference database from wherever
  /// [ReferenceDatabaseProvisioner] has already placed it (downloaded and
  /// installed by the bootstrap flow before this is ever called — see
  /// `bootstrap_app.dart`). This class no longer provisions the file itself.
  static Future<Database> _openReferenceDb() async {
    final dbPath = await ReferenceDatabaseProvisioner.resolveLocalPath();
    final stopwatch = Stopwatch()..start();

    _log.debug('Opening reference database at: $dbPath');
    try {
      final db = await openDatabase(
        dbPath,
        readOnly: true,
      ).timeout(_openTimeout);
      _log.debug(
        'Reference database opened successfully in ${stopwatch.elapsedMilliseconds}ms.',
      );
      return db;
    } finally {
      stopwatch.stop();
    }
  }

  // ---------------------------------------------------------------------------
  // User DB (read-write)
  // ---------------------------------------------------------------------------

  static Future<Database> get userDb async {
    if (_userDb != null) return _userDb!;
    _userInitialization ??= _openUserDb().catchError((e) {
      _userInitialization = null;
      throw e;
    });
    _userDb = await _userInitialization!;
    return _userDb!;
  }

  static Future<Database> _openUserDb() async {
    final dir = await getApplicationSupportDirectory();
    final dbPath = join(dir.path, 'discere_user.db');
    final stopwatch = Stopwatch()..start();

    _log.debug('Opening user database at: $dbPath');
    try {
      final db = await openDatabase(
        dbPath,
        version: userDbVersion,
        onCreate: _createUserSchema,
        onUpgrade: _upgradeUserSchema,
      ).timeout(_openTimeout);
      _log.debug(
        'User database opened successfully with version: ${await db.getVersion()} '
        'in ${stopwatch.elapsedMilliseconds}ms',
      );
      return db;
    } finally {
      stopwatch.stop();
    }
  }

  static Future<void> _createUserSchema(Database db, int version) async {
    _log.debug('User DB schema create start (version=$version)');
    await _createCurrentUserSchema(db);
    _log.debug('User DB schema create done');
  }

  @visibleForTesting
  static Future<void> migrateUserSchemaV5ToV6ForTesting(Database db) =>
      _migrateUserSchemaV5ToV6(db);

  @visibleForTesting
  static Future<void> migrateUserSchemaV6ToV7ForTesting(Database db) =>
      _migrateUserSchemaV6ToV7(db);

  @visibleForTesting
  static Future<void> migrateUserSchemaV7ToV8ForTesting(Database db) =>
      _migrateUserSchemaV7ToV8(db);

  @visibleForTesting
  static Future<void> migrateUserSchemaV8ToV9ForTesting(Database db) =>
      _migrateUserSchemaV8ToV9(db);

  @visibleForTesting
  static Future<void> migrateUserSchemaV9ToV10ForTesting(Database db) =>
      _migrateUserSchemaV9ToV10(db);

  @visibleForTesting
  static Future<void> migrateUserSchemaV10ToV11ForTesting(Database db) =>
      _migrateUserSchemaV10ToV11(db);

  @visibleForTesting
  static Future<void> migrateUserSchemaV11ToV12ForTesting(Database db) =>
      _migrateUserSchemaV11ToV12(db);

  // The v11 -> v12 migration is composed of four ordered steps, each exposed
  // for focused testing of its own transformation (see `_migrateUserSchemaV11ToV12`).
  @visibleForTesting
  static Future<void> migrateV11ToV12SeedQueueTablesForTesting(Database db) =>
      _v11ToV12SeedQueueTables(db);

  @visibleForTesting
  static Future<void> migrateV11ToV12CutoverForTesting(Database db) =>
      _v11ToV12CutoverSpeciesWorkAndJobs(db);

  @visibleForTesting
  static Future<void> migrateV11ToV12DropTaxonomyOwnerDeckIdForTesting(
    Database db,
  ) => _v11ToV12DropTaxonomyOwnerDeckId(db);

  @visibleForTesting
  static Future<void> migrateV11ToV12NormalizeTaxonomySpeciesForTesting(
    Database db,
  ) => _v11ToV12NormalizeTaxonomySpecies(db);

  static Future<void> _upgradeUserSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    _log.debug('User DB schema upgrade start ($oldVersion -> $newVersion)');

    if (oldVersion < 2) {
      await _migrateUserSchemaV1ToV2(db);
    }
    if (oldVersion < 3) {
      await _migrateUserSchemaV2ToV3(db);
    }
    if (oldVersion < 4) {
      await _migrateUserSchemaV3ToV4(db);
    }
    if (oldVersion < 5) {
      // Drop and recreate flashcard_stats to remove legacy SM-2 columns
      // (interval, repetition, ease_factor). Only applies to dev installs —
      // this clears all review history.
      await db.execute('DROP TABLE IF EXISTS flashcard_stats');
    }
    if (oldVersion < 6) {
      await _migrateUserSchemaV5ToV6(db);
    }
    if (oldVersion < 7) {
      await _migrateUserSchemaV6ToV7(db);
    }
    if (oldVersion < 8) {
      await _migrateUserSchemaV7ToV8(db);
    }
    if (oldVersion < 9) {
      await _migrateUserSchemaV8ToV9(db);
    }
    if (oldVersion < 10) {
      await _migrateUserSchemaV9ToV10(db);
    }
    if (oldVersion < 11) {
      await _migrateUserSchemaV10ToV11(db);
    }
    if (oldVersion < 12) {
      await _migrateUserSchemaV11ToV12(db);
    }

    // Ensure all tables exist (CREATE TABLE IF NOT EXISTS is idempotent)
    await _createCurrentUserSchema(db);
    _log.debug('User DB schema upgrade done');
  }

  /// Migration v1 → v2: Add card_state and step_index columns for learning steps.
  /// Existing reviewed cards are set to CardState.review (2).
  static Future<void> _migrateUserSchemaV1ToV2(Database db) async {
    _log.debug('Migrating user DB v1 → v2: adding card_state, step_index');
    await db.execute(
      'ALTER TABLE flashcard_stats ADD COLUMN card_state INTEGER DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE flashcard_stats ADD COLUMN step_index INTEGER DEFAULT 0',
    );
    // Cards that have been reviewed (have a lastReviewDate) are in Review state
    await db.execute(
      'UPDATE flashcard_stats SET card_state = 2 '
      'WHERE last_review_date IS NOT NULL',
    );
  }

  /// Migration v2 → v3: Add deck_config table for per-deck SRS settings.
  static Future<void> _migrateUserSchemaV2ToV3(Database db) async {
    _log.debug('Migrating user DB v2 → v3: adding deck_config table');
    await _executeSqlAsset(db, _createDeckConfigSqlAsset);
  }

  /// Migration v3 → v4: Add daily_counts table and new_cards_per_day /
  /// max_reviews_per_day columns to deck_config.
  static Future<void> _migrateUserSchemaV3ToV4(Database db) async {
    _log.debug(
      'Migrating user DB v3 → v4: adding daily_counts table and daily-limit columns',
    );
    await _executeSqlAsset(db, _createDailyCountsSqlAsset);
    await db.execute(
      'ALTER TABLE deck_config ADD COLUMN new_cards_per_day INTEGER DEFAULT 20',
    );
    await db.execute(
      'ALTER TABLE deck_config ADD COLUMN max_reviews_per_day INTEGER DEFAULT 200',
    );
  }

  /// Migration v5 → v6: Add learning_mode to deck_config, flashcard_stats and
  /// daily_counts. Existing progress is preserved as species-mode progress.
  static Future<void> _migrateUserSchemaV5ToV6(Database db) async {
    _log.debug('Migrating user DB v5 → v6: adding per-mode learning stats');

    if (!await _tableHasColumn(db, 'deck_config', 'learning_mode')) {
      await db.execute(
        "ALTER TABLE deck_config ADD COLUMN learning_mode TEXT NOT NULL DEFAULT 'species'",
      );
    }

    if (await _tableExists(db, 'flashcard_stats')) {
      await db.execute(
        'ALTER TABLE flashcard_stats RENAME TO flashcard_stats_old',
      );
      await _executeSqlAsset(db, _createFlashcardStatsSqlAsset);
      await db.execute('''
        INSERT INTO flashcard_stats (
          species_id,
          deck_id,
          learning_mode,
          next_review_date,
          stability,
          difficulty,
          last_review_date,
          card_state,
          step_index
        )
        SELECT
          species_id,
          deck_id,
          'species',
          next_review_date,
          stability,
          difficulty,
          last_review_date,
          card_state,
          step_index
        FROM flashcard_stats_old
        ''');
      await db.execute('DROP TABLE flashcard_stats_old');
    }

    if (await _tableExists(db, 'daily_counts')) {
      await db.execute('ALTER TABLE daily_counts RENAME TO daily_counts_old');
      await _executeSqlAsset(db, _createDailyCountsSqlAsset);
      await db.execute('''
        INSERT INTO daily_counts (
          deck_id,
          date,
          learning_mode,
          new_count,
          review_count
        )
        SELECT deck_id, date, 'species', new_count, review_count
        FROM daily_counts_old
        ''');
      await db.execute('DROP TABLE daily_counts_old');
    }
  }

  /// Migration v6 → v7: Add review_mode to deck_config (flip vs. multiple
  /// choice review). Existing decks keep the flip behavior.
  static Future<void> _migrateUserSchemaV6ToV7(Database db) async {
    _log.debug('Migrating user DB v6 → v7: adding review_mode to deck_config');
    await _ensureColumnExists(
      db,
      'deck_config',
      'review_mode',
      "TEXT NOT NULL DEFAULT 'flip'",
    );
  }

  /// Migration v7 → v8: Add sortOrder to decks so the deck list has a stable,
  /// user-controllable order. Editing a deck (which upserts via
  /// `INSERT OR REPLACE`) previously reshuffled the rowid-based scan order;
  /// existing decks are backfilled by their current rowid order so the
  /// visible order does not jump on upgrade.
  static Future<void> _migrateUserSchemaV7ToV8(Database db) async {
    _log.debug('Migrating user DB v7 → v8: adding sortOrder to decks');
    await _ensureColumnExists(
      db,
      'decks',
      'sortOrder',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('''
      UPDATE decks SET sortOrder = (
        SELECT COUNT(*) FROM decks AS earlier
        WHERE earlier.rowid <= decks.rowid
      )
      ''');
  }

  /// Migration v8 → v9: Add name_type to deck_config, flashcard_stats and
  /// daily_counts, so common-name and scientific-name progress are tracked
  /// independently. Existing progress is preserved as commonName-mode progress.
  static Future<void> _migrateUserSchemaV8ToV9(Database db) async {
    _log.debug(
      'Migrating user DB v8 → v9: adding per-name-type learning stats',
    );

    await _ensureColumnExists(
      db,
      'deck_config',
      'name_type',
      "TEXT NOT NULL DEFAULT 'commonName'",
    );

    if (await _tableExists(db, 'flashcard_stats')) {
      await db.execute(
        'ALTER TABLE flashcard_stats RENAME TO flashcard_stats_old',
      );
      await _executeSqlAsset(db, _createFlashcardStatsSqlAsset);
      await db.execute('''
        INSERT INTO flashcard_stats (
          species_id,
          deck_id,
          learning_mode,
          name_type,
          next_review_date,
          stability,
          difficulty,
          last_review_date,
          card_state,
          step_index
        )
        SELECT
          species_id,
          deck_id,
          learning_mode,
          'commonName',
          next_review_date,
          stability,
          difficulty,
          last_review_date,
          card_state,
          step_index
        FROM flashcard_stats_old
        ''');
      await db.execute('DROP TABLE flashcard_stats_old');
    }

    if (await _tableExists(db, 'daily_counts')) {
      await db.execute('ALTER TABLE daily_counts RENAME TO daily_counts_old');
      await _executeSqlAsset(db, _createDailyCountsSqlAsset);
      await db.execute('''
        INSERT INTO daily_counts (
          deck_id,
          date,
          learning_mode,
          name_type,
          new_count,
          review_count
        )
        SELECT deck_id, date, learning_mode, 'commonName', new_count, review_count
        FROM daily_counts_old
        ''');
      await db.execute('DROP TABLE daily_counts_old');
    }
  }

  /// Migration v9 → v10: Add sourceId and updatedAt to decks, populated for
  /// decks imported from the online catalog (discere-data). sourceId is a
  /// stable catalog identifier; updatedAt is the catalog entry's last-edited
  /// timestamp. Both are null for locally-created decks and for existing
  /// decks on upgrade.
  static Future<void> _migrateUserSchemaV9ToV10(Database db) async {
    _log.debug(
      'Migrating user DB v9 → v10: adding sourceId, updatedAt to decks',
    );
    await _ensureColumnExists(db, 'decks', 'sourceId', 'TEXT');
    await _ensureColumnExists(db, 'decks', 'updatedAt', 'INTEGER');
  }

  /// Migration v10 → v11: Remove the daily new-card/review limits
  /// (new_cards_per_day, max_reviews_per_day on deck_config; the whole
  /// daily_counts table). These were never surfaced in any settings UI, so a
  /// deck could silently hit its cap and leave the "activate more cards?"
  /// dialog looping with no feedback once the default budget was exhausted.
  static Future<void> _migrateUserSchemaV10ToV11(Database db) async {
    _log.debug(
      'Migrating user DB v10 → v11: removing daily new-card/review limits',
    );

    if (await _tableExists(db, 'deck_config')) {
      await db.execute('ALTER TABLE deck_config RENAME TO deck_config_old');
      await _executeSqlAsset(db, _createDeckConfigSqlAsset);
      await db.execute('''
        INSERT INTO deck_config (
          deck_id,
          desired_retention,
          maximum_interval,
          learning_steps,
          relearning_steps,
          learning_mode,
          name_type,
          review_mode
        )
        SELECT
          deck_id,
          desired_retention,
          maximum_interval,
          learning_steps,
          relearning_steps,
          learning_mode,
          name_type,
          review_mode
        FROM deck_config_old
        ''');
      await db.execute('DROP TABLE deck_config_old');
    }

    await db.execute('DROP TABLE IF EXISTS daily_counts');
  }

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
  static Future<void> _migrateUserSchemaV11ToV12(Database db) async {
    _log.debug(
      'Migrating user DB v11 → v12: enrichment producer-consumer rewrite',
    );
    await _v11ToV12SeedQueueTables(db);
    await _v11ToV12CutoverSpeciesWorkAndJobs(db);
    await _v11ToV12DropTaxonomyOwnerDeckId(db);
    await _v11ToV12NormalizeTaxonomySpecies(db);
  }

  /// Step 1/4 — seed the new queue tables (species-capability state,
  /// deck-membership, unresolved names) and backfill them from the still-intact
  /// enrichment_jobs/enrichment_species_work data. Additive only: nothing is
  /// renamed or dropped here — the old per-stage columns
  /// (base_state/inat_primary_state/species_common_names_state/
  /// inat_backfill_state/deck_ids_json) are still readable, and the later steps
  /// do the cutover.
  static Future<void> _v11ToV12SeedQueueTables(Database db) async {
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
        batch.insert(
          'enrichment_unresolved_names',
          {
            'deck_id': deckId,
            'name': name,
            'state': 'pending',
            'wants_inat_photos': (includeInatPhotosByDeck[deckId] ?? true)
                ? 1
                : 0,
            'wants_common_names': (includeCommonNamesByDeck[deckId] ?? true)
                ? 1
                : 0,
            'attempt_count': 0,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
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
  static Future<void> _v11ToV12CutoverSpeciesWorkAndJobs(Database db) async {
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
  static Future<void> _v11ToV12DropTaxonomyOwnerDeckId(Database db) async {
    _log.debug(
      'v11 → v12 (3/4): drop unused owner_deck_id from enrichment_taxonomy_work',
    );

    // Only rename-recreate-copy if the table still has the column — a freshly
    // created table is already in the shrunk shape, with nothing to copy.
    if (await _tableHasColumn(
      db,
      'enrichment_taxonomy_work',
      'owner_deck_id',
    )) {
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
  static Future<void> _v11ToV12NormalizeTaxonomySpecies(Database db) async {
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
        batch.insert('enrichment_taxonomy_work_species', {
          'work_key': workKey,
          'species_id': speciesId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
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

  static List<String> _decodeStringListForMigration(Object? rawValue) {
    if (rawValue is! String || rawValue.isEmpty) return <String>[];
    final decoded = jsonDecode(rawValue);
    if (decoded is! List) return <String>[];
    return decoded.whereType<String>().toList();
  }

  static Future<bool> _tableExists(Database db, String tableName) async {
    final result = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [tableName],
    );
    return result.isNotEmpty;
  }

  static Future<bool> _tableHasColumn(
    Database db,
    String tableName,
    String columnName,
  ) async {
    if (!await _tableExists(db, tableName)) return false;
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    return columns.any((column) => column['name'] == columnName);
  }

  static Future<void> _createCurrentUserSchema(Database db) async {
    await _executeSqlAsset(db, _createDecksSqlAsset);
    await _executeSqlAsset(db, _createFlashcardStatsSqlAsset);
    await _executeSqlAsset(db, _createDeckConfigSqlAsset);
    await _createINatCacheTable(db);
    await _createRuntimeCommonNamesTable(db);
    await _createRuntimeCommonNameSearchTables(db);
    await _createExternalIdentifierCacheTable(db);
    await _createEnrichmentJobTables(db);
    await _createLocalDiagnosticsTables(db);
  }

  static Future<void> _createINatCacheTable(Database db) async {
    await _executeSqlAsset(db, _createINatPhotoCacheSqlAsset);
  }

  static Future<void> _createRuntimeCommonNamesTable(Database db) async {
    await _executeSqlAsset(db, _createRuntimeCommonNamesSqlAsset);
  }

  static Future<void> _createRuntimeCommonNameSearchTables(Database db) async {
    await _executeSqlAsset(db, _createRuntimeCommonNameSearchDocumentsSqlAsset);
    await _createRuntimeCommonNameSearchFtsTable(db);
  }

  /// Creates the local full-text index for runtime common-name search documents.
  ///
  /// We intentionally use `fts4` for broad Android/SQLite compatibility. The
  /// previous optimistic `fts5` attempt produced a failing statement during the
  /// schema transaction on some runtimes.
  static Future<void> _createRuntimeCommonNameSearchFtsTable(
    Database db,
  ) async {
    await _executeSqlAsset(db, _createRuntimeCommonNameSearchFtsSqlAsset);
  }

  static Future<void> _createExternalIdentifierCacheTable(Database db) async {
    await _executeSqlAsset(db, _createExternalIdentifierCacheSqlAsset);
  }

  static Future<void> _createEnrichmentJobTables(Database db) async {
    await _executeSqlAsset(db, _createEnrichmentJobsSqlAsset);
    await _ensureColumnExists(
      db,
      'enrichment_jobs',
      'retry_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumnExists(
      db,
      'enrichment_jobs',
      'next_attempt_at',
      'INTEGER',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_enrichment_jobs_next_attempt '
      'ON enrichment_jobs(next_attempt_at)',
    );
    await _executeSqlAsset(db, _createEnrichmentJobStagesSqlAsset);
    await _executeSqlAsset(db, _createEnrichmentSpeciesWorkSqlAsset);
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
    await _executeSqlAsset(db, _createEnrichmentTaxonomyWorkSqlAsset);
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
    await _executeSqlAsset(db, _createEnrichmentTaxonomyWorkSpeciesSqlAsset);
    await _executeSqlAsset(db, _createEnrichmentSpeciesCapabilityStateSqlAsset);
    await _executeSqlAsset(db, _createEnrichmentSpeciesDeckMembershipSqlAsset);
    await _executeSqlAsset(db, _createEnrichmentUnresolvedNamesSqlAsset);
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
  }

  static Future<void> _createLocalDiagnosticsTables(Database db) async {
    await _executeSqlAsset(db, _createLocalDiagnosticsEventsSqlAsset);
    await _executeSqlAsset(db, _createLocalDiagnosticsNetworkFailuresSqlAsset);
  }

  static Future<void> _executeSqlAsset(Database db, String assetPath) async {
    final sql = await rootBundle.loadString(assetPath);
    await db.execute(sql);
  }

  static Future<void> _ensureColumnExists(
    Database db,
    String tableName,
    String columnName,
    String columnDefinition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final hasColumn = columns.any((row) => row['name'] == columnName);
    if (hasColumn) return;
    await db.execute(
      'ALTER TABLE $tableName ADD COLUMN $columnName $columnDefinition',
    );
  }

  static Future<void> close() async {
    _log.debug(
      'Closing databases (reference open=${_referenceDb != null}, '
      'user open=${_userDb != null})',
    );
    final referenceInitialization = _referenceInitialization;
    final userInitialization = _userInitialization;

    Database? referenceDb = _referenceDb;
    Database? userDb = _userDb;

    if (referenceDb == null && referenceInitialization != null) {
      try {
        referenceDb = await referenceInitialization;
      } catch (_) {
        // Ignore failed opens during cleanup.
      }
    }

    if (userDb == null && userInitialization != null) {
      try {
        userDb = await userInitialization;
      } catch (_) {
        // Ignore failed opens during cleanup.
      }
    }

    await referenceDb?.close();
    await userDb?.close();

    _referenceDb = null;
    _userDb = null;
    _referenceInitialization = null;
    _userInitialization = null;
    _log.debug('Databases closed');
  }

  /// Deletes the local user database. Useful for testing ensuring a clean state.
  static Future<void> deleteUserDatabase() async {
    await close();
    final dir = await getApplicationSupportDirectory();
    final dbPath = join(dir.path, 'discere_user.db');
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  }
}
