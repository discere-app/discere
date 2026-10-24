import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/repository/optional_reference_table.dart';
import 'package:discere/external/inaturalist/inat_ancestry_requirement.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Which iNaturalist phyla and classes a taxon found by name may sit under,
/// read from the ETL's `inat_allowed_ancestors`: per own class, the ids of
/// the iNaturalist phyla (and classes) that correspond to its phylum (and to
/// itself).
///
/// Null throughout for a reference database without the table: it cannot
/// say what fits, and callers fall back to the name alone.
class INatAllowedAncestorRepository {
  static const tableName = 'inat_allowed_ancestors';

  final Database? _injectedRefDb;

  INatAllowedAncestorRepository({Database? referenceDatabase})
    : _injectedRefDb = referenceDatabase;

  Future<Database> get _referenceDb async =>
      _injectedRefDb ?? await DatabaseHelper.referenceDb;

  /// What a species of the class [classId] requires: a phylum of its class.
  /// A species without a class — its chain breaks off below it — has
  /// nothing to check against, and the requirement cannot be met.
  Future<INatAncestryRequirement?> requirementForSpecies(
    String? classId,
  ) async {
    final db = await _referenceDb;
    if (!await OptionalReferenceTable.exists(db, tableName)) return null;
    if (classId == null) return const INatAncestryRequirement([]);
    final allowed = await _allowedByClass(db, {classId});
    return INatAncestryRequirement([allowed[classId]?.phyla ?? const {}]);
  }

  /// What the higher taxon named [scientificName] on [rank] requires. Its
  /// name key stands for every row of the rank's table with that name and a
  /// species beneath it, so a hit must fit each of them: a phylum of the
  /// row's class, and — below the class rank, where homonyms within one
  /// phylum are common — that class too. A row without a chain up to its
  /// class, or a name no such row carries, cannot be met.
  Future<INatAncestryRequirement?> requirementForHigherTaxon(
    TaxonRank rank,
    String scientificName,
  ) async {
    final db = await _referenceDb;
    if (!await OptionalReferenceTable.exists(db, tableName)) return null;
    final rows = await db.rawQuery(_carrierClassesSql(rank), [
      scientificName.trim().toLowerCase(),
    ]);
    if (rows.isEmpty) return const INatAncestryRequirement([]);
    final classIds = [for (final row in rows) row['class_id'] as String?];
    final allowed = await _allowedByClass(db, classIds.nonNulls.toSet());
    return INatAncestryRequirement([
      for (final classId in classIds) ...[
        allowed[classId]?.phyla ?? const {},
        if (rank != TaxonRank.classRank) allowed[classId]?.classes ?? const {},
      ],
    ]);
  }

  Future<Map<String, ({Set<int> phyla, Set<int> classes})>> _allowedByClass(
    Database db,
    Set<String> classIds,
  ) async {
    if (classIds.isEmpty) return const {};
    final placeholders = List.filled(classIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT class_id, rank, inat_taxon_id FROM $tableName '
      'WHERE class_id IN ($placeholders)',
      classIds.toList(),
    );
    final allowed = <String, ({Set<int> phyla, Set<int> classes})>{};
    for (final row in rows) {
      final entry = allowed.putIfAbsent(
        row['class_id'] as String,
        () => (phyla: <int>{}, classes: <int>{}),
      );
      final taxonId = row['inat_taxon_id'] as int;
      switch (row['rank']) {
        case 'phylum':
          entry.phyla.add(taxonId);
        case 'class':
          entry.classes.add(taxonId);
      }
    }
    return allowed;
  }

  /// The class of every row carrying the name, one row each — the same rows
  /// the ETL checked a mapping against: those with a species beneath them,
  /// and every class.
  static String _carrierClassesSql(TaxonRank rank) => switch (rank) {
    TaxonRank.genus => '''
      SELECT o.class AS class_id
      FROM genera g
      LEFT JOIN families f ON f.id = g.family
      LEFT JOIN orders o ON o.id = f."order"
      WHERE LOWER(TRIM(g.name)) = ?
        AND EXISTS (SELECT 1 FROM species s WHERE s.genus = g.id)''',
    TaxonRank.family => '''
      SELECT o.class AS class_id
      FROM families f
      LEFT JOIN orders o ON o.id = f."order"
      WHERE LOWER(TRIM(f.name)) = ?
        AND EXISTS (SELECT 1 FROM genera g JOIN species s ON s.genus = g.id
                    WHERE g.family = f.id)''',
    TaxonRank.order => '''
      SELECT o.class AS class_id
      FROM orders o
      WHERE LOWER(TRIM(o.name)) = ?
        AND EXISTS (SELECT 1 FROM families f JOIN genera g ON g.family = f.id
                    JOIN species s ON s.genus = g.id
                    WHERE f."order" = o.id)''',
    TaxonRank.classRank => '''
      SELECT c.id AS class_id
      FROM classes c
      WHERE LOWER(TRIM(c.name)) = ?''',
  };
}
