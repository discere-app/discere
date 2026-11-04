import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/model/removed_comparison_species.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// The user's comparison lists (`comparison_lists`) and the species in each
/// (`comparison_list_species`).
class ComparisonListRepository {
  static const _listsTable = 'comparison_lists';
  static const _speciesTable = 'comparison_list_species';

  final Database? _injectedDb;

  ComparisonListRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  /// Every list, newest first, each with its species in list order.
  Future<List<ComparisonList>> getLists() async {
    final db = await _database;
    final listRows = await db.query(_listsTable, orderBy: 'created_at DESC');
    // rowid breaks a tie in position — a species put back after another took
    // the last position in the meantime — by insertion order.
    final speciesRows = await db.query(
      _speciesTable,
      columns: ['list_id', 'species_id'],
      orderBy: 'position, rowid',
    );

    final speciesIdsByList = <String, List<String>>{};
    for (final row in speciesRows) {
      speciesIdsByList
          .putIfAbsent(row['list_id'] as String, () => [])
          .add(row['species_id'] as String);
    }
    return [
      for (final row in listRows)
        ComparisonList(
          id: row['id'] as String,
          name: row['name'] as String,
          speciesIds: List.unmodifiable(
            speciesIdsByList[row['id'] as String] ?? const <String>[],
          ),
        ),
    ];
  }

  /// Creates the list [id] holding [speciesIds] in their iteration order, in
  /// one transaction.
  Future<void> createList({
    required String id,
    required String name,
    required Set<String> speciesIds,
    required DateTime at,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.insert(_listsTable, {
        'id': id,
        'name': name,
        'created_at': at.millisecondsSinceEpoch,
      });
      await _appendSpecies(txn, id, speciesIds);
    });
  }

  /// Adds [speciesIds] to [listId] after the species it already holds. A
  /// species already in the list stays where it is.
  Future<void> addSpecies(String listId, Set<String> speciesIds) async {
    final db = await _database;
    await db.transaction((txn) => _appendSpecies(txn, listId, speciesIds));
  }

  Future<void> _appendSpecies(
    Transaction txn,
    String listId,
    Set<String> speciesIds,
  ) async {
    final last = await txn.rawQuery(
      'SELECT MAX(position) AS last FROM $_speciesTable WHERE list_id = ?',
      [listId],
    );
    var position = (last.single['last'] as int? ?? -1) + 1;
    final batch = txn.batch();
    for (final speciesId in speciesIds) {
      batch.insert(_speciesTable, {
        'list_id': listId,
        'species_id': speciesId,
        'position': position++,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  /// Removes [speciesId] from [listId] and answers what [restoreSpecies]
  /// needs to put it back, or null when the list did not hold it.
  Future<RemovedComparisonSpecies?> removeSpecies(
    String listId,
    String speciesId,
  ) async {
    final db = await _database;
    return db.transaction((txn) async {
      const where = 'list_id = ? AND species_id = ?';
      final whereArgs = [listId, speciesId];
      final rows = await txn.query(
        _speciesTable,
        columns: ['position'],
        where: where,
        whereArgs: whereArgs,
      );
      if (rows.isEmpty) return null;
      await txn.delete(_speciesTable, where: where, whereArgs: whereArgs);
      return RemovedComparisonSpecies(
        listId: listId,
        speciesId: speciesId,
        position: rows.single['position'] as int,
      );
    });
  }

  /// Puts [removed] back at its old position. Does nothing when its list has
  /// gone in the meantime or holds the species again.
  Future<void> restoreSpecies(RemovedComparisonSpecies removed) async {
    final db = await _database;
    // INSERT … SELECT rather than a plain insert: the foreign key would
    // reject a row for a deleted list, and that is no error here.
    await db.rawInsert(
      'INSERT OR IGNORE INTO $_speciesTable (list_id, species_id, position) '
      'SELECT id, ?, ? FROM $_listsTable WHERE id = ?',
      [removed.speciesId, removed.position, removed.listId],
    );
  }

  Future<void> renameList(String listId, String name) async {
    final db = await _database;
    await db.update(
      _listsTable,
      {'name': name},
      where: 'id = ?',
      whereArgs: [listId],
    );
  }

  /// Its species follow through ON DELETE CASCADE.
  Future<void> deleteList(String listId) async {
    final db = await _database;
    await db.delete(_listsTable, where: 'id = ?', whereArgs: [listId]);
  }
}
