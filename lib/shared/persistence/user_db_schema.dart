import 'dart:convert';

import 'package:discere/shared/persistence/schema/schema_asset.dart';
import 'package:discere/shared/persistence/schema/schema_reconciler.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
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
part 'migration/migration_v13.dart';
part 'migration/migration_v14.dart';
part 'migration/migration_v15.dart';
part 'migration/migration_v16.dart';
part 'migration/migration_v17.dart';
part 'migration/migration_v18.dart';
part 'migration/migration_v19.dart';
part 'migration/migration_v20.dart';

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
const _createLocalDiagnosticsNetworkFailuresSqlAsset =
    'assets/sql/user_db/tables/create_local_diagnostics_network_failures.sql';
const _createDeckConfigSqlAsset =
    'assets/sql/user_db/tables/create_deck_config.sql';
const _createSpeciesPhotoGapAckSqlAsset =
    'assets/sql/user_db/tables/create_species_photo_gap_ack.sql';

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
  static const int version = 20;

  /// Every table of the current schema, in creation order — `decks` first,
  /// because the tables after it declare a foreign key to it.
  ///
  /// This is both the create path and [SchemaReconciler]'s input, so a table
  /// absent from this list is a table nothing repairs. Adding a
  /// `create_*.sql` asset means adding it here;
  /// `user_db_schema_assets_test.dart` fails if one is left out.
  ///
  /// The full-text index deliberately uses `fts4` rather than `fts5`: fts5 is
  /// not compiled into every Android/SQLite build this app runs against, and
  /// an optimistic fts5 statement failed inside the schema transaction on some
  /// runtimes.
  @visibleForTesting
  static const schemaAssetPaths = <String>[
    _createDecksSqlAsset,
    _createFlashcardStatsSqlAsset,
    _createDeckConfigSqlAsset,
    _createSpeciesPhotoGapAckSqlAsset,
    _createINatPhotoCacheSqlAsset,
    _createRuntimeCommonNamesSqlAsset,
    _createRuntimeCommonNameSearchDocumentsSqlAsset,
    _createRuntimeCommonNameSearchFtsSqlAsset,
    _createExternalIdentifierCacheSqlAsset,
    _createEnrichmentJobsSqlAsset,
    _createEnrichmentSpeciesWorkSqlAsset,
    _createEnrichmentTaxonomyWorkSqlAsset,
    _createEnrichmentTaxonomyWorkSpeciesSqlAsset,
    _createEnrichmentSpeciesCapabilityStateSqlAsset,
    _createEnrichmentSpeciesDeckMembershipSqlAsset,
    _createEnrichmentUnresolvedNamesSqlAsset,
    _createLocalDiagnosticsNetworkFailuresSqlAsset,
  ];

  /// `onCreate` for a fresh user database — builds the current schema directly.
  static Future<void> create(Database db, int version) async {
    _log.debug('User DB schema create start (version=$version)');
    await _reconcileCurrentSchema(db);
    _log.debug('User DB schema create done');
  }

  /// `onUpgrade` — runs the ordered migrations from [oldVersion] up to the
  /// current [version], then reconciles the result against the current schema.
  /// Each version bump lives in its own `migration/migration_vN.dart` part
  /// file.
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
    if (oldVersion < 13) await migrateUserDbToV13(db);
    if (oldVersion < 14) await migrateUserDbToV14(db);
    if (oldVersion < 15) await migrateUserDbToV15(db);
    if (oldVersion < 16) await migrateUserDbToV16(db);
    if (oldVersion < 17) await migrateUserDbToV17(db);
    if (oldVersion < 18) await migrateUserDbToV18(db);
    if (oldVersion < 19) await migrateUserDbToV19(db);
    if (oldVersion < 20) await migrateUserDbToV20(db);

    // Bring whatever the ladder produced to the current shape: missing
    // tables, missing columns, missing indexes. A migration describes the
    // schema as it was (ARCH-13), so this is what states what it is now.
    await _reconcileCurrentSchema(db);
    _log.debug('User DB schema upgrade done');
  }

  /// Reconciles [db] against the assets in [schemaAssetPaths].
  ///
  /// The same call serves both entry points: on a fresh database every table
  /// is missing, so reconciliation *is* the create path, and after an upgrade
  /// it closes whatever gap the ladder left. One code path means the two
  /// cannot drift apart.
  static Future<void> _reconcileCurrentSchema(Database db) async {
    final assets = <SchemaAsset>[];
    for (final path in schemaAssetPaths) {
      assets.add(SchemaAsset.parse(await rootBundle.loadString(path)));
    }
    await SchemaReconciler.reconcile(db, assets);
  }
}
