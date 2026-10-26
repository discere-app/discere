import 'package:discere/learning/model/subdeck.dart';
import 'package:discere/learning/model/subdeck_structure.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// The subdecks of the user's decks: `deck_subdecks`, which species of a
/// deck belong to which (`deck_subdeck_species`), and the subdeck of each
/// imported name still waiting to be resolved
/// (`deck_subdeck_unresolved_names`).
///
/// Membership of the deck itself stays where it is, in `flashcard_stats`;
/// these tables only say how a deck's species are divided up.
class SubdeckRepository {
  final Database? _injectedDb;

  SubdeckRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  /// Makes [structure] the subdecks of [deckId], in one transaction.
  ///
  /// A subdeck already there keeps whether it is active and takes the new
  /// name and position; a new one starts active. A subdeck the structure no
  /// longer has goes, and its species with it into no subdeck at all. Which
  /// species and names belong where is replaced as a whole.
  Future<void> writeStructure(String deckId, SubdeckStructure structure) async {
    final db = await _database;
    await db.transaction((txn) async {
      final kept = [for (final subdeck in structure.subdecks) subdeck.id];
      // Their species and names follow through ON DELETE CASCADE.
      await txn.delete(
        'deck_subdecks',
        where:
            'deck_id = ? AND subdeck_id NOT IN '
            '(${List.filled(kept.length, '?').join(',')})',
        whereArgs: [deckId, ...kept],
      );
      await txn.delete(
        'deck_subdeck_species',
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
      await txn.delete(
        'deck_subdeck_unresolved_names',
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );

      final batch = txn.batch();
      for (final (index, subdeck) in structure.subdecks.indexed) {
        batch.insert('deck_subdecks', {
          'deck_id': deckId,
          'subdeck_id': subdeck.id,
          'name': subdeck.name,
          'sort_order': index,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        batch.update(
          'deck_subdecks',
          {'name': subdeck.name, 'sort_order': index},
          where: 'deck_id = ? AND subdeck_id = ?',
          whereArgs: [deckId, subdeck.id],
        );
      }
      for (final MapEntry(key: speciesId, value: subdeckId)
          in structure.subdeckIdBySpeciesId.entries) {
        batch.insert('deck_subdeck_species', {
          'deck_id': deckId,
          'species_id': speciesId,
          'subdeck_id': subdeckId,
        });
      }
      for (final MapEntry(key: name, value: subdeckId)
          in structure.subdeckIdByUnresolvedName.entries) {
        batch.insert('deck_subdeck_unresolved_names', {
          'deck_id': deckId,
          'name': name,
          'subdeck_id': subdeckId,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  /// The subdecks of [deckId] in their order, each with its species count.
  Future<List<Subdeck>> getSubdecks(String deckId) async {
    final db = await _database;
    final rows = await db.rawQuery(
      '''
      SELECT d.deck_id, d.subdeck_id, d.name, d.sort_order, d.is_active,
             (SELECT COUNT(*) FROM deck_subdeck_species s
               WHERE s.deck_id = d.deck_id AND s.subdeck_id = d.subdeck_id)
               AS species_count
      FROM deck_subdecks d
      WHERE d.deck_id = ?
      ORDER BY d.sort_order
    ''',
      [deckId],
    );
    return rows.map(Subdeck.fromMap).toList();
  }

  /// The subdeck of each species of [deckId] that belongs to one.
  Future<Map<String, String>> getSubdeckIdBySpeciesId(String deckId) async {
    final db = await _database;
    final rows = await db.query(
      'deck_subdeck_species',
      columns: ['species_id', 'subdeck_id'],
      where: 'deck_id = ?',
      whereArgs: [deckId],
    );
    return {
      for (final row in rows)
        row['species_id'] as String: row['subdeck_id'] as String,
    };
  }

  /// The species in a switched-off subdeck of [deckId].
  Future<Set<String>> getSpeciesIdsInInactiveSubdecks(String deckId) async =>
      (await _speciesInInactiveSubdecks(deckId: deckId))[deckId] ?? const {};

  /// The species in a switched-off subdeck, across all decks, keyed by deck
  /// id. A deck without such species is missing from the result.
  Future<Map<String, Set<String>>> getSpeciesIdsInInactiveSubdecksByDeckId() =>
      _speciesInInactiveSubdecks();

  Future<Map<String, Set<String>>> _speciesInInactiveSubdecks({
    String? deckId,
  }) async {
    final db = await _database;
    final rows = await db.rawQuery(
      '''
      SELECT s.deck_id, s.species_id
      FROM deck_subdeck_species s
      JOIN deck_subdecks d
        ON d.deck_id = s.deck_id AND d.subdeck_id = s.subdeck_id
      WHERE d.is_active = 0 ${deckId == null ? '' : 'AND s.deck_id = ?'}
    ''',
      [?deckId],
    );
    final byDeckId = <String, Set<String>>{};
    for (final row in rows) {
      (byDeckId[row['deck_id'] as String] ??= {}).add(
        row['species_id'] as String,
      );
    }
    return byDeckId;
  }

  /// Switches the subdecks of [deckId] in [activeSubdeckIds] on and every
  /// other one off.
  Future<void> setActiveSubdecks(
    String deckId,
    Set<String> activeSubdeckIds,
  ) async {
    final db = await _database;
    final ids = activeSubdeckIds.toList();
    await db.rawUpdate(
      '''
      UPDATE deck_subdecks
         SET is_active = subdeck_id IN (${List.filled(ids.length, '?').join(',')})
       WHERE deck_id = ?
    ''',
      [...ids, deckId],
    );
  }

  /// Takes [speciesIds] out of their subdecks of [deckId] — for species that
  /// leave the deck, so that one added again later is in none.
  Future<void> removeSpecies(String deckId, Set<String> speciesIds) async {
    if (speciesIds.isEmpty) return;
    final db = await _database;
    final ids = speciesIds.toList();
    await db.delete(
      'deck_subdeck_species',
      where:
          'deck_id = ? AND species_id IN '
          '(${List.filled(ids.length, '?').join(',')})',
      whereArgs: [deckId, ...ids],
    );
  }

  /// Puts [speciesId], resolved from the imported [name], into the subdeck
  /// that name was listed in, and forgets the name. Nothing happens for a
  /// name listed in no subdeck, and a species already in one stays there.
  Future<void> assignResolvedName(
    String deckId,
    String name,
    String speciesId,
  ) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.rawInsert(
        '''
        INSERT OR IGNORE INTO deck_subdeck_species
          (deck_id, species_id, subdeck_id)
        SELECT deck_id, ?, subdeck_id
        FROM deck_subdeck_unresolved_names
        WHERE deck_id = ? AND name = ?
      ''',
        [speciesId, deckId, name],
      );
      await txn.delete(
        'deck_subdeck_unresolved_names',
        where: 'deck_id = ? AND name = ?',
        whereArgs: [deckId, name],
      );
    });
  }
}
