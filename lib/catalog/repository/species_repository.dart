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
import 'package:discere/catalog/model/locale_place_mapping.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/util/logger.dart';

/// Reads species from the reference database and merges user-side enrichments.
///
/// The repository keeps the reference DB as the canonical source of taxonomy,
/// pictures, and baseline common names. User-DB enrichments from iNaturalist
/// are merged on read for species names and higher taxonomy ranks so the rest
/// of the app can continue to consume a single [Species] model.
class SpeciesRepository {
  static final _log = Logger.forType(SpeciesRepository);
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
  static const String scientificNamesTableName = 'species_scientific_names';
  static const String columnScientificNameSpeciesId = 'species_id';
  static const String columnScientificNameNormalizedName = 'normalized_name';
  static const String columnScientificNameIsPreferred = 'is_preferred';
  static const String columnScientificNameSource = 'source';
  static const String taxonomyTraitsTableName = 'taxonomy_traits';
  static const String taxonomyDistributionRegionsTableName =
      'taxonomy_distribution_regions';

  static const String _selectClause =
      '''
      $speciesAlias.$columnSpeciesExternalSource AS ${speciesAlias}_$columnSpeciesExternalSource,
      $speciesAlias.$columnSpeciesExternalId AS ${speciesAlias}_$columnSpeciesExternalId,
      $speciesAlias.$columnSpeciesId AS ${speciesAlias}_$columnSpeciesId,
      $speciesAlias.$columnSpeciesName AS ${speciesAlias}_$columnSpeciesName,
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

  /// Returns [_selectClause] with an optional regional country preference
  /// injected into every `common_names` ORDER BY.
  ///
  /// When [preferredCountry] is non-null (ISO-3166 numeric, e.g. '756'),
  /// names for that country are sorted before global names (`country IS NULL`),
  /// which are still preferred over names from other countries.
  static String _buildSelectClause(String? preferredCountry) {
    if (preferredCountry == null) return _selectClause;
    return _selectClause.replaceAll(
      '(cn.country IS NULL) DESC',
      "(cn.country = '$preferredCountry') DESC, (cn.country IS NULL) DESC",
    );
  }

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
  final LocalePlaceMapping? _localeMapping;

  SpeciesRepository({
    Database? database,
    Database? userDatabase,
    LocalePlaceMapping? localeMapping,
  }) : _injectedDb = database,
       _injectedUserDb = userDatabase,
       _localeMapping = localeMapping;

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
    SELECT ${_buildSelectClause(_localeMapping?.countryCodeNumeric)}
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

    final referenceCommonNames = await _loadReferenceSpeciesCommonNames({id});
    final importedCommonNames = await _loadImportedSpeciesCommonNames({id});
    final importedClassificationCommonNames =
        await _loadImportedClassificationCommonNames([speciesMap]);

    return _mapToSpecies(
      speciesMap,
      pictures[id] ?? [],
      traitsBySpecies[id] ?? const [],
      nativeRegionsBySpecies[id] ?? const [],
      _mergeCommonNames(
        referenceCommonNames[id] ?? const {},
        importedCommonNames[id] ?? const {},
      ),
      importedClassificationCommonNames,
    );
  }

  Future<Set<Species>> getSpecies(Set<String> ids) async {
    if (ids.isEmpty) return {};

    // 1. Load base rows (without common names — those come from batch queries)
    final allRows = <Map<String, dynamic>>[];
    const int chunkSize = 900;
    final idList = ids.toList();
    final db = await _database;

    for (var i = 0; i < idList.length; i += chunkSize) {
      final chunk = idList.skip(i).take(chunkSize).toList();
      final whereString = List.generate(
        chunk.length,
        (_) => "$speciesAlias.$columnSpeciesId = ?",
      ).join(' OR ');

      final result = await db.rawQuery('''
      SELECT ${_buildSelectClause(_localeMapping?.countryCodeNumeric)}
      $_joinClause
      WHERE $whereString
      $_groupClause
      ORDER BY
        $classesAlias.$columnClassName,
        $ordersAlias.$columnOrderName,
        $familiesAlias.$columnFamilyName,
        $generaAlias.$columnGenusName
    ''', chunk);

      allRows.addAll(result);
    }

    if (allRows.isEmpty) return {};

    // 2. Collect IDs from rows
    final speciesIds = allRows
        .map((r) => r['${speciesAlias}_$columnSpeciesId'] as String)
        .toSet();

    // 3. Bulk load all supplementary data
    final allPictureMap = await _getPicturesForSpecies(speciesIds.toList());
    final traitsBySpecies = await _loadSpeciesTraits(speciesIds);
    final nativeRegionsBySpecies = await _loadSpeciesNativeRegions(speciesIds);
    final referenceCommonNames = await _loadReferenceSpeciesCommonNames(
      speciesIds,
    );
    final importedCommonNames = await _loadImportedSpeciesCommonNames(
      speciesIds,
    );
    final importedClassificationCommonNames =
        await _loadImportedClassificationCommonNames(allRows);

    // 4. Create complete Species objects in one pass
    return allRows.map((map) {
      final id = map['${speciesAlias}_$columnSpeciesId'] as String;
      return _mapToSpecies(
        map,
        allPictureMap[id] ?? [],
        traitsBySpecies[id] ?? const [],
        nativeRegionsBySpecies[id] ?? const [],
        _mergeCommonNames(
          referenceCommonNames[id] ?? const {},
          importedCommonNames[id] ?? const {},
        ),
        importedClassificationCommonNames,
      );
    }).toSet();
  }

  Future<Set<String>> getSpeciesIdsByScientificNames(
    List<(String, String)> scientificNames,
  ) async {
    final fullNames = scientificNames
        .map((record) => '${record.$1} ${record.$2}')
        .toList();
    return getSpeciesIdsByFullNames(fullNames);
  }

  /// Resolves full scientific names (e.g. "Genus species") to species IDs.
  Future<Set<String>> getSpeciesIdsByFullNames(List<String> names) async {
    final resolved = await resolveFullNames(names);
    return resolved.values.toSet();
  }

  /// Like [getSpeciesIdsByFullNames] but returns a map of input name → species ID,
  /// so callers can determine which names were not found.
  Future<Map<String, String>> resolveFullNames(List<String> names) async {
    final normalizedByInput = <String, String>{};
    for (final name in names) {
      final normalized = _normalizeToBinomial(name);
      if (normalized.isEmpty) continue;
      normalizedByInput[name] = normalized;
    }

    if (normalizedByInput.isEmpty) return {};

    final db = await _database;
    final result = <String, String>{};

    const int chunkSize = 400;
    final entries = normalizedByInput.entries.toList();

    for (var i = 0; i < entries.length; i += chunkSize) {
      final chunk = entries.skip(i).take(chunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final arguments = chunk.map((entry) => entry.value).toList();

      final dbResult = await db.rawQuery('''
        SELECT
          ssn.name AS matched_name,
          ssn.$columnScientificNameNormalizedName AS normalized_name,
          ssn.$columnScientificNameSpeciesId AS species_id,
          ssn.name_status AS name_status,
          ssn.$columnScientificNameSource AS source
        FROM $scientificNamesTableName ssn
        JOIN $speciesTableName s
          ON s.$columnSpeciesId = ssn.$columnScientificNameSpeciesId
        WHERE ssn.$columnScientificNameNormalizedName IN ($placeholders)
          AND s.$columnSpeciesStatus = 'active'
        ORDER BY
          ssn.$columnScientificNameNormalizedName,
          ssn.$columnScientificNameIsPreferred DESC,
          CASE ssn.$columnScientificNameSource
            WHEN 'fishbase' THEN 0
            WHEN 'sealifebase' THEN 1
            ELSE 2
          END
      ''', arguments);

      final resolvedNames = <String, String>{};
      final resolvedMetadata =
          <String, ({String matchedName, String nameStatus, String source})>{};
      for (final row in dbResult) {
        final normalizedName = row['normalized_name'] as String;
        final id = row['species_id'] as String;
        resolvedNames.putIfAbsent(normalizedName, () => id);
        resolvedMetadata.putIfAbsent(
          normalizedName,
          () => (
            matchedName: row['matched_name'] as String,
            nameStatus: row['name_status'] as String,
            source: row['source'] as String,
          ),
        );
      }

      for (final entry in chunk) {
        final id = resolvedNames[entry.value];
        if (id != null) {
          result[entry.key] = id;
          final metadata = resolvedMetadata[entry.value];
          if (metadata != null) {
            _logDebug(
              'Species lookup: "${entry.key}" -> ${metadata.matchedName} '
              '[status=${metadata.nameStatus}, source=${metadata.source}, id=$id]',
            );
          }
        } else {
          _logDebug('Species lookup: "${entry.key}" -> unresolved');
        }
      }
    }

    return result;
  }

  String _normalizeToBinomial(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) return '';
    return '${parts[0].toLowerCase()} ${parts[1].toLowerCase()}';
  }

  Species _mapToSpecies(
    Map<String, dynamic> map,
    List<Picture> pictures,
    List<HabitatTag> traits,
    List<SpeciesNativeRegion> nativeRegions,
    Map<Language, List<String>> commonNames,
    Map<String, Map<Language, List<String>>> importedClassificationCommonNames,
  ) {
    final source =
        map['${speciesAlias}_$columnSpeciesExternalSource'] as String;
    final extId = map['${speciesAlias}_$columnSpeciesExternalId'] as String;

    return Species(
      map['${speciesAlias}_$columnSpeciesId'] as String,
      extId,
      source,
      map['${speciesAlias}_$columnSpeciesName'] as String,
      commonNames,
      _mapToClassification(map, importedClassificationCommonNames),
      pictures,
      maxLengthCm: _parseLengthCm(
        map['${speciesAlias}_$columnSpeciesMaxLengthCm'],
      ),
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
    Map<String, Map<Language, List<String>>> importedClassificationCommonNames,
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
        Language.de: _wrapName(map['${generaAlias}_$columnGenusCommonName']),
      }, importedClassificationCommonNames[genusKey] ?? const {}),
      map['${generaAlias}_$columnGenusSubFamily'] as String?,
      map['${familiesAlias}_$columnFamilyName'] as String,
      _mergeCommonNames({
        Language.de: _wrapName(
          map['${familiesAlias}_$columnFamilyCommonNameDe'],
        ),
        Language.en: _wrapName(
          map['${familiesAlias}_$columnFamilyCommonNameEn'],
        ),
        Language.fr: _wrapName(
          map['${familiesAlias}_$columnFamilyCommonNameFr'],
        ),
        Language.es: _wrapName(
          map['${familiesAlias}_$columnFamilyCommonNameEs'],
        ),
      }, importedClassificationCommonNames[familyKey] ?? const {}),
      map['${ordersAlias}_$columnOrderName'] as String,
      _mergeCommonNames({
        Language.de: _wrapName(map['${ordersAlias}_$columnOrderCommonNameDe']),
        Language.en: _wrapName(map['${ordersAlias}_$columnOrderCommonNameEn']),
        Language.fr: _wrapName(map['${ordersAlias}_$columnOrderCommonNameFr']),
        Language.es: _wrapName(map['${ordersAlias}_$columnOrderCommonNameEs']),
      }, importedClassificationCommonNames[orderKey] ?? const {}),
      map['${classesAlias}_$columnClassName'] as String,
      _mergeCommonNames({
        Language.de: _wrapName(map['${classesAlias}_$columnClassCommonName']),
      }, importedClassificationCommonNames[classKey] ?? const {}),
      map['${classesAlias}_$columnClassSuperClass'] as String?,
    );
  }

  List<String> _wrapName(Object? raw) {
    final value = (raw as String?)?.trim();
    return (value != null && value.isNotEmpty) ? [value] : const [];
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

  Future<Map<String, Map<Language, List<String>>>>
  _loadReferenceSpeciesCommonNames(Set<String> speciesIds) async {
    if (speciesIds.isEmpty) return {};

    final db = await _database;
    final result = <String, Map<Language, List<String>>>{};
    const chunkSize = 900;
    final idList = speciesIds.toList();

    final countryPref = _localeMapping?.countryCodeNumeric;
    final countryOrder = countryPref != null
        ? "(cn.country = '$countryPref') DESC, (cn.country IS NULL) DESC"
        : '(cn.country IS NULL) DESC';

    for (var i = 0; i < idList.length; i += chunkSize) {
      final chunk = idList.skip(i).take(chunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final stopwatch = Stopwatch()..start();
      final rows = await db.rawQuery('''
        SELECT cn.entity_id, cn.language, cn.name
        FROM common_names cn
        WHERE cn.entity_id IN ($placeholders)
        ORDER BY cn.entity_id, cn.language,
                 $countryOrder,
                 cn.is_preferred DESC, cn.rank ASC
      ''', chunk);
      stopwatch.stop();
      _logDebug(
        'Species repo: reference species common names '
        '(chunk=${chunk.length}, rows=${rows.length}, '
        '${stopwatch.elapsedMilliseconds}ms)',
      );

      for (final row in rows) {
        final entityId = row['entity_id'] as String;
        final name = (row['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final language = _languageFromCode(row['language'] as String);
        if (language == null) continue;

        final names = result
            .putIfAbsent(entityId, () => {})
            .putIfAbsent(language, () => []);
        if (names.length < 20) {
          names.add(name);
        }
      }
    }

    _deduplicateCommonNameMap(result);
    return result;
  }

  Future<Map<String, Map<Language, List<String>>>>
  _loadImportedSpeciesCommonNames(Set<String> speciesIds) async {
    final userDb = await _userDatabase;
    if (userDb == null || speciesIds.isEmpty) return {};

    final namesBySpecies = <String, Map<Language, List<String>>>{};
    const int chunkSize = 900;

    for (var i = 0; i < speciesIds.length; i += chunkSize) {
      final chunk = speciesIds.skip(i).take(chunkSize).toList();
      final args = chunk.map((speciesId) => 'species:$speciesId').toList();
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final stopwatch = Stopwatch()..start();
      final rows = await userDb.rawQuery('''
        SELECT entity_key, language_code, name
        FROM runtime_common_names
        WHERE entity_key IN ($placeholders)
        ORDER BY entity_key, language_code,
                 ${_runtimePlaceOrderBy()},
                 COALESCE(position, 999999),
                 COALESCE(place_position, 999999)
        ''', args);
      stopwatch.stop();
      _logDebug(
        'Species repo: imported species common names '
        '(chunk=${chunk.length}, rows=${rows.length}, '
        '${stopwatch.elapsedMilliseconds}ms)',
      );

      for (final row in rows) {
        final entityKey = row['entity_key'] as String;
        final speciesId = entityKey.substring('species:'.length);
        final name = (row['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final language = _languageFromCode(row['language_code'] as String);
        if (language == null) continue;

        namesBySpecies
            .putIfAbsent(speciesId, () => {})
            .putIfAbsent(language, () => [])
            .add(name);
      }
    }

    _deduplicateCommonNameMap(namesBySpecies);
    return namesBySpecies;
  }

  Future<Map<String, Map<Language, List<String>>>>
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

    final namesByEntity = <String, Map<Language, List<String>>>{};
    const chunkSize = 900;
    final keyList = entityKeys.toList();

    try {
      for (var i = 0; i < keyList.length; i += chunkSize) {
        final chunk = keyList.skip(i).take(chunkSize).toList();
        final placeholders = List.filled(chunk.length, '?').join(', ');
        final stopwatch = Stopwatch()..start();
        final rows = await userDb.rawQuery('''
          SELECT entity_key, language_code, name
          FROM runtime_common_names
          WHERE entity_key IN ($placeholders)
          ORDER BY entity_key, language_code,
                   (place_id IS NULL) DESC,
                   COALESCE(position, 999999),
                   COALESCE(place_position, 999999)
          ''', chunk);
        stopwatch.stop();
        _logDebug(
          'Species repo: imported classification common names '
          '(chunk=${chunk.length}, rows=${rows.length}, '
          '${stopwatch.elapsedMilliseconds}ms)',
        );

        for (final row in rows) {
          final entityKey = row['entity_key'] as String;
          final name = (row['name'] as String?)?.trim() ?? '';
          if (name.isEmpty) continue;
          final language = _languageFromCode(row['language_code'] as String);
          if (language == null) continue;

          namesByEntity
              .putIfAbsent(entityKey, () => {})
              .putIfAbsent(language, () => [])
              .add(name);
        }
      }
    } catch (_) {
      return {};
    }

    _deduplicateCommonNameMap(namesByEntity);
    return namesByEntity;
  }

  Map<Language, List<String>> _mergeCommonNames(
    Map<Language, List<String>> referenceNames,
    Map<Language, List<String>> importedNames,
  ) {
    final merged = <Language, List<String>>{};

    for (final language in Language.values) {
      final imported = importedNames[language] ?? const [];
      final reference = referenceNames[language] ?? const [];
      merged[language] = _mergeNameLists(imported, reference);
    }

    return merged;
  }

  List<String> _mergeNameLists(List<String> primary, List<String> secondary) {
    if (secondary.isEmpty) return primary;
    if (primary.isEmpty) return secondary;

    final result = <String>[];
    final seen = <String>{};

    for (final name in [...primary, ...secondary]) {
      final normalized = name
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase();
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      result.add(name);
    }

    return result;
  }

  Language? _languageFromCode(String code) {
    for (final language in Language.values) {
      if (language.name == code) return language;
    }
    return null;
  }

  void _deduplicateCommonNameMap(
    Map<String, Map<Language, List<String>>> nameMap,
  ) {
    for (final entityNames in nameMap.values) {
      for (final language in entityNames.keys) {
        final names = entityNames[language]!;
        if (names.length <= 1) continue;
        final seen = <String>{};
        final deduped = <String>[];
        for (final name in names) {
          final normalized = name
              .trim()
              .replaceAll(RegExp(r'\s+'), ' ')
              .toLowerCase();
          if (normalized.isEmpty || seen.contains(normalized)) continue;
          seen.add(normalized);
          deduped.add(name);
        }
        entityNames[language] = deduped;
      }
    }
  }

  String _taxonomyEntityKey(String rank, String scientificName) {
    return '$rank:${scientificName.trim().toLowerCase()}';
  }

  /// ORDER BY fragment for `runtime_common_names` queries.
  ///
  /// When a locale mapping is available, the user's regional place is sorted
  /// first, followed by global names (`place_id IS NULL`).
  String _runtimePlaceOrderBy() {
    final placeId = _localeMapping?.inatPlaceId;
    if (placeId == null) return '(place_id IS NULL) DESC';
    return '(place_id = $placeId) DESC, (place_id IS NULL) DESC';
  }

  void _logDebug(String message) {
    if (_enableSpeciesDebugLogging) {
      _log.debug(message);
    }
  }
}
