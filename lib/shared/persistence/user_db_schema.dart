import 'dart:convert';

import 'package:discere/shared/util/logger.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

part 'migration/migration_v2.dart';
part 'migration/migration_v3.dart';
part 'migration/migration_v4.dart';
part 'migration/migration_v5.dart';
part 'migration/migration_v6.dart';
part 'migration/migration_v7.dart';
part 'migration/migration_v8.dart';
part 'migration/migration_v9.dart';
part 'migration/migration_v10.dart';
part 'migration/migration_v11.dart';
part 'migration/migration_v12.dart';

final _log = Logger.forType(UserDbSchema);

const _createDecksSqlAsset = 'assets/sql/user_db/tables/create_decks.sql';
const _createFlashcardStatsSqlAsset =
    'assets/sql/user_db/tables/create_flashcard_stats.sql';
const _createINatPhotoCacheSqlAsset =
    'assets/sql/user_db/tables/create_inat_photo_cache.sql';
const _createRuntimeCommonNamesSqlAsset =
    'assets/sql/user_db/tables/create_runtime_common_names.sql';
const _createRuntimeCommonNameSearchDocumentsSqlAsset =
    'assets/sql/user_db/tables/create_runtime_common_name_search_documents.sql';
const _createRuntimeCommonNameSearchFtsSqlAsset =
    'assets/sql/user_db/fts/create_runtime_common_name_search_fts.sql';
const _createExternalIdentifierCacheSqlAsset =
    'assets/sql/user_db/tables/create_external_identifier_cache.sql';
const _createEnrichmentJobsSqlAsset =
    'assets/sql/user_db/tables/create_enrichment_jobs.sql';
const _createEnrichmentJobStagesSqlAsset =
    'assets/sql/user_db/tables/create_enrichment_job_stages.sql';
const _createEnrichmentSpeciesWorkSqlAsset =
    'assets/sql/user_db/tables/create_enrichment_species_work.sql';
const _createEnrichmentTaxonomyWorkSqlAsset =
    'assets/sql/user_db/tables/create_enrichment_taxonomy_work.sql';
const _createEnrichmentTaxonomyWorkSpeciesSqlAsset =
    'assets/sql/user_db/tables/create_enrichment_taxonomy_work_species.sql';
const _createEnrichmentSpeciesCapabilityStateSqlAsset =
    'assets/sql/user_db/tables/create_enrichment_species_capability_state.sql';
const _createEnrichmentSpeciesDeckMembershipSqlAsset =
    'assets/sql/user_db/tables/create_enrichment_species_deck_membership.sql';
const _createEnrichmentUnresolvedNamesSqlAsset =
    'assets/sql/user_db/tables/create_enrichment_unresolved_names.sql';
const _createLocalDiagnosticsEventsSqlAsset =
    'assets/sql/user_db/tables/create_local_diagnostics_events.sql';
const _createLocalDiagnosticsNetworkFailuresSqlAsset =
    'assets/sql/user_db/tables/create_local_diagnostics_network_failures.sql';
const _createDeckConfigSqlAsset =
    'assets/sql/user_db/tables/create_deck_config.sql';
// Only used by the historical v3→v4/v5→v6/v8→v9 migration steps below —
// fresh installs and upgrades past v11 no longer create this table (see
// _migrateUserSchemaV10ToV11).
const _createDailyCountsSqlAsset =
    'assets/sql/user_db/tables/create_daily_counts.sql';

Future<void> _executeSqlAsset(Database db, String assetPath) async {
  final sql = await rootBundle.loadString(assetPath);
  await db.execute(sql);
}

Future<void> _ensureColumnExists(
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

Future<bool> _tableExists(Database db, String tableName) async {
  final result = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    [tableName],
  );
  return result.isNotEmpty;
}

Future<bool> _tableHasColumn(
  Database db,
  String tableName,
  String columnName,
) async {
  if (!await _tableExists(db, tableName)) return false;
  final columns = await db.rawQuery('PRAGMA table_info($tableName)');
  return columns.any((column) => column['name'] == columnName);
}

List<String> _decodeStringListForMigration(Object? rawValue) {
  if (rawValue is! String || rawValue.isEmpty) return <String>[];
  final decoded = jsonDecode(rawValue);
  if (decoded is! List) return <String>[];
  return decoded.whereType<String>().toList();
}

/// Owns the user database schema: its [version], initial [create]ion and the
/// ordered [upgrade] migrations (one `migration_vN.dart` part file per version).
/// Extracted from `DatabaseHelper` so each file has one responsibility.
class UserDbSchema {
  UserDbSchema._();

  /// Current user DB schema version — bump whenever a migration is added.
  static const int version = 12;

  /// `onCreate` for a fresh user database — builds the current schema directly.
  static Future<void> create(Database db, int version) async {
    _log.debug('User DB schema create start (version=$version)');
    await _createCurrentUserSchema(db);
    _log.debug('User DB schema create done');
  }

  /// `onUpgrade` — runs the ordered migrations from [oldVersion] up to the
  /// current [version], then repairs any missing tables/columns. Each version
  /// bump lives in its own `migration/migration_vN.dart` part file.
  static Future<void> upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    _log.debug('User DB schema upgrade start ($oldVersion -> $newVersion)');

    if (oldVersion < 2) await migrateUserDbToV2(db);
    if (oldVersion < 3) await migrateUserDbToV3(db);
    if (oldVersion < 4) await migrateUserDbToV4(db);
    if (oldVersion < 5) await migrateUserDbToV5(db);
    if (oldVersion < 6) await migrateUserDbToV6(db);
    if (oldVersion < 7) await migrateUserDbToV7(db);
    if (oldVersion < 8) await migrateUserDbToV8(db);
    if (oldVersion < 9) await migrateUserDbToV9(db);
    if (oldVersion < 10) await migrateUserDbToV10(db);
    if (oldVersion < 11) await migrateUserDbToV11(db);
    if (oldVersion < 12) await migrateUserDbToV12(db);

    // Ensure all tables exist (CREATE TABLE IF NOT EXISTS is idempotent).
    await _createCurrentUserSchema(db);
    _log.debug('User DB schema upgrade done');
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
}
