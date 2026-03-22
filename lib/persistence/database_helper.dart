import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static Database? _referenceDb;
  static Database? _userDb;

  // ---------------------------------------------------------------------------
  // Reference DB (read-only)
  // ---------------------------------------------------------------------------

  static Future<Database> get referenceDb async {
    _referenceDb ??= await _openReferenceDb();
    return _referenceDb!;
  }

  static Future<Database> _openReferenceDb() async {
    final dir = await getApplicationSupportDirectory();
    final dbPath = join(dir.path, 'discere_reference.db');

    await _copyAssetIfNeeded(dbPath);

    return openDatabase(
      dbPath,
      readOnly: true,
    );
  }

  static Future<void> _copyAssetIfNeeded(String dbPath) async {
    final dbFile = File(dbPath);

    if (await dbFile.exists()) {
      final shouldUpdate = await _isNewerVersionAvailable(dbPath);
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
  }

  static Future<bool> _isNewerVersionAvailable(String localDbPath) async {
    try {
      final localDb = await openDatabase(localDbPath, readOnly: true);
      final localMetadataRows = await localDb.query('metadata', where: 'key IS NOT NULL', orderBy: 'key');
      await localDb.close();

      final dir = await getTemporaryDirectory();
      final tempPath = join(dir.path, 'discere_check.db');
      final data = await rootBundle.load('assets/database/discere_reference.db');
      await File(tempPath).writeAsBytes(data.buffer.asUint8List());
      final assetDb = await openDatabase(tempPath, readOnly: true);
      final assetMetadataRows = await assetDb.query('metadata', where: 'key IS NOT NULL', orderBy: 'key');
      await assetDb.close();
      await File(tempPath).delete();

      if (localMetadataRows.length != assetMetadataRows.length) return true;
      for (int i = 0; i < localMetadataRows.length; i++) {
        if (localMetadataRows[i]['key'] != assetMetadataRows[i]['key'] ||
            localMetadataRows[i]['value'] != assetMetadataRows[i]['value']) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  // ---------------------------------------------------------------------------
  // User DB (read-write)
  // ---------------------------------------------------------------------------

  static Future<Database> get userDb async {
    _userDb ??= await _openUserDb();
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
        external_id      TEXT NOT NULL,
        external_source  TEXT NOT NULL,
        deck_id          TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
        next_review_date INTEGER,
        interval         INTEGER DEFAULT 0,
        repetition       INTEGER DEFAULT 0,
        ease_factor      REAL    DEFAULT 2.5,
        PRIMARY KEY (deck_id, external_source, external_id)
      )
    ''');
  }

  static Future<void> _upgradeUserSchema(
      Database db, int oldVersion, int newVersion) async {
    throw UnimplementedError(
      'User DB migration from v$oldVersion to v$newVersion not implemented.',
    );
  }

  static Future<Database> openAquaFlashDB() async {
    // Stub to keep main.dart compiling during Phase 1 transition
    throw UnimplementedError('openAquaFlashDB is deprecated. Phase 2/3 will migrate repositories to userDb and referenceDb.');
  }

  static Future<void> close() async {
    await _referenceDb?.close();
    await _userDb?.close();
    _referenceDb = null;
    _userDb = null;
  }
}
