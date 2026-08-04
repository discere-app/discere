import 'package:discere/shared/persistence/user_db_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens a fresh in-memory user database with the full, current schema
/// (built via the real [UserDbSchema.create], not a hand-picked subset of
/// `create_*.sql` files) and foreign-key enforcement on, mirroring
/// `DatabaseHelper._openUserDb`'s `onOpen`. A real SQLite connection rather
/// than a mock, so tests exercise actual constraints (cascades, uniqueness,
/// FTS) without touching disk, and without the test schema silently
/// drifting from production as migrations get added.
///
/// Requires `TestWidgetsFlutterBinding.ensureInitialized()` to already have
/// run (needed for the `rootBundle` asset reads `UserDbSchema.create` does
/// internally).
Future<Database> openInMemoryUserDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(
    inMemoryDatabasePath,
    version: UserDbSchema.version,
    onConfigure: _seedFtsTableForTestHost,
    onCreate: UserDbSchema.create,
  );
  await db.execute('PRAGMA foreign_keys = ON');
  return db;
}

/// The sqlite3 build `sqflite_common_ffi` links on some hosts (e.g. macOS,
/// via the system libsqlite3) only has the fts5 module compiled in, not
/// fts4 — but `UserDbSchema` deliberately creates
/// `runtime_common_name_search_fts` with fts4 for on-device Android
/// compatibility (see its own doc comment). Pre-creating the table here
/// with whichever module this host actually supports — same fts5-then-fts4
/// fallback `search_repository_test.dart` already uses — means
/// `UserDbSchema.create`'s `CREATE VIRTUAL TABLE IF NOT EXISTS ... fts4`
/// becomes a no-op instead of throwing "no such module: fts4".
Future<void> _seedFtsTableForTestHost(Database db) async {
  const columns =
      'scientific_name, common_name_en, common_name_de, common_name_fr, '
      'common_name_es';
  try {
    await db.execute(
      'CREATE VIRTUAL TABLE runtime_common_name_search_fts '
      "USING fts5($columns, tokenize='unicode61')",
    );
  } on DatabaseException {
    await db.execute(
      'CREATE VIRTUAL TABLE runtime_common_name_search_fts '
      'USING fts4($columns, tokenize=unicode61)',
    );
  }
}
