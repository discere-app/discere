import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
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

  static Database? _referenceDb;
  static Database? _userDb;
  static Future<Database>? _referenceInitialization;
  static Future<Database>? _userInitialization;

  @visibleForTesting
  static const int referenceDbVersion = 5; // Increment this when updating assets/database/discere_reference.db
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

  static Future<Database> _openReferenceDb() async {
    final dir = await getApplicationSupportDirectory();
    final dbPath = join(dir.path, 'discere_reference.db');

    await _copyAssetIfNeeded(dbPath);

    if (kDebugMode) debugPrint("Opening reference database at: $dbPath");
    final db = await openDatabase(dbPath, readOnly: true);
    if (kDebugMode) debugPrint("Reference database opened successfully.");
    return db;
  }

  static Future<void> _copyAssetIfNeeded(String dbPath) async {
    final dbFile = File(dbPath);

    if (await dbFile.exists()) {
      final shouldUpdate = await isNewerVersionAvailable();
      if (!shouldUpdate) return;
      if (kDebugMode) {
        debugPrint("Newer database version available, updating local copy.");
      }
    } else {
      if (kDebugMode) {
        debugPrint("Database not found locally, copying from assets.");
      }
    }

    if (kDebugMode) debugPrint("Starting database copy from assets...");

    final data = await rootBundle.load('assets/database/discere_reference.db');
    final bytes = data.buffer.asUint8List();
    await dbFile.writeAsBytes(bytes, flush: true);

    if (kDebugMode) debugPrint("Database asset copied to: $dbPath");

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

    if (kDebugMode) debugPrint("Opening user database at: $dbPath");
    try {
      final db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: _createUserSchema,
      );
      if (kDebugMode) {
        debugPrint(
          "User database opened successfully with version: ${await db.getVersion()} "
          "in ${stopwatch.elapsedMilliseconds}ms",
        );
      }
      return db;
    } finally {
      stopwatch.stop();
    }
  }

  static Future<void> _createUserSchema(Database db, int version) async {
    if (kDebugMode) {
      debugPrint('User DB schema create start (version=$version)');
    }
    await _createCurrentUserSchema(db);
    if (kDebugMode) {
      debugPrint('User DB schema create done');
    }
  }

  static Future<void> _createCurrentUserSchema(Database db) async {
    await _executeSqlAsset(db, _createDecksSqlAsset);
    await _executeSqlAsset(db, _createFlashcardStatsSqlAsset);
    await _createINatCacheTable(db);
    await _createRuntimeCommonNamesTable(db);
    await _createRuntimeCommonNameSearchTables(db);
    await _createExternalIdentifierCacheTable(db);
  }

  static Future<void> _createINatCacheTable(Database db) async {
    await _executeSqlAsset(db, _createINatPhotoCacheSqlAsset);
  }

  static Future<void> _createRuntimeCommonNamesTable(Database db) async {
    await _executeSqlAsset(db, _createRuntimeCommonNamesSqlAsset);
  }

  static Future<void> _createRuntimeCommonNameSearchTables(Database db) async {
    await _executeSqlAsset(
      db,
      _createRuntimeCommonNameSearchDocumentsSqlAsset,
    );
    await _createRuntimeCommonNameSearchFtsTable(db);
  }

  /// Creates the local full-text index for runtime common-name search documents.
  ///
  /// We intentionally use `fts4` for broad Android/SQLite compatibility. The
  /// previous optimistic `fts5` attempt produced a failing statement during the
  /// schema transaction on some runtimes.
  static Future<void> _createRuntimeCommonNameSearchFtsTable(Database db) async {
    await _executeSqlAsset(db, _createRuntimeCommonNameSearchFtsSqlAsset);
  }

  static Future<void> _createExternalIdentifierCacheTable(Database db) async {
    await _executeSqlAsset(db, _createExternalIdentifierCacheSqlAsset);
  }

  static Future<void> _executeSqlAsset(Database db, String assetPath) async {
    final sql = await rootBundle.loadString(assetPath);
    await db.execute(sql);
  }

  static Future<void> close() async {
    await _referenceDb?.close();
    await _userDb?.close();
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
