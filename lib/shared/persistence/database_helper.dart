import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:discere/shared/util/logger.dart';

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
  static const _createLocalDiagnosticsEventsSqlAsset =
      'assets/sql/user_db/tables/create_local_diagnostics_events.sql';
  static const _createLocalDiagnosticsNetworkFailuresSqlAsset =
      'assets/sql/user_db/tables/create_local_diagnostics_network_failures.sql';
  static const _createDeckConfigSqlAsset =
      'assets/sql/user_db/tables/create_deck_config.sql';
  static const _createDailyCountsSqlAsset =
      'assets/sql/user_db/tables/create_daily_counts.sql';

  static Database? _referenceDb;
  static Database? _userDb;
  static Future<Database>? _referenceInitialization;
  static Future<Database>? _userInitialization;

  @visibleForTesting
  static const int referenceDbVersion = 2;
  @visibleForTesting
  static const int userDbVersion = 10;
  static const String prefKeyDbVersion = 'last_reference_db_version';

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

  static Future<Database> _openReferenceDb() async {
    final dir = await getApplicationSupportDirectory();
    final dbPath = join(dir.path, 'discere_reference.db');
    final stopwatch = Stopwatch()..start();

    await _copyAssetIfNeeded(dbPath);

    _log.debug("Opening reference database at: $dbPath");
    try {
      final db = await openDatabase(dbPath, readOnly: true);
      _log.debug(
        "Reference database opened successfully in ${stopwatch.elapsedMilliseconds}ms.",
      );
      return db;
    } finally {
      stopwatch.stop();
    }
  }

  static Future<void> _copyAssetIfNeeded(String dbPath) async {
    final dbFile = File(dbPath);

    if (await dbFile.exists()) {
      final shouldUpdate = await isNewerVersionAvailable();
      if (!shouldUpdate) {
        _log.debug(
          "Reference database asset copy skipped; local copy is current.",
        );
        return;
      }
      _log.debug("Newer database version available, updating local copy.");
    } else {
      _log.debug("Database not found locally, copying from assets.");
    }

    _log.debug("Starting database copy from assets...");
    final stopwatch = Stopwatch()..start();

    final data = await rootBundle.load('assets/database/discere_reference.db');
    final bytes = data.buffer.asUint8List();
    await dbFile.writeAsBytes(bytes, flush: true);

    _log.debug(
      "Database asset copied to: $dbPath in ${stopwatch.elapsedMilliseconds}ms",
    );
    stopwatch.stop();

    // Update the version in SharedPreferences after a successful copy
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefKeyDbVersion, referenceDbVersion);
  }

  @visibleForTesting
  static Future<bool> isNewerVersionAvailable() async {
    final prefs = await SharedPreferences.getInstance();
    final lastVersion = prefs.getInt(prefKeyDbVersion) ?? 0;
    return referenceDbVersion > lastVersion;
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

    _log.debug("Opening user database at: $dbPath");
    try {
      final db = await openDatabase(
        dbPath,
        version: userDbVersion,
        onCreate: _createUserSchema,
        onUpgrade: _upgradeUserSchema,
      );
      _log.debug(
        "User database opened successfully with version: ${await db.getVersion()} "
        "in ${stopwatch.elapsedMilliseconds}ms",
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
    _log.debug('Migrating user DB v8 → v9: adding per-name-type learning stats');

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
    await _executeSqlAsset(db, _createDailyCountsSqlAsset);
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
    await _executeSqlAsset(db, _createEnrichmentTaxonomyWorkSqlAsset);
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
