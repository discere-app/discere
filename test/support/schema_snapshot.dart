import 'package:sqflite/sqflite.dart';

/// A structural snapshot of every table in [db]: its columns (name, type,
/// nullability, default, position in the primary key) and its explicit indexes.
///
/// Compared instead of the `sqlite_master` DDL text, because a table that was
/// migrated or reconciled still carries the text it was originally created with
/// plus whatever `ALTER TABLE` appended — so the text differs from a fresh
/// install's even when the schema is identical. Column order differs for the
/// same reason and is deliberately not part of the comparison; everything here
/// is addressed by name in SQL.
Future<Map<String, Object?>> schemaSnapshot(Database db) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' "
    'ORDER BY name',
  );
  final snapshot = <String, Object?>{};
  for (final table in tables) {
    final name = table['name'] as String;
    final columns = await db.rawQuery('PRAGMA table_info($name)');
    final indexes = <String, Object?>{};
    for (final index in await db.rawQuery('PRAGMA index_list($name)')) {
      final indexName = index['name'] as String;
      // Implicit PRIMARY KEY/UNIQUE indexes — already covered by the
      // column-level `pk` value and the table's own DDL.
      if (indexName.startsWith('sqlite_autoindex_')) continue;
      final indexColumns = await db.rawQuery('PRAGMA index_info($indexName)');
      indexes[indexName] = {
        'unique': index['unique'],
        'columns': [for (final column in indexColumns) column['name']],
      };
    }
    snapshot[name] = {
      'columns': {
        for (final column in columns)
          column['name'] as String: {
            'type': column['type'],
            'notnull': column['notnull'],
            'default': column['dflt_value'],
            'pk': column['pk'],
          },
      },
      'indexes': indexes,
    };
  }
  return snapshot;
}
