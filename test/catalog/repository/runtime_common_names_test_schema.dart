import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Creates `runtime_common_names` matching the production schema exactly
/// (`assets/sql/user_db/tables/create_runtime_common_names.sql`) — no
/// primary key, since production relies on delete-then-reinsert per
/// `entity_key` rather than a uniqueness constraint. Shared by tests that
/// need real `runtime_common_names` rows (as opposed to the flattened
/// `runtime_common_name_search_documents` cache) so they can't drift from
/// what the app actually creates.
Future<void> createRuntimeCommonNamesTable(Database db) async {
  await db.execute('''
    CREATE TABLE runtime_common_names (
      entity_key     TEXT NOT NULL,
      entity_type    TEXT NOT NULL,
      language_code  TEXT NOT NULL,
      name           TEXT NOT NULL,
      position       INTEGER,
      place_id       INTEGER,
      place_position INTEGER,
      fetched_at     INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE INDEX idx_runtime_common_names_lookup
      ON runtime_common_names(entity_key, language_code)
  ''');
}
