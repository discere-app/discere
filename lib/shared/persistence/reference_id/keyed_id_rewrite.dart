import 'dart:convert';

import 'package:discere/shared/persistence/reference_id/reference_alias_map.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_rewrite_report.dart';
import 'package:sqflite/sqflite.dart';

/// One row a rewrite reads: where it is, which ID it holds and which it will
/// hold, and the [values] of the columns its table's rules need.
class IdRow {
  const IdRow({
    required this.rowId,
    required this.oldId,
    required this.newId,
    required this.values,
  });

  final int rowId;
  final String oldId;
  final String newId;
  final Map<String, Object?> values;

  /// Whether [oldId] is an alias. A row that is not already holds [newId]:
  /// it is the row that was there before the rewrite.
  bool get isAliased => oldId != newId;
}

/// What a collision leaves behind: the row that stays (none, when every row
/// of the group goes) and the column values it takes from the others.
class CollisionOutcome {
  const CollisionOutcome(this.survivor, [this.survivorUpdate = const {}]);

  const CollisionOutcome.dropAll() : survivor = null, survivorUpdate = const {};

  final IdRow? survivor;
  final Map<String, Object?> survivorUpdate;
}

/// Picks the outcome for a group of rows that would share one key after the
/// rewrite. Called only for groups of two or more.
typedef CollisionRule = CollisionOutcome Function(List<IdRow> group);

/// Runs once a table's IDs are rewritten, given the rows a collision removed
/// and the survivors a collision updated.
typedef AfterRewrite =
    Future<void> Function(
      Transaction txn, {
      required List<int> droppedRowIds,
      required List<int> mergedRowIds,
    });

/// A user-database table holding reference IDs in one key column, with the
/// rule for rows that collide once their IDs are rewritten.
///
/// The ID is read through [idSql], an SQL expression over the table's
/// columns in which `{t}` stands for the table, so a column that wraps the ID
/// (`species:<id>`) is handled like a raw one; [scopeSql], written the same
/// way, limits the rewrite to the rows whose column holds such an ID.
/// [setIdSql] is the `SET` clause that writes back the new ID it is given as
/// an SQL expression.
class KeyedIdTable {
  const KeyedIdTable({
    required this.table,
    required this.idSql,
    required this.setIdSql,
    required this.keyColumns,
    required this.onCollision,
    this.scopeSql = '1',
    this.valueColumns = const [],
    this.afterRewrite,
  });

  final String table;
  final String idSql;
  final String Function(String newIdSql) setIdSql;
  final String scopeSql;

  /// The columns besides the ID that make up a row's key: rows that agree on
  /// them and on the rewritten ID collide.
  final List<String> keyColumns;

  /// Further columns [onCollision] decides by.
  final List<String> valueColumns;

  final CollisionRule onCollision;

  final AfterRewrite? afterRewrite;

  /// Rewrites every aliased ID in [table] through [ReferenceAliasMap.tempTable]
  /// and records the counts in [report].
  Future<void> rewrite(Transaction txn, ReferenceIdRewriteReport report) async {
    const alias = ReferenceAliasMap.tempTable;
    final columns = {...keyColumns, ...valueColumns}.map((c) => 't.$c');
    final rows = await txn.rawQuery('''
      SELECT t.rowid AS row_id, ${_qualified('t')} AS old_id,
             COALESCE(a.new_id, ${_qualified('t')}) AS new_id
             ${columns.isEmpty ? '' : ', ${columns.join(', ')}'}
        FROM $table t
        LEFT JOIN $alias a ON a.old_id = ${_qualified('t')}
       WHERE ${_scoped('t')}
         AND (a.old_id IS NOT NULL
              OR ${_qualified('t')} IN (SELECT new_id FROM $alias))
    ''');

    final groups = <String, List<IdRow>>{};
    for (final row in rows) {
      final idRow = IdRow(
        rowId: row['row_id'] as int,
        oldId: row['old_id'] as String,
        newId: row['new_id'] as String,
        values: row,
      );
      final key = jsonEncode([
        idRow.newId,
        for (final column in keyColumns) row[column],
      ]);
      (groups[key] ??= []).add(idRow);
    }

    final droppedRowIds = <int>[];
    final mergedRowIds = <int>[];
    for (final group in groups.values) {
      if (group.length < 2) continue;
      final outcome = onCollision(group);
      for (final row in group) {
        if (identical(row, outcome.survivor)) continue;
        droppedRowIds.add(row.rowId);
      }
      final survivor = outcome.survivor;
      if (survivor != null && outcome.survivorUpdate.isNotEmpty) {
        await txn.update(
          table,
          outcome.survivorUpdate,
          where: 'rowid = ?',
          whereArgs: [survivor.rowId],
        );
        mergedRowIds.add(survivor.rowId);
      }
    }
    for (final rowId in droppedRowIds) {
      await txn.delete(table, where: 'rowid = ?', whereArgs: [rowId]);
    }

    // After the deletes, no two remaining rows share a rewritten key, and a
    // new ID is never itself an alias — so this cannot collide row by row.
    final rewritten = await txn.rawUpdate('''
      UPDATE $table
         SET ${setIdSql('(SELECT new_id FROM $alias WHERE old_id = ${_qualified(table)})')}
       WHERE ${_scoped(table)}
         AND ${_qualified(table)} IN (SELECT old_id FROM $alias)
    ''');

    await afterRewrite?.call(
      txn,
      droppedRowIds: droppedRowIds,
      mergedRowIds: mergedRowIds,
    );
    report.record(table, rewritten: rewritten, dropped: droppedRowIds.length);
  }

  String _qualified(String qualifier) => idSql.replaceAll('{t}', qualifier);

  String _scoped(String qualifier) => scopeSql.replaceAll('{t}', qualifier);
}

/// Keeps the row that already held the new ID — what the user had under the
/// valid ID stays as it is. When every row of the group is aliased, keeps
/// the one with the smallest old ID, so the outcome does not depend on the
/// order the rows were read in.
IdRow existingRowOrSmallestOldId(List<IdRow> group) {
  for (final row in group) {
    if (!row.isAliased) return row;
  }
  return (List.of(group)..sort((a, b) => a.oldId.compareTo(b.oldId))).first;
}
