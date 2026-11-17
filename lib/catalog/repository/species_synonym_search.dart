import 'package:discere/catalog/repository/optional_reference_table.dart';
import 'package:discere/catalog/repository/search_sql.dart';
import 'package:discere/catalog/search/search_ranking.dart';
import 'package:sqflite/sqflite.dart';

/// Finds active species under their synonyms — scientific names a source
/// gives them besides the current one — from the ETL's
/// `species_synonyms_fts`.
///
/// A synonym of several species finds each of them. A species several of
/// whose synonyms match is found once, under the synonym that matches best.
///
/// Empty for a reference database without the table: older releases do not
/// ship it, and search there finds species under their current names only.
class SpeciesSynonymSearch {
  static const _table = 'species_synonyms_fts';

  /// How many species one search returns, as many as each reference search
  /// branch.
  static const _speciesLimit = 20;

  /// How many synonym rows one search reads. A species has up to dozens of
  /// synonyms and a short prefix matches thousands of rows, so the window
  /// is several times [_speciesLimit] to still fill it with distinct
  /// species; the rows are two short columns from the index alone.
  static const _synonymRowLimit = 200;

  final Future<Database> Function() _referenceDatabase;

  const SpeciesSynonymSearch(this._referenceDatabase);

  /// Rows shaped like the reference search's species rows, each with the
  /// synonym it was found through as `matched_synonym`.
  ///
  /// [wildcardTerm] is the FTS term bound to `MATCH`; [normalizedSearchTerm]
  /// decides which synonym of a species matches best, and which species
  /// fill the limit when more match.
  Future<List<Map<String, dynamic>>> search(
    String wildcardTerm,
    String normalizedSearchTerm,
  ) async {
    final db = await _referenceDatabase();
    if (!await OptionalReferenceTable.exists(db, _table)) return const [];

    final synonymRows = await db.rawQuery(
      speciesSynonymFtsSql(_synonymRowLimit),
      [wildcardTerm],
    );
    final synonymBySpecies = _bestSynonymBySpecies(
      synonymRows,
      normalizedSearchTerm,
    );
    if (synonymBySpecies.isEmpty) return const [];

    final speciesRows = await db.rawQuery(
      activeSpeciesByIdSql(synonymBySpecies.length),
      synonymBySpecies.keys.toList(),
    );
    return [
      for (final row in speciesRows)
        {...row, 'matched_synonym': synonymBySpecies[row['id']]},
    ];
  }

  /// The best-matching synonym of each species, for the [_speciesLimit]
  /// species whose synonyms match best.
  Map<String, String> _bestSynonymBySpecies(
    List<Map<String, Object?>> rows,
    String normalizedSearchTerm,
  ) {
    int compare(String a, String b) {
      final byMatch = _matchPriority(
        a,
        normalizedSearchTerm,
      ).compareTo(_matchPriority(b, normalizedSearchTerm));
      return byMatch != 0 ? byMatch : a.compareTo(b);
    }

    final best = <String, String>{};
    for (final row in rows) {
      final speciesId = row['species_id'] as String;
      final synonym = row['name'] as String;
      final current = best[speciesId];
      if (current == null || compare(synonym, current) < 0) {
        best[speciesId] = synonym;
      }
    }

    // By species id last, so that species sharing their best synonym fill
    // the limit the same way every time.
    final ranked = best.entries.toList()
      ..sort((a, b) {
        final bySynonym = compare(a.value, b.value);
        return bySynonym != 0 ? bySynonym : a.key.compareTo(b.key);
      });
    return Map.fromEntries(ranked.take(_speciesLimit));
  }

  int _matchPriority(String synonym, String normalizedSearchTerm) =>
      nameMatchPriority([synonym], normalizedSearchTerm: normalizedSearchTerm);
}
