import 'package:sqflite/sqflite.dart';

/// Whether an open reference database has a table that older releases do not
/// ship.
///
/// The ETL adds tables without raising the schema version, so a device keeps
/// an older reference database until it updates. A repository reading such a
/// table asks here first and answers as the reference database could before
/// the table existed, rather than failing on a missing table. Asked once per
/// database, like `TaxonPlaceholderSql`.
class OptionalReferenceTable {
  static final _present = Expando<Map<String, bool>>('optional reference tables');

  const OptionalReferenceTable._();

  static Future<bool> exists(Database db, String table) async {
    final known = _present[db] ??= <String, bool>{};
    final cached = known[table];
    if (cached != null) return cached;
    final rows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return known[table] = rows.isNotEmpty;
  }
}
