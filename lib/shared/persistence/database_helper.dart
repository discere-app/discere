import 'dart:async';
import 'dart:io';

import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/user_db_schema.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final _log = Logger.forType(DatabaseHelper);

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
  static int get userDbVersion => UserDbSchema.version;

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
        version: UserDbSchema.version,
        onCreate: UserDbSchema.create,
        onUpgrade: UserDbSchema.upgrade,
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
