import 'package:flutter/foundation.dart';

import 'package:discere/catalog/model/body_form.dart';
import 'package:discere/catalog/model/fishing_importance.dart';
import 'package:discere/catalog/model/habitat_tag.dart';
import 'package:discere/catalog/model/human_risk.dart';
import 'package:discere/catalog/util/region_label_resolver.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_native_region.dart';
import 'package:discere/catalog/model/species_status.dart';
import 'package:sqflite/sqflite.dart';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/persistence/database_helper.dart';

/// Reads species from the reference database and merges user-side enrichments.
///
/// The repository keeps the reference DB as the canonical source of taxonomy,
/// pictures, and baseline common names. User-DB enrichments from iNaturalist
/// are merged on read for species names and higher taxonomy ranks so the rest
/// of the app can continue to consume a single [Species] model.
class SpeciesRepository {
  static const bool _enableSpeciesDebugLogging = true;
  static const String speciesTableName = 'species';
  static const String speciesAlias = 's';
  static const String columnSpeciesId = 'id';
  static const String columnSpeciesExternalId = 'external_id';
  static const String columnSpeciesExternalSource = 'external_source';
  static const String columnSpeciesName = 'name';
  static const String columnSpeciesCommonNameDe = 'common_name_de';
  static const String columnSpeciesCommonNameEn = 'common_name_en';
  static const String columnSpeciesCommonNameFr = 'common_name_fr';
  static const String columnSpeciesCommonNameEs = 'common_name_es';
  static const String columnSpeciesMaxLengthCm = 'max_length_cm';
  static const String columnSpeciesDepthMinM = 'depth_min_m';
  static const String columnSpeciesDepthMaxM = 'depth_max_m';
  static const String columnSpeciesHabitat = 'habitat';
  static const String columnSpeciesVulnerability = 'vulnerability';
  static const String columnSpeciesDangerousToHumans = 'dangerous_to_humans';
  static const String columnSpeciesFisheriesImportance = 'fisheries_importance';
  static const String columnSpeciesLongevityYears = 'longevity_years';
  static const String columnSpeciesBodyShape = 'body_shape';
  static const String columnSpeciesTrophicLevelFood = 'trophic_level_food';
  static const String columnSpeciesStatus = 'status';
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
  static const String columnFamilyCommonNameFr = 'common_name_fr';
  static const String columnFamilyCommonNameEs = 'common_name_es';
  static const String columnFamilyOrderId = '"order"'; // FK zu Orders

  static const String ordersTableName = 'orders';
  static const String ordersAlias = 'o';
  static const String columnOrderId = 'id';
  static const String columnOrderName = 'name';
  static const String columnOrderCommonNameDe = 'common_name_de';
  static const String columnOrderCommonNameEn = 'common_name_en';
  static const String columnOrderCommonNameFr = 'common_name_fr';
  static const String columnOrderCommonNameEs = 'common_name_es';
  static const String columnOrderClassId = 'class'; // FK zu Classes

  static const String classesTableName = 'classes';
  static const String classesAlias = 'c';
  static const String columnClassId = 'id';
  static const String columnClassName = 'name';
  static const String columnClassCommonName = 'common_name';
  static const String columnClassBodyShape = 'body_shape';
  static const String columnClassSuperClass = 'super_class';

  static const String picturesTableName = 'pictures';
  static const String columnPictureSpeciesId = 'species';
  static const String columnPictureIsUsable = 'is_usable';
  static const String taxonomyTraitsTableName = 'taxonomy_traits';
  static const String taxonomyDistributionRegionsTableName =
      'taxonomy_distribution_regions';

  static const String _selectClause =
      '''
      $speciesAlias.$columnSpeciesExternalSource AS ${speciesAlias}_$columnSpeciesExternalSource,
      $speciesAlias.$columnSpeciesExternalId AS ${speciesAlias}_$columnSpeciesExternalId,
      $speciesAlias.$columnSpeciesId AS ${speciesAlias}_$columnSpeciesId,
      $speciesAlias.$columnSpeciesName AS ${speciesAlias}_$columnSpeciesName,
      (SELECT GROUP_CONCAT(name, ';') FROM (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $speciesAlias.$columnSpeciesId AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 20) sub) AS ${speciesAlias}_$columnSpeciesCommonNameDe,
      (SELECT GROUP_CONCAT(name, ';') FROM (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $speciesAlias.$columnSpeciesId AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 20) sub) AS ${speciesAlias}_$columnSpeciesCommonNameEn,
      (SELECT GROUP_CONCAT(name, ';') FROM (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $speciesAlias.$columnSpeciesId AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 20) sub) AS ${speciesAlias}_$columnSpeciesCommonNameFr,
      (SELECT GROUP_CONCAT(name, ';') FROM (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $speciesAlias.$columnSpeciesId AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 20) sub) AS ${speciesAlias}_$columnSpeciesCommonNameEs,
      $speciesAlias.$columnSpeciesMaxLengthCm AS ${speciesAlias}_$columnSpeciesMaxLengthCm,
      $speciesAlias.$columnSpeciesDepthMinM AS ${speciesAlias}_$columnSpeciesDepthMinM,
      $speciesAlias.$columnSpeciesDepthMaxM AS ${speciesAlias}_$columnSpeciesDepthMaxM,
      $speciesAlias.$columnSpeciesHabitat AS ${speciesAlias}_$columnSpeciesHabitat,
      $speciesAlias.$columnSpeciesVulnerability AS ${speciesAlias}_$columnSpeciesVulnerability,
      $speciesAlias.$columnSpeciesDangerousToHumans AS ${speciesAlias}_$columnSpeciesDangerousToHumans,
      $speciesAlias.$columnSpeciesFisheriesImportance AS ${speciesAlias}_$columnSpeciesFisheriesImportance,
      $speciesAlias.$columnSpeciesLongevityYears AS ${speciesAlias}_$columnSpeciesLongevityYears,
      $speciesAlias.$columnSpeciesBodyShape AS ${speciesAlias}_$columnSpeciesBodyShape,
      $speciesAlias.$columnSpeciesTrophicLevelFood AS ${speciesAlias}_$columnSpeciesTrophicLevelFood,
      $speciesAlias.$columnSpeciesStatus AS ${speciesAlias}_$columnSpeciesStatus,

      $generaAlias.$columnGenusId AS ${generaAlias}_$columnGenusId,
      $generaAlias.$columnGenusName AS ${generaAlias}_$columnGenusName,
      (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $generaAlias.$columnGenusId AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS ${generaAlias}_$columnGenusCommonName,
      $generaAlias.$columnGenusSubFamily AS ${generaAlias}_$columnGenusSubFamily,

      $familiesAlias.$columnFamilyId AS ${familiesAlias}_$columnFamilyId,
      $familiesAlias.$columnFamilyName AS ${familiesAlias}_$columnFamilyName,
      (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $familiesAlias.$columnFamilyId AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS ${familiesAlias}_$columnFamilyCommonNameDe,
      (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $familiesAlias.$columnFamilyId AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS ${familiesAlias}_$columnFamilyCommonNameEn,
      (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $familiesAlias.$columnFamilyId AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS ${familiesAlias}_$columnFamilyCommonNameFr,
      (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $familiesAlias.$columnFamilyId AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS ${familiesAlias}_$columnFamilyCommonNameEs,

      $ordersAlias.$columnOrderId AS ${ordersAlias}_$columnOrderId,
      $ordersAlias.$columnOrderName AS ${ordersAlias}_$columnOrderName,
      (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $ordersAlias.$columnOrderId AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS ${ordersAlias}_$columnOrderCommonNameDe,
      (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $ordersAlias.$columnOrderId AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS ${ordersAlias}_$columnOrderCommonNameEn,
      (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $ordersAlias.$columnOrderId AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS ${ordersAlias}_$columnOrderCommonNameFr,
      (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $ordersAlias.$columnOrderId AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS ${ordersAlias}_$columnOrderCommonNameEs,

      $classesAlias.$columnClassId AS ${classesAlias}_$columnClassId,
      $classesAlias.$columnClassName AS ${classesAlias}_$columnClassName,
      (SELECT cn.name FROM common_names cn WHERE cn.entity_id = $classesAlias.$columnClassId AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS ${classesAlias}_$columnClassCommonName,
      $classesAlias.$columnClassBodyShape AS ${classesAlias}_$columnClassBodyShape,
      $classesAlias.$columnClassSuperClass AS ${classesAlias}_$columnClassSuperClass
  ''';

  static const String _joinClause =
      '''
    FROM $speciesTableName AS $speciesAlias
    JOIN $generaTableName AS $generaAlias 
      ON $speciesAlias.$columnSpeciesGenusId = $generaAlias.$columnGenusId
    JOIN $familiesTableName AS $familiesAlias 
      ON $generaAlias.$columnGenusFamilyId = $familiesAlias.$columnFamilyId
    JOIN $ordersTableName AS $ordersAlias 
      ON $familiesAlias.$columnFamilyOrderId = $ordersAlias.$columnOrderId
    JOIN $classesTableName AS $classesAlias 
      ON $ordersAlias.$columnOrderClassId = $classesAlias.$columnClassId
  ''';

  static const String _groupClause =
      '''
    GROUP BY
      $speciesAlias.$columnSpeciesId,
      $speciesAlias.$columnSpeciesExternalSource,
      $speciesAlias.$columnSpeciesExternalId,
      $speciesAlias.$columnSpeciesName,
      $speciesAlias.$columnSpeciesMaxLengthCm,
      $speciesAlias.$columnSpeciesDepthMinM,
      $speciesAlias.$columnSpeciesDepthMaxM,
      $speciesAlias.$columnSpeciesHabitat,
      $speciesAlias.$columnSpeciesVulnerability,
      $speciesAlias.$columnSpeciesDangerousToHumans,
      $speciesAlias.$columnSpeciesFisheriesImportance,
      $speciesAlias.$columnSpeciesLongevityYears,
      $speciesAlias.$columnSpeciesBodyShape,
      $speciesAlias.$columnSpeciesTrophicLevelFood,
      $speciesAlias.$columnSpeciesStatus,
      $generaAlias.$columnGenusId,
      $generaAlias.$columnGenusName,
      $generaAlias.$columnGenusSubFamily,
      $familiesAlias.$columnFamilyId,
      $familiesAlias.$columnFamilyName,
      $ordersAlias.$columnOrderId,
      $ordersAlias.$columnOrderName,
      $classesAlias.$columnClassId,
      $classesAlias.$columnClassName,
      $classesAlias.$columnClassBodyShape,
      $classesAlias.$columnClassSuperClass
  ''';

  final Database? _injectedDb;
  final Database? _injectedUserDb;

  SpeciesRepository({Database? database, Database? userDatabase})
    : _injectedDb = database,
      _injectedUserDb = userDatabase;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.referenceDb;

  Future<Database?> get _userDatabase async {
    if (_injectedDb != null && _injectedUserDb == null) {
      return null;
    }
    return _injectedUserDb ?? await DatabaseHelper.userDb;
  }

  Future<Species?> getSpeciesById(String id) async {
    final db = await _database;
    final result = await db.rawQuery(
      '''
    SELECT $_selectClause
    $_joinClause
    WHERE $speciesAlias.$columnSpeciesId = ?
    $_groupClause
    LIMIT 1
  ''',
      [id],
    );

    if (result.isEmpty) {
      return null;
    }

    final speciesMap = result.first;
    final pictures = await _getPicturesForSpecies([id]);
    final traitsBySpecies = await _loadSpeciesTraits({id});
    final nativeRegionsBySpecies = await _loadSpeciesNativeRegions({id});

    final importedCommonNames = await _loadImportedSpeciesCommonNames({id});
    final importedClassificationCommonNames =
        await _loadImportedClassificationCommonNames([speciesMap]);

    return _mapToSpecies(
      speciesMap,
      pictures[id] ?? [],
      traitsBySpecies[id] ?? const [],
      nativeRegionsBySpecies[id] ?? const [],
      importedCommonNames[id] ?? const {},
      importedClassificationCommonNames,
    );
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

      final whereClauses = List.generate(
        chunk.length,
        (_) => "$speciesAlias.$columnSpeciesId = ?",
      );
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

      final chunkSpecies = result.map(
        (map) => _mapToSpecies(map, [], const [], const [], const {}, const {}),
      );
      allSpecies.addAll(chunkSpecies);
    }

    // Fetch all pictures in bulk
    final allPictureMap = await _getPicturesForSpecies(
      allSpecies.map((s) => s.id).toList(),
    );
    final speciesIds = allSpecies.map((s) => s.id).toSet();
    final traitsBySpecies = await _loadSpeciesTraits(speciesIds);
    final nativeRegionsBySpecies = await _loadSpeciesNativeRegions(speciesIds);
    final importedCommonNames = await _loadImportedSpeciesCommonNames(
      speciesIds,
    );
    final resultMaps = await _loadSpeciesRowsByIds(speciesIds);
    final importedClassificationCommonNames =
        await _loadImportedClassificationCommonNames(resultMaps);
    final mapsBySpeciesId = <String, Map<String, dynamic>>{
      for (final map in resultMaps)
        map['${speciesAlias}_$columnSpeciesId'] as String: map,
    };

    // Assign mapped pictures to correct species items
    final Set<Species> completeSpecies = {};
    for (var s in allSpecies) {
      completeSpecies.add(
        Species(
          s.id,
          s.externalId,
          s.externalSource,
          s.scientificName,
          _mergeCommonNames(
            s.commonNames,
            importedCommonNames[s.id] ?? const {},
          ),
          _mapToClassification(
            mapsBySpeciesId[s.id]!,
            importedClassificationCommonNames,
          ),
          allPictureMap[s.id] ?? [],
          maxLengthCm: s.maxLengthCm,
          depthMinM: s.depthMinM,
          depthMaxM: s.depthMaxM,
          habitat: s.habitat,
          habitatTag: s.habitatTag,
          conservation: s.conservation,
          dangerousToHumans: s.dangerousToHumans,
          fisheriesImportance: s.fisheriesImportance,
          longevityYears: s.longevityYears,
          bodyShape: s.bodyShape,
          trophicLevelFood: s.trophicLevelFood,
          traits: traitsBySpecies[s.id] ?? s.traits,
          nativeRegions: nativeRegionsBySpecies[s.id] ?? s.nativeRegions,
          status: s.status,
        ),
      );
    }

    return completeSpecies;
  }

  Future<Set<String>> getSpeciesIdsByScientificNames(
    List<(String, String)> scientificNames,
  ) async {
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
          .map(
            (_) =>
                '($generaAlias.$columnGenusName = ? AND $speciesAlias.$columnSpeciesName = ?)',
          )
          .join(' OR ');

      final arguments = chunk
          .expand((record) => [record.$1, record.$2])
          .toList();

      final dbResult = await db.rawQuery('''
      SELECT DISTINCT $speciesAlias.$columnSpeciesId
      FROM $speciesTableName AS $speciesAlias
      JOIN $generaTableName AS $generaAlias ON $speciesAlias.$columnSpeciesGenusId = $generaAlias.$columnGenusId
      WHERE ($whereClause) AND $speciesAlias.$columnSpeciesStatus = 'active'
    ''', arguments);

      allSpeciesIds.addAll(
        dbResult.map((result) => result[columnSpeciesId] as String),
      );
    }

    return allSpeciesIds;
  }

  /// Resolves full scientific names (e.g. "Genus species") to species IDs.
  Future<Set<String>> getSpeciesIdsByFullNames(List<String> names) async {
    final List<(String, String)> parsedNames = names
        .map((name) {
          final parts = name.trim().split(' ');
          if (parts.length < 2) return (name, '');
          return (parts[0], parts[1]);
        })
        .where((name) => name.$1.isNotEmpty && name.$2.isNotEmpty)
        .toList();

    return getSpeciesIdsByScientificNames(parsedNames);
  }

  Species _mapToSpecies(
    Map<String, dynamic> map,
    List<Picture> pictures,
    List<HabitatTag> traits,
    List<SpeciesNativeRegion> nativeRegions,
    Map<String, String> importedCommonNames,
    Map<String, Map<String, String>> importedClassificationCommonNames,
  ) {
    final source =
        map['${speciesAlias}_$columnSpeciesExternalSource'] as String;
    final extId = map['${speciesAlias}_$columnSpeciesExternalId'] as String;

    return Species(
      map['${speciesAlias}_$columnSpeciesId'] as String,
      extId,
      source,
      map['${speciesAlias}_$columnSpeciesName'] as String,
      _mergeCommonNames({
        Language.de:
            map['${speciesAlias}_$columnSpeciesCommonNameDe'] as String? ?? '',
        Language.en:
            map['${speciesAlias}_$columnSpeciesCommonNameEn'] as String? ?? '',
        Language.fr:
            map['${speciesAlias}_$columnSpeciesCommonNameFr'] as String? ?? '',
        Language.es:
            map['${speciesAlias}_$columnSpeciesCommonNameEs'] as String? ?? '',
      }, importedCommonNames),
      _mapToClassification(map, importedClassificationCommonNames),
      pictures,
      maxLengthCm: _parseLengthCm(map['${speciesAlias}_$columnSpeciesMaxLengthCm']),
      depthMinM: _parseDepthM(map['${speciesAlias}_$columnSpeciesDepthMinM']),
      depthMaxM: _parseDepthM(map['${speciesAlias}_$columnSpeciesDepthMaxM']),
      habitat: _formatHabitat(map['${speciesAlias}_$columnSpeciesHabitat']),
      habitatTag: HabitatTag.fromRawHabitat(
        map['${speciesAlias}_$columnSpeciesHabitat'] as String? ?? '',
      ),
      conservation: _parseVulnerability(
        map['${speciesAlias}_$columnSpeciesVulnerability'],
      ),
      dangerousToHumansRaw: _formatTextFact(
        map['${speciesAlias}_$columnSpeciesDangerousToHumans'],
      ),
      dangerousToHumans: _parseHumanRisk(
        map['${speciesAlias}_$columnSpeciesDangerousToHumans'],
      ),
      fisheriesImportance: _parseFishingImportance(
        map['${speciesAlias}_$columnSpeciesFisheriesImportance'],
      ),
      longevityYears: _parseYears(
        map['${speciesAlias}_$columnSpeciesLongevityYears'],
      ),
      bodyShape: _parseBodyForm(map['${speciesAlias}_$columnSpeciesBodyShape']),
      trophicLevelFood: _parseTrophicLevel(
        map['${speciesAlias}_$columnSpeciesTrophicLevelFood'],
      ),
      traits: traits,
      nativeRegions: nativeRegions,
      status: SpeciesStatus.fromRaw(
        map['${speciesAlias}_$columnSpeciesStatus'] as String?,
      ),
    );
  }

  double? _parseLengthCm(Object? rawLengthCm) {
    return switch (rawLengthCm) {
      null => null,
      num value => value.toDouble(),
      String value => double.tryParse(value.trim()),
      _ => null,
    };
  }

  double? _parseDepthM(Object? rawDepthM) {
    return switch (rawDepthM) {
      null => null,
      num value => value.toDouble(),
      String value => double.tryParse(value.trim()),
      _ => null,
    };
  }

  String? _formatHabitat(Object? rawHabitat) {
    final habitat = (rawHabitat as String?)?.trim();
    if (habitat == null || habitat.isEmpty) return null;
    return habitat[0].toUpperCase() + habitat.substring(1);
  }

  BodyForm? _parseBodyForm(Object? rawBodyForm) {
    final value = _nullableTrimmed(rawBodyForm);
    if (value == null) return null;
    return BodyForm.fromRaw(value);
  }

  FishingImportance? _parseFishingImportance(Object? rawFishingImportance) {
    final value = _nullableTrimmed(rawFishingImportance);
    if (value == null) return null;
    return FishingImportance.fromRaw(value);
  }

  HumanRisk? _parseHumanRisk(Object? rawHumanRisk) {
    final value = _nullableTrimmed(rawHumanRisk);
    if (value == null) return null;
    return HumanRisk.fromRaw(value);
  }

  double? _parseVulnerability(Object? rawVulnerability) {
    return _parseNum(rawVulnerability)?.toDouble();
  }

  String? _formatTextFact(Object? rawValue) {
    return _nullableTrimmed(rawValue);
  }

  double? _parseYears(Object? rawYears) {
    return _parseNum(rawYears)?.toDouble();
  }

  double? _parseTrophicLevel(Object? rawValue) {
    return _parseNum(rawValue)?.toDouble();
  }

  String? _nullableTrimmed(Object? rawValue) {
    final value = (rawValue as String?)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  num? _parseNum(Object? rawValue) {
    return switch (rawValue) {
      null => null,
      num value => value,
      String value => num.tryParse(value.trim()),
      _ => null,
    };
  }

  Classification _mapToClassification(
    Map<String, dynamic> map,
    Map<String, Map<String, String>> importedClassificationCommonNames,
  ) {
    final genusKey = _taxonomyEntityKey(
      'genus',
      map['${generaAlias}_$columnGenusName'] as String,
    );
    final familyKey = _taxonomyEntityKey(
      'family',
      map['${familiesAlias}_$columnFamilyName'] as String,
    );
    final orderKey = _taxonomyEntityKey(
      'order',
      map['${ordersAlias}_$columnOrderName'] as String,
    );
    final classKey = _taxonomyEntityKey(
      'class',
      map['${classesAlias}_$columnClassName'] as String,
    );

    return Classification(
      map['${generaAlias}_$columnGenusName'] as String,
      _mergeCommonNames({
        Language.de:
            map['${generaAlias}_$columnGenusCommonName'] as String? ?? '',
      }, importedClassificationCommonNames[genusKey] ?? const {}),
      map['${generaAlias}_$columnGenusSubFamily'] as String?,
      map['${familiesAlias}_$columnFamilyName'] as String,
      _mergeCommonNames({
        Language.de:
            map['${familiesAlias}_$columnFamilyCommonNameDe'] as String? ?? '',
        Language.en:
            map['${familiesAlias}_$columnFamilyCommonNameEn'] as String? ?? '',
        Language.fr:
            map['${familiesAlias}_$columnFamilyCommonNameFr'] as String? ?? '',
        Language.es:
            map['${familiesAlias}_$columnFamilyCommonNameEs'] as String? ?? '',
      }, importedClassificationCommonNames[familyKey] ?? const {}),
      map['${ordersAlias}_$columnOrderName'] as String,
      _mergeCommonNames({
        Language.de:
            map['${ordersAlias}_$columnOrderCommonNameDe'] as String? ?? '',
        Language.en:
            map['${ordersAlias}_$columnOrderCommonNameEn'] as String? ?? '',
        Language.fr:
            map['${ordersAlias}_$columnOrderCommonNameFr'] as String? ?? '',
        Language.es:
            map['${ordersAlias}_$columnOrderCommonNameEs'] as String? ?? '',
      }, importedClassificationCommonNames[orderKey] ?? const {}),
      map['${classesAlias}_$columnClassName'] as String,
      _mergeCommonNames({
        Language.de:
            map['${classesAlias}_$columnClassCommonName'] as String? ?? '',
      }, importedClassificationCommonNames[classKey] ?? const {}),
      map['${classesAlias}_$columnClassSuperClass'] as String?,
    );
  }

  Future<Map<String, List<Picture>>> _getPicturesForSpecies(
    List<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) return {};

    final db = await _database;
    final Map<String, List<Picture>> picturesBySpecies = {
      for (var id in speciesIds) id: [],
    };

    const int chunkSize = 900;
    for (var i = 0; i < speciesIds.length; i += chunkSize) {
      final chunk = speciesIds.skip(i).take(chunkSize).toList();
      final whereClause = List.filled(
        chunk.length,
        '$columnPictureSpeciesId = ?',
      ).join(' OR ');

      final results = await db.query(
        picturesTableName,
        where: '($whereClause) AND $columnPictureIsUsable = 1',
        whereArgs: chunk,
      );

      for (var row in results) {
        final pic = Picture.fromMap(row);
        picturesBySpecies[pic.species]?.add(pic);
      }
    }

    return picturesBySpecies;
  }

  Future<Map<String, List<HabitatTag>>> _loadSpeciesTraits(
    Set<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) return {};

    final db = await _database;
    final traitsBySpecies = <String, List<HabitatTag>>{};
    const chunkSize = 900;
    final idList = speciesIds.toList();

    for (var i = 0; i < idList.length; i += chunkSize) {
      final chunk = idList.skip(i).take(chunkSize).toList();
      final whereClause = List.filled(
        chunk.length,
        'entity_id = ?',
      ).join(' OR ');
      final rows = await db.query(
        taxonomyTraitsTableName,
        columns: ['entity_id', 'trait_key'],
        where:
            'entity_type = ? AND ($whereClause) AND COALESCE(trait_value_bool, 0) = 1',
        whereArgs: ['species', ...chunk],
        orderBy: 'trait_key',
      );

      for (final row in rows) {
        final speciesId = row['entity_id'] as String;
        final traitKey = row['trait_key'] as String? ?? '';
        if (traitKey.isEmpty) continue;
        final tag = HabitatTag.fromTraitKey(traitKey);
        if (tag == null) continue;
        final tags = traitsBySpecies.putIfAbsent(speciesId, () => []);
        if (!tags.contains(tag)) {
          tags.add(tag);
        }
      }
    }

    return traitsBySpecies;
  }

  Future<Map<String, List<SpeciesNativeRegion>>> _loadSpeciesNativeRegions(
    Set<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) return {};

    final db = await _database;
    final regionsBySpecies = <String, List<SpeciesNativeRegion>>{};
    const chunkSize = 900;
    final idList = speciesIds.toList();

    for (var i = 0; i < idList.length; i += chunkSize) {
      final chunk = idList.skip(i).take(chunkSize).toList();
      final whereClause = List.filled(
        chunk.length,
        'entity_id = ?',
      ).join(' OR ');
      final rows = await db.query(
        taxonomyDistributionRegionsTableName,
        columns: [
          'entity_id',
          'region_scope',
          'region_label',
          'presence_status',
          'establishment_status',
          'abundance',
          'importance',
          'threatened_flag',
          'comment',
        ],
        where:
            'entity_type = ? AND ($whereClause) AND (establishment_status IS NULL OR TRIM(establishment_status) = \'\' OR lower(establishment_status) LIKE ?)',
        whereArgs: ['species', ...chunk, '%native%'],
        orderBy: 'region_scope, region_label',
      );

      for (final row in rows) {
        final speciesId = row['entity_id'] as String;
        final region = SpeciesNativeRegion(
          scope: row['region_scope'] as String? ?? 'region',
          label: resolveCountryRegionLabel(
            row['region_label'] as String? ?? '',
          ),
          presenceStatus: _nullableTrimmed(row['presence_status']),
          establishmentStatus: _nullableTrimmed(row['establishment_status']),
          abundance: _nullableTrimmed(row['abundance']),
          importance: _nullableTrimmed(row['importance']),
          isThreatened: _parseNum(row['threatened_flag']) == 1,
          comment: _nullableTrimmed(row['comment']),
        );
        if (region.label.isEmpty) continue;
        regionsBySpecies.putIfAbsent(speciesId, () => []).add(region);
      }
    }

    return regionsBySpecies;
  }

  Future<Map<String, Map<String, String>>> _loadImportedSpeciesCommonNames(
    Set<String> speciesIds,
  ) async {
    final userDb = await _userDatabase;
    if (userDb == null || speciesIds.isEmpty) return {};

    final namesBySpecies = <String, Map<String, String>>{};
    const int chunkSize = 900;

    for (var i = 0; i < speciesIds.length; i += chunkSize) {
      final chunk = speciesIds.skip(i).take(chunkSize).toList();
      final whereClause = List.filled(
        chunk.length,
        'entity_key = ?',
      ).join(' OR ');

      final stopwatch = Stopwatch()..start();
      final rows = await userDb.query(
        'runtime_common_names',
        columns: ['entity_key', 'language_code', 'names'],
        where: whereClause,
        whereArgs: chunk.map((speciesId) => 'species:$speciesId').toList(),
      );
      stopwatch.stop();
      _logDebug(
        'Species repo: imported species common names '
        '(chunk=${chunk.length}, rows=${rows.length}, '
        '${stopwatch.elapsedMilliseconds}ms)',
      );

      for (final row in rows) {
        final entityKey = row['entity_key'] as String;
        final speciesId = entityKey.substring('species:'.length);
        final languageCode = row['language_code'] as String;
        final names = row['names'] as String? ?? '';
        if (names.trim().isEmpty) continue;
        namesBySpecies.putIfAbsent(speciesId, () => {})[languageCode] = names;
      }
    }

    return namesBySpecies;
  }

  Future<List<Map<String, dynamic>>> _loadSpeciesRowsByIds(
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return [];

    final db = await _database;
    final maps = <Map<String, dynamic>>[];
    const chunkSize = 900;
    final idList = ids.toList();

    for (var i = 0; i < idList.length; i += chunkSize) {
      final chunk = idList.skip(i).take(chunkSize).toList();
      final whereClauses = List.generate(
        chunk.length,
        (_) => "$speciesAlias.$columnSpeciesId = ?",
      );

      final rows = await db.rawQuery('''
      SELECT $_selectClause
      $_joinClause
      WHERE ${whereClauses.join(' OR ')}
      $_groupClause
    ''', chunk);

      maps.addAll(rows);
    }

    return maps;
  }

  Future<Map<String, Map<String, String>>>
  _loadImportedClassificationCommonNames(
    List<Map<String, dynamic>> maps,
  ) async {
    final userDb = await _userDatabase;
    if (userDb == null || maps.isEmpty) return {};

    final entityKeys = <String>{};
    for (final map in maps) {
      entityKeys.add(
        _taxonomyEntityKey(
          'genus',
          map['${generaAlias}_$columnGenusName'] as String,
        ),
      );
      entityKeys.add(
        _taxonomyEntityKey(
          'family',
          map['${familiesAlias}_$columnFamilyName'] as String,
        ),
      );
      entityKeys.add(
        _taxonomyEntityKey(
          'order',
          map['${ordersAlias}_$columnOrderName'] as String,
        ),
      );
      entityKeys.add(
        _taxonomyEntityKey(
          'class',
          map['${classesAlias}_$columnClassName'] as String,
        ),
      );
    }

    final namesByEntity = <String, Map<String, String>>{};
    const chunkSize = 900;
    final keyList = entityKeys.toList();

    try {
      for (var i = 0; i < keyList.length; i += chunkSize) {
        final chunk = keyList.skip(i).take(chunkSize).toList();
        final whereClause = List.filled(
          chunk.length,
          'entity_key = ?',
        ).join(' OR ');

        final stopwatch = Stopwatch()..start();
        final rows = await userDb.query(
          'runtime_common_names',
          columns: ['entity_key', 'language_code', 'names'],
          where: whereClause,
          whereArgs: chunk,
        );
        stopwatch.stop();
        _logDebug(
          'Species repo: imported classification common names '
          '(chunk=${chunk.length}, rows=${rows.length}, '
          '${stopwatch.elapsedMilliseconds}ms)',
        );

        for (final row in rows) {
          final entityKey = row['entity_key'] as String;
          final languageCode = row['language_code'] as String;
          final names = row['names'] as String? ?? '';
          if (names.trim().isEmpty) continue;
          namesByEntity.putIfAbsent(entityKey, () => {})[languageCode] = names;
        }
      }
    } catch (_) {
      return {};
    }

    return namesByEntity;
  }

  Map<Language, String> _mergeCommonNames(
    Map<Language, String> referenceCommonNames,
    Map<String, String> importedCommonNames,
  ) {
    final merged = <Language, String>{
      for (final language in Language.values)
        language: referenceCommonNames[language] ?? '',
    };

    for (final language in Language.values) {
      final imported = importedCommonNames[language.name];
      if (imported == null || imported.trim().isEmpty) continue;
      merged[language] = _mergeNameStrings(imported, merged[language] ?? '');
    }

    return merged;
  }

  String _mergeNameStrings(String primary, String additional) {
    final mergedNames = <String>[];
    final seen = <String>{};

    for (final source in [primary, additional]) {
      final parts = source
          .split(';')
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty);
      for (final name in parts) {
        final normalized = _normalizeName(name);
        if (normalized.isEmpty || seen.contains(normalized)) continue;
        seen.add(normalized);
        mergedNames.add(name);
      }
    }

    return mergedNames.join(';');
  }

  String _normalizeName(String name) {
    return name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String _taxonomyEntityKey(String rank, String scientificName) {
    return '$rank:${scientificName.trim().toLowerCase()}';
  }

  void _logDebug(String message) {
    if (_enableSpeciesDebugLogging && kDebugMode) {
      debugPrint(message);
    }
  }
}
