import '../model/biology/species.dart';
import 'package:sqflite/sqflite.dart';

import '../model/biology/classification.dart';
import '../model/language.dart';

class SpeciesRepository {
  static const String speciesTableName = 'species';
  static const String speciesAlias = 's';
  static const String columnSpeciesId = 'id';
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

  static const String deckSpeciesTableName = 'deck_species';
  static const String deckSpeciesAlias = 'ds';
  static const String columnDeckSpeciesDeckId = 'deck_id';
  static const String columnDeckSpeciesSpeciesId = 'species_id';

  static const String flashcardStatsTableName = 'flashcard_stats';
  static const String flashcardStatsAlias = 'fs';
  static const String columnFlashcardStatsDeckId = 'deck_id';
  static const String columnFlashcardStatsSpeciesId = 'species_id';

  late final Database _database;

  SpeciesRepository(Database database) {
    _database = database;
  }

  Future<Set<Species>> getUninitializedSpeciesForDeck(
      String deckId, int limit) async {
    final List<Map<String, dynamic>> dbResult = await _database.rawQuery('''
SELECT
  $speciesAlias.$columnSpeciesId,
  $speciesAlias.$columnSpeciesName,
  $speciesAlias.$columnSpeciesCommonNameDe,
  $speciesAlias.$columnSpeciesCommonNameEn,
  GROUP_CONCAT($picturesAlias.$columnPictureUrl) AS $columnPictureUrls,
  $generaAlias.$columnGenusName AS genus_name,
  $generaAlias.$columnGenusCommonName AS genus_common_name,
  $generaAlias.$columnGenusSubFamily AS genus_subfamily,
  $familiesAlias.$columnFamilyName AS family_name,
  $familiesAlias.$columnFamilyCommonNameDe AS family_common_name_de,
  $familiesAlias.$columnFamilyCommonNameEn AS family_common_name_en,
  $ordersAlias.$columnOrderName AS order_name,
  $ordersAlias.$columnOrderCommonNameDe AS order_common_name_de,
  $ordersAlias.$columnOrderCommonNameEn AS order_common_name_en,
  $classesAlias.$columnClassName AS class_name,
  $classesAlias.$columnClassCommonName AS class_common_name,
  $classesAlias.$columnClassSuperClass AS class_super_class
FROM $speciesTableName AS $speciesAlias
JOIN $generaTableName AS $generaAlias ON $speciesAlias.$columnSpeciesGenusId = $generaAlias.$columnGenusId
JOIN $familiesTableName AS $familiesAlias ON $generaAlias.$columnGenusFamilyId = $familiesAlias.$columnFamilyId
JOIN $ordersTableName AS $ordersAlias ON $familiesAlias.$columnFamilyOrderId = $ordersAlias.$columnOrderId
JOIN $classesTableName AS $classesAlias ON $ordersAlias.$columnOrderClassId = $classesAlias.$columnClassId
LEFT JOIN $picturesTableName AS $picturesAlias ON $speciesAlias.$columnSpeciesId = $picturesAlias.$columnPictureSpeciesId
JOIN $deckSpeciesTableName AS $deckSpeciesAlias ON $deckSpeciesAlias.$columnDeckSpeciesSpeciesId = $speciesAlias.$columnSpeciesId
LEFT JOIN $flashcardStatsTableName AS $flashcardStatsAlias
       ON $flashcardStatsAlias.$columnFlashcardStatsSpeciesId = $speciesAlias.$columnSpeciesId
      AND $flashcardStatsAlias.$columnFlashcardStatsDeckId = $deckSpeciesAlias.$columnDeckSpeciesDeckId
WHERE $deckSpeciesAlias.$columnDeckSpeciesDeckId = ? 
AND $flashcardStatsAlias.$columnFlashcardStatsSpeciesId IS NULL
GROUP BY 
  $speciesAlias.$columnSpeciesId,
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
LIMIT ?
''', [deckId, limit]);

    Set<Species> species = dbResult.map((map) => _mapToSpecies(map)).toSet();
    return species;
  }

  Future<Species?> getSpeciesById(String id) async {
    final result = await _database.rawQuery('''
    SELECT
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

    WHERE $speciesAlias.$columnSpeciesId = ?

    GROUP BY 
      $speciesAlias.$columnSpeciesId,
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

    LIMIT 1
  ''', [id]);

    if (result.isEmpty) {
      return null;
    }

    return _mapToSpecies(result.first);
  }

  Future<Set<Species>> getSpecies(Set<String> ids) async {
    final idsList = ids.toList();

    final result = await _database.rawQuery('''
   SELECT
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

    WHERE $speciesAlias.$columnSpeciesId IN (${idsList.map((_) => '?').join(',')})

    GROUP BY 
      $speciesAlias.$columnSpeciesId,
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

    ORDER BY 
      $classesAlias.$columnClassName,
      $ordersAlias.$columnOrderName,
      $familiesAlias.$columnFamilyName,
      $generaAlias.$columnGenusName
  ''', idsList);

    return result.map((map) => _mapToSpecies(map)).toSet();
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

    final whereClause = validNames
        .map((_) =>
            '($generaAlias.$columnGenusName = ? AND $speciesAlias.$columnSpeciesName = ?)')
        .join(' OR ');

    final arguments =
        validNames.expand((record) => [record.$1, record.$2]).toList();

    final dbResult = await _database.rawQuery('''
    SELECT DISTINCT $speciesAlias.$columnSpeciesId
    FROM $speciesTableName AS $speciesAlias
    JOIN $generaTableName AS $generaAlias ON $speciesAlias.$columnSpeciesGenusId = $generaAlias.$columnGenusId
    WHERE $whereClause
  ''', arguments);

    return dbResult.map((result) => result[columnSpeciesId] as String).toSet();
  }

  Species _mapToSpecies(Map<String, dynamic> map) {
    return Species(
      map['${speciesAlias}_$columnSpeciesId'] as String,
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
