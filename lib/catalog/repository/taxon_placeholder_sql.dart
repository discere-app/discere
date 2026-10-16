import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:sqflite/sqflite.dart';

/// How queries read the reference database's rank placeholders.
///
/// A rank placeholder is a higher taxon a source uses for "not assigned at
/// this rank" — SeaLifeBase's family "Not assigned", say. It holds real
/// species in its chain, so the reference database keeps it as an entity
/// and marks it in an `is_placeholder` column on classes, orders, families
/// and genera.
///
/// A reference database built before that column existed does not have it.
/// Rather than a second set of queries for such a database, every query
/// reads the flag through [sqlFor], which is the column where the database
/// has it and the constant 0 where it does not. The query text stays one,
/// and a database without the column shows its placeholders under their
/// source name, as it always did.
class TaxonPlaceholderSql {
  static const column = 'is_placeholder';

  /// Whether an open database has the column, asked once per database.
  static final _hasColumn = Expando<bool>('taxon placeholder column');

  final bool databaseHasColumn;

  const TaxonPlaceholderSql({required this.databaseHasColumn});

  static Future<TaxonPlaceholderSql> of(Database db) async {
    final known = _hasColumn[db];
    if (known != null) return TaxonPlaceholderSql(databaseHasColumn: known);
    // The ETL adds the column to all four rank tables in one schema, so one
    // of them answers for all.
    final columns = await db.rawQuery('PRAGMA table_info(families)');
    final hasColumn = columns.any((info) => info['name'] == column);
    _hasColumn[db] = hasColumn;
    return TaxonPlaceholderSql(databaseHasColumn: hasColumn);
  }

  /// The flag of the row aliased [alias], as an SQL expression that is 0 or 1.
  String sqlFor(String alias) => databaseHasColumn ? '$alias.$column' : '0';

  /// `<flag> AS <alias>_is_placeholder` for every alias in [aliasByRank],
  /// read back by [ranksIn].
  String columnsFor(Map<TaxonRank, String> aliasByRank) => aliasByRank.values
      .map((alias) => '${sqlFor(alias)} AS ${alias}_$column')
      .join(', ');

  /// The ranks whose flag is set in [row], selected through [columnsFor].
  static Set<TaxonRank> ranksIn(
    Map<String, Object?> row,
    Map<TaxonRank, String> aliasByRank,
  ) => {
    for (final MapEntry(key: rank, value: alias) in aliasByRank.entries)
      if (row['${alias}_$column'] == 1) rank,
  };

  /// Whether [row] carries a set flag under [key].
  static bool isSet(Map<String, Object?>? row, [String key = column]) =>
      row?[key] == 1;
}
