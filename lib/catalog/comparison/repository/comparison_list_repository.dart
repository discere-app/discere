import 'package:discere/catalog/comparison/model/comparison_list.dart';
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

  /// Every list, newest first, each with its species in the order they were
  /// added.
  Future<List<ComparisonList>> getLists() async {
    final db = await _database;
    final listRows = await db.query(_listsTable, orderBy: 'created_at DESC');
    // rowid breaks the tie between species added in one call, which share
    // their added_at: they keep the order they were passed in.
    final speciesRows = await db.query(
      _speciesTable,
      columns: ['list_id', 'species_id'],
      orderBy: 'added_at, rowid',
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

  /// Creates the list [id] holding [speciesIds], in one transaction.
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
      await _insertSpecies(txn, id, speciesIds, at);
    });
  }

  /// Adds [speciesIds] to [listId] after the species it already holds. A
  /// species already in the list stays where it is.
  Future<void> addSpecies(
    String listId,
    Set<String> speciesIds, {
    required DateTime at,
  }) async {
    final db = await _database;
    await db.transaction((txn) => _insertSpecies(txn, listId, speciesIds, at));
  }

  Future<void> _insertSpecies(
    Transaction txn,
    String listId,
    Set<String> speciesIds,
    DateTime at,
  ) async {
    final batch = txn.batch();
    for (final speciesId in speciesIds) {
      batch.insert(_speciesTable, {
        'list_id': listId,
        'species_id': speciesId,
        'added_at': at.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeSpecies(String listId, String speciesId) async {
    final db = await _database;
    await db.delete(
      _speciesTable,
      where: 'list_id = ? AND species_id = ?',
      whereArgs: [listId, speciesId],
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
