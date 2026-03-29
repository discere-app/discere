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
  static const int referenceDbVersion = 1; // Increment this when updating assets/database/discere_reference.db
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

    return openDatabase(dbPath, readOnly: true);
  }

  static Future<void> _copyAssetIfNeeded(String dbPath) async {
    final dbFile = File(dbPath);

    if (await dbFile.exists()) {
      final shouldUpdate = await isNewerVersionAvailable();
      if (!shouldUpdate) return;
      if (kDebugMode) {
        print("Newer database version available, updating local copy.");
      }
    } else {
      if (kDebugMode) {
        print("Database not found locally, copying from assets.");
      }
    }

    final data = await rootBundle.load('assets/database/discere_reference.db');
    final bytes = data.buffer.asUint8List();
    await dbFile.writeAsBytes(bytes, flush: true);

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

    return openDatabase(
      dbPath,
      version: 1,
      onCreate: _createUserSchema,
      onUpgrade: _upgradeUserSchema,
    );
  }

  static Future<void> _createUserSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE decks (
        id              TEXT PRIMARY KEY,
        name            TEXT NOT NULL,
        description     TEXT,
        coverImagePath  TEXT
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
  }

  static Future<void> _upgradeUserSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    throw UnimplementedError(
      'User DB migration from v$oldVersion to v$newVersion not implemented.',
    );
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
