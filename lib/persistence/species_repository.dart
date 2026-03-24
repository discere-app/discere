import '../model/biology/species.dart';
import 'package:sqflite/sqflite.dart';

import '../model/biology/classification.dart';
import '../model/language.dart';
import 'database_helper.dart';

class SpeciesRepository {
  static const String speciesTableName = 'species';
  static const String speciesAlias = 's';
  static const String columnSpeciesId = 'id';
  static const String columnSpeciesExternalId = 'external_id';
  static const String columnSpeciesExternalSource = 'external_source';
  static const String columnSpeciesName = 'name';
  static const String columnSpeciesCommonNameDe = 'common_name_de';
  static const String columnSpeciesCommonNameEn = 'common_name_en';
  static const String columnSpeciesGenusId = 'genus'; // FK zu Genera

  static const String generaTableName = 'genera';
  static const String generaAlias = 'g';
  static const String columnGenusId = 'id';
  static const String columnGenusName = 'name';
  static const String columnGenusSubFamily = 'subfamily';
  static const String columnGenusCommonName = 'common_name';
  static const String columnGenusFamilyId = 'family'; // FK zu Families

  static const String familiesTableName = 'families';
  static const String familiesAlias = 'f';
  static const String columnFamilyId = 'id';
  static const String columnFamilyName = 'name';
  static const String columnFamilyCommonNameDe = 'common_name_de';
  static const String columnFamilyCommonNameEn = 'common_name_en';
  static const String columnFamilyOrderId = '"order"'; // FK zu Orders

  static const String ordersTableName = 'orders';
  static const String ordersAlias = 'o';
  static const String columnOrderId = 'id';
  static const String columnOrderName = 'name';
  static const String columnOrderCommonNameDe = 'common_name_de';
  static const String columnOrderCommonNameEn = 'common_name_en';
  static const String columnOrderClassId = 'class'; // FK zu Classes

  static const String classesTableName = 'classes';
  static const String classesAlias = 'c';
  static const String columnClassId = 'id';
  static const String columnClassName = 'name';
  static const String columnClassCommonName = 'common_name';
  static const String columnClassSuperClass = 'super_class';

  static const String picturesTableName = 'pictures';
  static const String picturesAlias = 'p';
  static const String columnPictureId = 'id';
  static const String columnPictureSpeciesId = 'species'; // FK zu Species
  static const String columnPictureUrl = 'url';
  static const columnPictureUrls = 'pictureUrls';

  static const String _selectClause = '''
      $speciesAlias.$columnSpeciesExternalSource AS ${speciesAlias}_$columnSpeciesExternalSource,
      $speciesAlias.$columnSpeciesExternalId AS ${speciesAlias}_$columnSpeciesExternalId,
      $speciesAlias.$columnSpeciesId AS ${speciesAlias}_$columnSpeciesId,
      $speciesAlias.$columnSpeciesName AS ${speciesAlias}_$columnSpeciesName,
      $speciesAlias.$columnSpeciesCommonNameDe AS ${speciesAlias}_$columnSpeciesCommonNameDe,
      $speciesAlias.$columnSpeciesCommonNameEn AS ${speciesAlias}_$columnSpeciesCommonNameEn,
      GROUP_CONCAT($picturesAlias.$columnPictureUrl) AS ${speciesAlias}_$columnPictureUrls,

      $generaAlias.$columnGenusName AS ${generaAlias}_$columnGenusName,
      $generaAlias.$columnGenusCommonName AS ${generaAlias}_$columnGenusCommonName,
      $generaAlias.$columnGenusSubFamily AS ${generaAlias}_$columnGenusSubFamily,

      $familiesAlias.$columnFamilyName AS ${familiesAlias}_$columnFamilyName,
      $familiesAlias.$columnFamilyCommonNameDe AS ${familiesAlias}_$columnFamilyCommonNameDe,
      $familiesAlias.$columnFamilyCommonNameEn AS ${familiesAlias}_$columnFamilyCommonNameEn,

      $ordersAlias.$columnOrderName AS ${ordersAlias}_$columnOrderName,
      $ordersAlias.$columnOrderCommonNameDe AS ${ordersAlias}_$columnOrderCommonNameDe,
      $ordersAlias.$columnOrderCommonNameEn AS ${ordersAlias}_$columnOrderCommonNameEn,

      $classesAlias.$columnClassName AS ${classesAlias}_$columnClassName,
      $classesAlias.$columnClassCommonName AS ${classesAlias}_$columnClassCommonName,
      $classesAlias.$columnClassSuperClass AS ${classesAlias}_$columnClassSuperClass
  ''';

  static const String _joinClause = '''
    FROM $speciesTableName AS $speciesAlias
    JOIN $generaTableName AS $generaAlias 
      ON $speciesAlias.$columnSpeciesGenusId = $generaAlias.$columnGenusId
    JOIN $familiesTableName AS $familiesAlias 
      ON $generaAlias.$columnGenusFamilyId = $familiesAlias.$columnFamilyId
    JOIN $ordersTableName AS $ordersAlias 
      ON $familiesAlias.$columnFamilyOrderId = $ordersAlias.$columnOrderId
    JOIN $classesTableName AS $classesAlias 
      ON $ordersAlias.$columnOrderClassId = $classesAlias.$columnClassId
    LEFT JOIN $picturesTableName AS $picturesAlias 
      ON $speciesAlias.$columnSpeciesId = $picturesAlias.$columnPictureSpeciesId
  ''';

  static const String _groupClause = '''
    GROUP BY 
      $speciesAlias.$columnSpeciesId,
      $speciesAlias.$columnSpeciesExternalSource,
      $speciesAlias.$columnSpeciesExternalId,
      $speciesAlias.$columnSpeciesName,
      $speciesAlias.$columnSpeciesCommonNameDe,
      $speciesAlias.$columnSpeciesCommonNameEn,
      $generaAlias.$columnGenusName,
      $generaAlias.$columnGenusCommonName,
      $generaAlias.$columnGenusSubFamily,
      $familiesAlias.$columnFamilyName,
      $familiesAlias.$columnFamilyCommonNameDe,
      $familiesAlias.$columnFamilyCommonNameEn,
      $ordersAlias.$columnOrderName,
      $ordersAlias.$columnOrderCommonNameDe,
      $ordersAlias.$columnOrderCommonNameEn,
      $classesAlias.$columnClassName,
      $classesAlias.$columnClassCommonName,
      $classesAlias.$columnClassSuperClass
  ''';

  final Database? _injectedDb;

  SpeciesRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async => _injectedDb ?? await DatabaseHelper.referenceDb;

  Future<Species?> getSpeciesById(String id) async {
    final db = await _database;
    final result = await db.rawQuery('''
    SELECT $_selectClause
    $_joinClause
    WHERE $speciesAlias.$columnSpeciesId = ?
    $_groupClause
    LIMIT 1
  ''', [id]);

    if (result.isEmpty) {
      return null;
    }

    return _mapToSpecies(result.first);
  }

  Future<Set<Species>> getSpecies(Set<String> ids) async {
    if (ids.isEmpty) return {};

    final Set<Species> allSpecies = {};
    
    // Chunking is used to prevent SQLite Exception: "too many SQL variables".
    // SQLite has a hard limit of 999 parameters per query. 
    // Here we use 1 parameter per ID, so a chunkSize of 900 is safe.
    const int chunkSize = 900;
    
    final idList = ids.toList();
    final db = await _database;

    for (var i = 0; i < idList.length; i += chunkSize) {
      final chunk = idList.skip(i).take(chunkSize).toList();

      final whereClauses = List.generate(chunk.length, (_) => "$speciesAlias.$columnSpeciesId = ?");
      final arguments = chunk;
      final whereString = whereClauses.join(' OR ');

      final result = await db.rawQuery('''
      SELECT $_selectClause
      $_joinClause
      WHERE $whereString
      $_groupClause
      ORDER BY 
        $classesAlias.$columnClassName,
        $ordersAlias.$columnOrderName,
        $familiesAlias.$columnFamilyName,
        $generaAlias.$columnGenusName
    ''', arguments);

      allSpecies.addAll(result.map((map) => _mapToSpecies(map)));
    }

    return allSpecies;
  }

  Future<Set<String>> getSpeciesIdsByScientificNames(
      List<(String, String)> scientificNames) async {
    //  leere Einträge filtern
    final validNames = scientificNames.where((record) {
      return record.$1.isNotEmpty && record.$2.isNotEmpty;
    }).toList();

    if (validNames.isEmpty) {
      return {};
    }

    final Set<String> allSpeciesIds = {};
    
    // Chunking prevents crashing when users paste or import large lists of species.
    // Each tuple generates 2 query parameters (g.name = ? AND s.name = ?).
    // A chunk size of 400 strictly limits parameters to 800, well below SQLite's 999 maximum limit.
    const int chunkSize = 400; // max 800 parameters per chunk
    
    final db = await _database;

    for (var i = 0; i < validNames.length; i += chunkSize) {
      final chunk = validNames.skip(i).take(chunkSize).toList();

      final whereClause = chunk
          .map((_) =>
              '($generaAlias.$columnGenusName = ? AND $speciesAlias.$columnSpeciesName = ?)')
          .join(' OR ');

      final arguments =
          chunk.expand((record) => [record.$1, record.$2]).toList();

      final dbResult = await db.rawQuery('''
      SELECT DISTINCT $speciesAlias.$columnSpeciesId
      FROM $speciesTableName AS $speciesAlias
      JOIN $generaTableName AS $generaAlias ON $speciesAlias.$columnSpeciesGenusId = $generaAlias.$columnGenusId
      WHERE $whereClause
    ''', arguments);

      allSpeciesIds.addAll(
        dbResult.map((result) => result[columnSpeciesId] as String),
      );
    }

    return allSpeciesIds;
  }

  Species _mapToSpecies(Map<String, dynamic> map) {
    final source = map['${speciesAlias}_$columnSpeciesExternalSource'] as String;
    final extId = map['${speciesAlias}_$columnSpeciesExternalId'] as String;

    return Species(
      map['${speciesAlias}_$columnSpeciesId'] as String,
      extId,
      source,
      map['${speciesAlias}_$columnSpeciesName'] as String,
      {
        Language.de:
            map['${speciesAlias}_$columnSpeciesCommonNameDe'] as String? ?? '',
        Language.en:
            map['${speciesAlias}_$columnSpeciesCommonNameEn'] as String? ?? '',
      },
      _mapToClassification(map),
      _parsePictureUrls(map['${speciesAlias}_$columnPictureUrls']),
    );
  }

  Classification _mapToClassification(Map<String, dynamic> map) {
    return Classification(
      map['${generaAlias}_$columnGenusName'] as String,
      {
        Language.de:
            map['${generaAlias}_$columnGenusCommonName'] as String? ?? '',
      },
      map['${generaAlias}_$columnGenusSubFamily'] as String?,
      map['${familiesAlias}_$columnFamilyName'] as String,
      {
        Language.de:
            map['${familiesAlias}_$columnFamilyCommonNameDe'] as String? ?? '',
        Language.en:
            map['${familiesAlias}_$columnFamilyCommonNameEn'] as String? ?? '',
      },
      map['${ordersAlias}_$columnOrderName'] as String,
      {
        Language.de:
            map['${ordersAlias}_$columnOrderCommonNameDe'] as String? ?? '',
        Language.en:
            map['${ordersAlias}_$columnOrderCommonNameEn'] as String? ?? '',
      },
      map['${classesAlias}_$columnClassName'] as String,
      {
        Language.de:
            map['${classesAlias}_$columnClassCommonName'] as String? ?? '',
      },
      map['${classesAlias}_$columnClassSuperClass'] as String?,
    );
  }

  List<String> _parsePictureUrls(String? concatenatedUrls) {
    if (concatenatedUrls == null || concatenatedUrls.isEmpty) {
      return [];
    }
    return concatenatedUrls.split(',');
  }
}
