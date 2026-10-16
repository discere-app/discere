import 'dart:math';

import 'package:sqflite/sqflite.dart';

/// The aliases of the installed reference database among the IDs the user's
/// data refers to: each superseded ID mapped to the entity that replaced it.
///
/// The reference database keeps an alias for every ID any earlier release
/// used, well over a hundred thousand of them, while a user database refers
/// to a few hundred at most. So only the IDs the user's data holds are looked
/// up, each by primary key, and only the hits are kept — in memory and, for
/// the rewrite itself, in a temporary table of the user database
/// ([writeTempTable]) that the table rewrites join against.
///
/// Reading through the reference database's own connection, rather than
/// attaching its file to the user database's, keeps the rewrite independent
/// of how either connection is opened (`ATTACH` cannot run inside a
/// transaction, and a read-only file attached to a writable connection is
/// writable through it).
///
/// The build guarantees what makes a single pass enough: every alias points
/// directly at an existing entity, and no alias is itself an entity ID. A
/// rewritten ID is therefore never rewritten again, by this pass or a later
/// one.
class ReferenceAliasMap {
  const ReferenceAliasMap(this.newIdByAlias);

  /// Temporary table [writeTempTable] fills, with columns `old_id` (primary
  /// key) and `new_id`.
  static const tempTable = 'temp.reference_id_alias';

  static const _lookupChunkSize = 500;

  /// Superseded ID → the ID that replaces it.
  final Map<String, String> newIdByAlias;

  bool get isEmpty => newIdByAlias.isEmpty;

  /// [id] as the installed reference database names it.
  String rewrite(String id) => newIdByAlias[id] ?? id;

  /// Looks up which of [ids] are aliases in [referenceDb]. A schema-1
  /// reference database has no alias table and so no aliases.
  static Future<ReferenceAliasMap> load(
    DatabaseExecutor referenceDb,
    Set<String> ids,
  ) async {
    final aliasTable = await referenceDb.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'entity_aliases'",
    );
    if (aliasTable.isEmpty) return const ReferenceAliasMap({});
    final idList = ids.toList()..sort();
    final newIdByAlias = <String, String>{};
    for (var i = 0; i < idList.length; i += _lookupChunkSize) {
      final chunk = idList.sublist(
        i,
        min(i + _lookupChunkSize, idList.length),
      );
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await referenceDb.rawQuery(
        'SELECT alias_id, entity_id FROM entity_aliases '
        'WHERE alias_id IN ($placeholders)',
        chunk,
      );
      for (final row in rows) {
        newIdByAlias[row['alias_id'] as String] = row['entity_id'] as String;
      }
    }
    return ReferenceAliasMap(newIdByAlias);
  }

  /// Replaces [tempTable] in [txn]'s connection with this map.
  Future<void> writeTempTable(Transaction txn) async {
    await txn.execute('DROP TABLE IF EXISTS $tempTable');
    await txn.execute(
      'CREATE TEMP TABLE reference_id_alias ('
      'old_id TEXT NOT NULL PRIMARY KEY, new_id TEXT NOT NULL)',
    );
    final batch = txn.batch();
    for (final MapEntry(key: oldId, value: newId) in newIdByAlias.entries) {
      batch.insert('reference_id_alias', {'old_id': oldId, 'new_id': newId});
    }
    await batch.commit(noResult: true);
  }

  /// Drops [tempTable] again.
  static Future<void> dropTempTable(Transaction txn) =>
      txn.execute('DROP TABLE IF EXISTS $tempTable');
}
