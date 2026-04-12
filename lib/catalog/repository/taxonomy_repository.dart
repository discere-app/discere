import 'package:discere/shared/model/language.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:sqflite/sqflite.dart';

import 'package:discere/shared/persistence/database_helper.dart';

class TaxonomyRepository {
  final Database? _injectedDb;
  final Database? _injectedUserDb;

  TaxonomyRepository({Database? database, Database? userDatabase})
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

  Future<TaxonomyDetail> getDetail(SearchResult result) async {
    if (result.id.startsWith('inat:')) {
      return TaxonomyDetail(
        result: result,
        commonNames: result.commonNames,
        classification: const [],
        metrics: const [],
        attributes: const [],
        isReferenceBacked: false,
      );
    }

    final db = await _database;
    final importedCommonNames = await _loadImportedCommonNames(result);
    switch (result.type) {
      case SearchEntityType.genus:
        return _getGenusDetail(db, result, importedCommonNames);
      case SearchEntityType.family:
        return _getFamilyDetail(db, result, importedCommonNames);
      case SearchEntityType.order:
        return _getOrderDetail(db, result, importedCommonNames);
      case SearchEntityType.classType:
        return _getClassDetail(db, result, importedCommonNames);
      case SearchEntityType.species:
        throw ArgumentError(
          'Species details are handled via SpeciesDetailPage.',
        );
    }
  }

  Future<TaxonomyDetail> _getGenusDetail(
    Database db,
    SearchResult result,
    Map<String, String> importedCommonNames,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = g.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS genus_common_name,
        g.subfamily AS genus_subfamily,
        g.body_shape AS genus_body_shape,
        f.name AS family_name,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = f.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS family_common_name_de,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = f.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS family_common_name_en,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = f.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS family_common_name_fr,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = f.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS family_common_name_es,
        o.name AS order_name,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = o.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS order_common_name_de,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = o.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS order_common_name_en,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = o.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS order_common_name_fr,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = o.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS order_common_name_es,
        c.name AS class_name,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = c.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS class_common_name,
        c.super_class AS super_class,
        COUNT(DISTINCT s.id) AS species_count
      FROM genera g
      LEFT JOIN families f ON f.id = g.family
      LEFT JOIN orders o ON o.id = f."order"
      LEFT JOIN classes c ON c.id = o.class
      LEFT JOIN species s ON s.genus = g.id AND s.status = 'active'
      WHERE g.id = ?
      GROUP BY
        g.id,
        g.subfamily,
        g.body_shape,
        f.name,
        o.name,
        c.name,
        c.super_class
      LIMIT 1
    ''',
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: _mergeLocalizedCommonNames(
        _mergedCommonNames(
          result.commonNames,
          row == null
              ? const {}
              : {Language.en: row['genus_common_name'] as String?},
        ),
        importedCommonNames,
      ),
      classification: row == null
          ? const []
          : [
              TaxonomyClassificationEntry(
                label: TaxonomyRankLabel.family,
                scientificName: row['family_name'] as String? ?? '',
                commonName: _localizedName(row, 'family'),
              ),
              TaxonomyClassificationEntry(
                label: TaxonomyRankLabel.order,
                scientificName: row['order_name'] as String? ?? '',
                commonName: _localizedName(row, 'order'),
              ),
              TaxonomyClassificationEntry(
                label: TaxonomyRankLabel.classType,
                scientificName: row['class_name'] as String? ?? '',
                commonName: row['class_common_name'] as String?,
              ),
              if ((row['super_class'] as String?)?.isNotEmpty ?? false)
                TaxonomyClassificationEntry(
                  label: TaxonomyRankLabel.superClass,
                  scientificName: row['super_class'] as String,
                ),
            ].where((entry) => entry.scientificName.isNotEmpty).toList(),
      metrics: row == null
          ? const []
          : [
              TaxonomyMetric(
                type: TaxonomyMetricType.species,
                count: row['species_count'] as int? ?? 0,
              ),
            ],
      attributes: row == null
          ? const []
          : _attributesFromPairs([
              ('subfamily', row['genus_subfamily']),
              ('body_shape', row['genus_body_shape']),
            ]),
      isReferenceBacked: row != null,
    );
  }

  Future<TaxonomyDetail> _getFamilyDetail(
    Database db,
    SearchResult result,
    Map<String, String> importedCommonNames,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = f.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_de,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = f.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = f.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_fr,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = f.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_es,
        f.body_shape,
        f.division,
        o.name AS order_name,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = o.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS order_common_name_de,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = o.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS order_common_name_en,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = o.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS order_common_name_fr,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = o.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS order_common_name_es,
        c.name AS class_name,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = c.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS class_common_name,
        c.super_class AS super_class,
        COUNT(DISTINCT g.id) AS genera_count,
        COUNT(DISTINCT s.id) AS species_count
      FROM families f
      LEFT JOIN orders o ON o.id = f."order"
      LEFT JOIN classes c ON c.id = o.class
      LEFT JOIN genera g ON g.family = f.id
      LEFT JOIN species s ON s.genus = g.id AND s.status = 'active'
      WHERE f.id = ?
      GROUP BY
        f.id,
        f.body_shape,
        f.division,
        o.name,
        c.name,
        c.super_class
      LIMIT 1
    ''',
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: _mergeLocalizedCommonNames(
        _mergedCommonNames(result.commonNames, _localizedMap(row)),
        importedCommonNames,
      ),
      classification: row == null
          ? const []
          : [
              TaxonomyClassificationEntry(
                label: TaxonomyRankLabel.order,
                scientificName: row['order_name'] as String? ?? '',
                commonName: _localizedName(row, 'order'),
              ),
              TaxonomyClassificationEntry(
                label: TaxonomyRankLabel.classType,
                scientificName: row['class_name'] as String? ?? '',
                commonName: row['class_common_name'] as String?,
              ),
              if ((row['super_class'] as String?)?.isNotEmpty ?? false)
                TaxonomyClassificationEntry(
                  label: TaxonomyRankLabel.superClass,
                  scientificName: row['super_class'] as String,
                ),
            ].where((entry) => entry.scientificName.isNotEmpty).toList(),
      metrics: row == null
          ? const []
          : [
              TaxonomyMetric(
                type: TaxonomyMetricType.genera,
                count: row['genera_count'] as int? ?? 0,
              ),
              TaxonomyMetric(
                type: TaxonomyMetricType.species,
                count: row['species_count'] as int? ?? 0,
              ),
            ],
      attributes: row == null
          ? const []
          : _attributesFromPairs([
              ('body_shape', row['body_shape']),
              ('division', row['division']),
            ]),
      isReferenceBacked: row != null,
    );
  }

  Future<TaxonomyDetail> _getOrderDetail(
    Database db,
    SearchResult result,
    Map<String, String> importedCommonNames,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = o.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_de,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = o.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = o.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_fr,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = o.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_es,
        o.sister_order,
        c.name AS class_name,
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = c.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS class_common_name,
        c.super_class AS super_class,
        COUNT(DISTINCT f.id) AS families_count,
        COUNT(DISTINCT g.id) AS genera_count,
        COUNT(DISTINCT s.id) AS species_count
      FROM orders o
      LEFT JOIN classes c ON c.id = o.class
      LEFT JOIN families f ON f."order" = o.id
      LEFT JOIN genera g ON g.family = f.id
      LEFT JOIN species s ON s.genus = g.id AND s.status = 'active'
      WHERE o.id = ?
      GROUP BY
        o.id,
        o.sister_order,
        c.name,
        c.super_class
      LIMIT 1
    ''',
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: _mergeLocalizedCommonNames(
        _mergedCommonNames(result.commonNames, _localizedMap(row)),
        importedCommonNames,
      ),
      classification: row == null
          ? const []
          : [
              TaxonomyClassificationEntry(
                label: TaxonomyRankLabel.classType,
                scientificName: row['class_name'] as String? ?? '',
                commonName: row['class_common_name'] as String?,
              ),
              if ((row['super_class'] as String?)?.isNotEmpty ?? false)
                TaxonomyClassificationEntry(
                  label: TaxonomyRankLabel.superClass,
                  scientificName: row['super_class'] as String,
                ),
            ].where((entry) => entry.scientificName.isNotEmpty).toList(),
      metrics: row == null
          ? const []
          : [
              TaxonomyMetric(
                type: TaxonomyMetricType.families,
                count: row['families_count'] as int? ?? 0,
              ),
              TaxonomyMetric(
                type: TaxonomyMetricType.genera,
                count: row['genera_count'] as int? ?? 0,
              ),
              TaxonomyMetric(
                type: TaxonomyMetricType.species,
                count: row['species_count'] as int? ?? 0,
              ),
            ],
      attributes: row == null
          ? const []
          : _attributesFromPairs([('sister_order', row['sister_order'])]),
      isReferenceBacked: row != null,
    );
  }

  Future<TaxonomyDetail> _getClassDetail(
    Database db,
    SearchResult result,
    Map<String, String> importedCommonNames,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        (SELECT cn.name FROM common_names cn WHERE cn.entity_id = c.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name,
        c.body_shape,
        c.super_class,
        COUNT(DISTINCT o.id) AS orders_count,
        COUNT(DISTINCT f.id) AS families_count,
        COUNT(DISTINCT g.id) AS genera_count,
        COUNT(DISTINCT s.id) AS species_count
      FROM classes c
      LEFT JOIN orders o ON o.class = c.id
      LEFT JOIN families f ON f."order" = o.id
      LEFT JOIN genera g ON g.family = f.id
      LEFT JOIN species s ON s.genus = g.id AND s.status = 'active'
      WHERE c.id = ?
      GROUP BY c.id, c.body_shape, c.super_class
      LIMIT 1
    ''',
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: _mergeLocalizedCommonNames(
        _mergedCommonNames(
          result.commonNames,
          row == null ? const {} : {Language.en: row['common_name'] as String?},
        ),
        importedCommonNames,
      ),
      classification: row == null
          ? const []
          : [
              if ((row['super_class'] as String?)?.isNotEmpty ?? false)
                TaxonomyClassificationEntry(
                  label: TaxonomyRankLabel.superClass,
                  scientificName: row['super_class'] as String,
                ),
            ],
      metrics: row == null
          ? const []
          : [
              TaxonomyMetric(
                type: TaxonomyMetricType.orders,
                count: row['orders_count'] as int? ?? 0,
              ),
              TaxonomyMetric(
                type: TaxonomyMetricType.families,
                count: row['families_count'] as int? ?? 0,
              ),
              TaxonomyMetric(
                type: TaxonomyMetricType.genera,
                count: row['genera_count'] as int? ?? 0,
              ),
              TaxonomyMetric(
                type: TaxonomyMetricType.species,
                count: row['species_count'] as int? ?? 0,
              ),
            ],
      attributes: row == null
          ? const []
          : _attributesFromPairs([('body_shape', row['body_shape'])]),
      isReferenceBacked: row != null,
    );
  }

  Map<Language, String?> _mergedCommonNames(
    Map<Language, String?> base,
    Map<Language, String?> additional,
  ) {
    return {
      Language.en: base[Language.en] ?? additional[Language.en],
      Language.de: base[Language.de] ?? additional[Language.de],
      Language.fr: base[Language.fr] ?? additional[Language.fr],
      Language.es: base[Language.es] ?? additional[Language.es],
    };
  }

  Future<Map<String, String>> _loadImportedCommonNames(
    SearchResult result,
  ) async {
    final userDb = await _userDatabase;
    if (userDb == null) return const {};

    final rows = await userDb.rawQuery(
      '''
      SELECT language_code, GROUP_CONCAT(name, ';') AS names
      FROM (
        SELECT language_code, name
        FROM runtime_common_names
        WHERE entity_key = ?
        ORDER BY language_code,
                 (place_id IS NULL) DESC,
                 COALESCE(position, 999999),
                 COALESCE(place_position, 999999)
      )
      GROUP BY language_code
      ''',
      [_taxonomyEntityKey(_rankFor(result.type), result.name)],
    );

    final namesByLanguage = <String, String>{};
    for (final row in rows) {
      final languageCode = row['language_code'] as String;
      final names = row['names'] as String? ?? '';
      if (names.trim().isEmpty) continue;
      namesByLanguage[languageCode] = names;
    }
    return namesByLanguage;
  }

  Map<Language, String?> _mergeLocalizedCommonNames(
    Map<Language, String?> referenceCommonNames,
    Map<String, String> importedCommonNames,
  ) {
    final merged = <Language, String?>{
      for (final language in Language.values)
        language: referenceCommonNames[language],
    };

    for (final language in Language.values) {
      final imported = importedCommonNames[language.name];
      if (imported == null || imported.trim().isEmpty) continue;
      merged[language] = _mergeNameStrings(imported, merged[language] ?? '');
    }

    return merged;
  }

  Map<Language, String?> _localizedMap(Map<String, Object?>? row) {
    if (row == null) return const {};

    return {
      Language.en: row['common_name_en'] as String?,
      Language.de: row['common_name_de'] as String?,
      Language.fr: row['common_name_fr'] as String?,
      Language.es: row['common_name_es'] as String?,
    };
  }

  String? _localizedName(Map<String, Object?> row, String prefix) {
    for (final language in const [
      Language.en,
      Language.de,
      Language.fr,
      Language.es,
    ]) {
      final value = row['${prefix}_common_name_${language.name}'] as String?;
      if (value != null && value.isNotEmpty) return value;
    }

    return null;
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

  String _rankFor(SearchEntityType type) {
    switch (type) {
      case SearchEntityType.genus:
        return 'genus';
      case SearchEntityType.family:
        return 'family';
      case SearchEntityType.order:
        return 'order';
      case SearchEntityType.classType:
        return 'class';
      case SearchEntityType.species:
        throw ArgumentError('Species are not supported in TaxonomyRepository.');
    }
  }

  List<TaxonomyAttribute> _attributesFromPairs(List<(String, Object?)> pairs) {
    return pairs
        .map((pair) {
          final value = (pair.$2 as String?)?.trim();
          if (value == null || value.isEmpty) return null;
          return TaxonomyAttribute(key: pair.$1, value: value);
        })
        .whereType<TaxonomyAttribute>()
        .toList();
  }
}
