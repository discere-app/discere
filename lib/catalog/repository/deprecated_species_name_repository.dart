import 'dart:math';

import 'package:discere/catalog/repository/binomial_name.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Matches scientific names against species the reference database keeps
/// as `deprecated` — no source delivers them any more, but learning progress
/// may still point at them.
///
/// Deliberately apart from `SpeciesRepository.resolveFullNames`, which only
/// ever answers with active species: search, import and adding species must
/// not reach a deprecated one. This is for a caller that already holds such
/// a species and needs to recognise it by name — the deck update, which
/// would otherwise report a species the remote deck still lists as removed.
class DeprecatedSpeciesNameRepository {
  DeprecatedSpeciesNameRepository({Database? database})
    : _injectedDb = database;

  static const _chunkSize = 400;

  final Database? _injectedDb;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.referenceDb;

  /// Each of [names] that names a deprecated species among [speciesIds],
  /// mapped to that species. A name matching none of them is left out.
  Future<Map<String, String>> resolveAmong(
    List<String> names,
    Set<String> speciesIds,
  ) async {
    final namesByNormalized = <String, List<String>>{};
    for (final name in names) {
      final normalized = normalizeToBinomial(name);
      if (normalized.isEmpty) continue;
      (namesByNormalized[normalized] ??= []).add(name);
    }
    if (namesByNormalized.isEmpty || speciesIds.isEmpty) return const {};

    final db = await _database;
    final normalizedNames = namesByNormalized.keys.toList();
    final result = <String, String>{};
    for (var i = 0; i < normalizedNames.length; i += _chunkSize) {
      final chunk = normalizedNames.sublist(
        i,
        min(i + _chunkSize, normalizedNames.length),
      );
      final placeholders = List.filled(chunk.length, '?').join(', ');
      // Filtered to [speciesIds] here rather than in SQL: a deck's species
      // and its names together would overrun SQLite's variable limit.
      final rows = await db.rawQuery('''
        SELECT ssn.normalized_name AS normalized_name,
               ssn.species_id AS species_id
          FROM species_scientific_names ssn
          JOIN species s ON s.id = ssn.species_id
         WHERE ssn.normalized_name IN ($placeholders)
           AND s.status = 'deprecated'
         ORDER BY ssn.normalized_name, ssn.is_preferred DESC, ssn.species_id
      ''', chunk);
      for (final row in rows) {
        final speciesId = row['species_id'] as String;
        if (!speciesIds.contains(speciesId)) continue;
        for (final name in namesByNormalized[row['normalized_name']]!) {
          result.putIfAbsent(name, () => speciesId);
        }
      }
    }
    return result;
  }
}
