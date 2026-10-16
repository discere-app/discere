import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/repository/taxon_placeholder_sql.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Which ranks of each species' chain assign it to no taxon, read without
/// loading the species.
///
/// The question a check across a whole deck asks — which of its species
/// have a genus, which a family — needs only the chain's ids and placeholder
/// flags. `SpeciesRepository.getSpecies` would load pictures, common names,
/// traits and regions for every one of them on top, and the check runs for
/// every deck card the deck list shows.
class TaxonAssignmentRepository {
  static const _aliasByRank = {
    TaxonRank.genus: 'g',
    TaxonRank.family: 'f',
    TaxonRank.order: 'o',
    TaxonRank.classRank: 'c',
  };

  /// Below SQLite's oldest limit on bound parameters, like the other
  /// chunked lookups.
  static const _chunkSize = 900;

  final Database? _injectedDb;

  TaxonAssignmentRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.referenceDb;

  /// `Classification.unassignedRanks` of each of [speciesIds] the reference
  /// database holds: the ranks that are a rank placeholder, and the ranks
  /// the chain does not reach. A species the database does not hold is
  /// missing from the result.
  Future<Map<String, Set<TaxonRank>>> unassignedRanksOf(
    Set<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) return const {};
    final db = await _database;
    final placeholders = await TaxonPlaceholderSql.of(db);
    final ids = speciesIds.toList(growable: false);
    final result = <String, Set<TaxonRank>>{};

    for (var start = 0; start < ids.length; start += _chunkSize) {
      final chunk = ids.skip(start).take(_chunkSize).toList(growable: false);
      final rows = await db.rawQuery('''
        SELECT s.id, g.id AS g_id, f.id AS f_id, o.id AS o_id, c.id AS c_id,
          ${placeholders.columnsFor(_aliasByRank)}
        FROM species s
        LEFT JOIN genera g ON g.id = s.genus
        LEFT JOIN families f ON f.id = g.family
        LEFT JOIN orders o ON o.id = f."order"
        LEFT JOIN classes c ON c.id = o.class
        WHERE s.id IN (${List.filled(chunk.length, '?').join(', ')})
      ''', chunk);

      for (final row in rows) {
        result[row['id'] as String] = {
          ...TaxonPlaceholderSql.ranksIn(row, _aliasByRank),
          for (final MapEntry(key: rank, value: alias) in _aliasByRank.entries)
            if (row['${alias}_id'] == null) rank,
        };
      }
    }
    return result;
  }
}
