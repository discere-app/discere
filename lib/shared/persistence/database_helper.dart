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

  static Database? _referenceDb;
  static Database? _userDb;
  static Future<Database>? _referenceInitialization;
  static Future<Database>? _userInitialization;

  @visibleForTesting
  static const int referenceDbVersion = 6; // Increment this when updating assets/database/discere_reference.db
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
        version: 2,
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

  static Future<void> _upgradeUserSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    _log.debug('User DB schema upgrade start ($oldVersion -> $newVersion)');
    await _createCurrentUserSchema(db);
    _log.debug('User DB schema upgrade done');
  }

  static Future<void> _createCurrentUserSchema(Database db) async {
    await _executeSqlAsset(db, _createDecksSqlAsset);
    await _executeSqlAsset(db, _createFlashcardStatsSqlAsset);
    await _createINatCacheTable(db);
    await _createRuntimeCommonNamesTable(db);
    await _createRuntimeCommonNameSearchTables(db);
    await _createExternalIdentifierCacheTable(db);
    await _createEnrichmentJobTables(db);
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
    await _executeSqlAsset(db, _createEnrichmentJobStagesSqlAsset);
  }

  static Future<void> _executeSqlAsset(Database db, String assetPath) async {
    final sql = await rootBundle.loadString(assetPath);
    await db.execute(sql);
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
