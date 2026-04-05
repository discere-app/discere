import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
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

    if (kDebugMode) debugPrint("Opening user database at: $dbPath");
    final db = await openDatabase(
      dbPath,
      version: 8,
      onCreate: _createUserSchema,
      onUpgrade: _upgradeUserSchema,
    );
    if (kDebugMode) {
      debugPrint(
        "User database opened successfully with version: ${await db.getVersion()}",
      );
    }
    return db;
  }

  static Future<void> _createUserSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE decks (
        id              TEXT PRIMARY KEY,
        name            TEXT NOT NULL,
        description     TEXT,
        coverImagePath  TEXT,
        language        INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE flashcard_stats (
        species_id       TEXT NOT NULL,
        deck_id          TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
        next_review_date INTEGER,
        interval         INTEGER DEFAULT 0,
        repetition       INTEGER DEFAULT 0,
        ease_factor      REAL    DEFAULT 2.5,
        stability        REAL    DEFAULT 0.0,
        difficulty       REAL    DEFAULT 0.0,
        last_review_date INTEGER,
        PRIMARY KEY (deck_id, species_id)
      )
    ''');
    await _createINatCacheTable(db);
    await _createINatCommonNamesTable(db);
    await _createINatTaxonomyCommonNamesTable(db);
    await _createDownloadedNameSearchTables(db);
    await _createExternalIdentifierCacheTable(db);
  }

  static Future<void> _upgradeUserSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (kDebugMode) {
      debugPrint('Upgrading user DB from v$oldVersion to v$newVersion');
    }

    // Sequentielle Migrationen: Jede Version wird nacheinander abgearbeitet.
    if (oldVersion < 2) {
      await _migrateToV2(db);
    }
    if (oldVersion < 3) {
      await _migrateToV3(db);
    }
    if (oldVersion < 4) {
      await _migrateToV4(db);
    }
    if (oldVersion < 5) {
      await _migrateToV5(db);
    }
    if (oldVersion < 6) {
      await _migrateToV6(db);
    }
    if (oldVersion < 7) {
      await _migrateToV7(db);
    }
    if (oldVersion < 8) {
      await _migrateToV8(db);
    }
  }

  static Future<void> _migrateToV2(Database db) async {
    await db.execute(
      'ALTER TABLE decks ADD COLUMN language INTEGER NOT NULL DEFAULT 1',
    );
  }

  static Future<void> _migrateToV3(Database db) async {
    await _createINatCacheTable(db);
  }

  static Future<void> _migrateToV4(Database db) async {
    await _createLegacyExternalIdentifiersTable(db);
  }

  static Future<void> _migrateToV5(Database db) async {
    final existingTables = await db.query(
      'sqlite_master',
      columns: ['name'],
      where:
          "type = 'table' AND name IN ('external_identifiers', 'external_identifier_cache')",
    );

    final tableNames = existingTables
        .map((row) => row['name'] as String)
        .toSet();

    if (tableNames.contains('external_identifiers') &&
        !tableNames.contains('external_identifier_cache')) {
      await db.execute(
        'ALTER TABLE external_identifiers RENAME TO external_identifier_cache',
      );
      return;
    }

    await _createExternalIdentifierCacheTable(db);
  }

  static Future<void> _migrateToV6(Database db) async {
    await _createINatCommonNamesTable(db);
  }

  static Future<void> _migrateToV7(Database db) async {
    await _createINatTaxonomyCommonNamesTable(db);
  }

  static Future<void> _migrateToV8(Database db) async {
    await _createDownloadedNameSearchTables(db);
  }

  static Future<void> _createINatCacheTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inat_photo_cache (
        species_id   TEXT NOT NULL,
        photo_url    TEXT NOT NULL,
        thumb_url    TEXT,
        attribution  TEXT,
        license_code TEXT,
        fetched_at   INTEGER NOT NULL,
        PRIMARY KEY (species_id, photo_url)
      )
    ''');
  }

  static Future<void> _createINatCommonNamesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inat_common_names (
        species_id     TEXT NOT NULL,
        language_code  TEXT NOT NULL,
        names          TEXT NOT NULL,
        fetched_at     INTEGER NOT NULL,
        PRIMARY KEY (species_id, language_code)
      )
    ''');
  }

  static Future<void> _createINatTaxonomyCommonNamesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inat_taxonomy_common_names (
        entity_key     TEXT NOT NULL,
        language_code  TEXT NOT NULL,
        names          TEXT NOT NULL,
        fetched_at     INTEGER NOT NULL,
        PRIMARY KEY (entity_key, language_code)
      )
    ''');
  }

  static Future<void> _createDownloadedNameSearchTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS downloaded_name_search_documents (
        entity_key             TEXT NOT NULL PRIMARY KEY,
        entity_id              TEXT NOT NULL,
        entity_type            TEXT NOT NULL,
        scientific_name        TEXT NOT NULL,
        common_name_en         TEXT,
        common_name_de         TEXT,
        common_name_fr         TEXT,
        common_name_es         TEXT,
        normalized_search_text TEXT NOT NULL
      )
    ''');

    await _createDownloadedNameSearchFtsTable(db);
  }

  /// Creates the local full-text index for downloaded names.
  ///
  /// Different SQLite runtimes expose different FTS modules. We prefer `fts5`
  /// when available and gracefully fall back to `fts4` for older runtimes.
  static Future<void> _createDownloadedNameSearchFtsTable(Database db) async {
    const ftsColumns = '''
      entity_key,
      scientific_name,
      common_name_en,
      common_name_de,
      common_name_fr,
      common_name_es
    ''';

    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS downloaded_name_search_fts
        USING fts5(
          $ftsColumns,
          tokenize = 'unicode61'
        )
      ''');
    } on DatabaseException {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS downloaded_name_search_fts
        USING fts4(
          $ftsColumns,
          tokenize=unicode61
        )
      ''');
    }
  }

  static Future<void> _createLegacyExternalIdentifiersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS external_identifiers (
        entity_id       TEXT NOT NULL,
        provider        TEXT NOT NULL,
        external_id     TEXT NOT NULL,
        last_synced_at  INTEGER NOT NULL,
        PRIMARY KEY (entity_id, provider)
      )
    ''');
  }

  static Future<void> _createExternalIdentifierCacheTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS external_identifier_cache (
        entity_id       TEXT NOT NULL,
        provider        TEXT NOT NULL,
        external_id     TEXT NOT NULL,
        last_synced_at  INTEGER NOT NULL,
        PRIMARY KEY (entity_id, provider)
      )
    ''');
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
