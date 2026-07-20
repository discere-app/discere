import 'package:discere/catalog/model/locale_place_mapping.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/repository/locale_aware_common_name_sql.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class TaxonomyRepository {
  final Database? _injectedDb;
  final Database? _injectedUserDb;
  final LocalePlaceMapping? _localeMapping;

  TaxonomyRepository({
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
    Map<Language, List<String>> importedCommonNames,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT
        ${commonNameSubquery(entityAlias: 'g', entityIdColumn: 'id', language: 'en', outputAlias: 'genus_common_name')},
        g.subfamily AS genus_subfamily,
        g.body_shape AS genus_body_shape,
        f.id AS family_id,
        f.name AS family_name,
        ${commonNameSubquery(entityAlias: 'f', entityIdColumn: 'id', language: 'de', outputAlias: 'family_common_name_de')},
        ${commonNameSubquery(entityAlias: 'f', entityIdColumn: 'id', language: 'en', outputAlias: 'family_common_name_en')},
        ${commonNameSubquery(entityAlias: 'f', entityIdColumn: 'id', language: 'fr', outputAlias: 'family_common_name_fr')},
        ${commonNameSubquery(entityAlias: 'f', entityIdColumn: 'id', language: 'es', outputAlias: 'family_common_name_es')},
        o.id AS order_id,
        o.name AS order_name,
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'de', outputAlias: 'order_common_name_de')},
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'en', outputAlias: 'order_common_name_en')},
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'fr', outputAlias: 'order_common_name_fr')},
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'es', outputAlias: 'order_common_name_es')},
        c.id AS class_id,
        c.name AS class_name,
        ${commonNameSubquery(entityAlias: 'c', entityIdColumn: 'id', language: 'en', outputAlias: 'class_common_name')},
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
        f.id,
        f.name,
        o.id,
        o.name,
        c.id,
        c.name,
        c.super_class
      LIMIT 1
    '''),
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
              : {Language.en: _wrapName(row['genus_common_name'] as String?)},
        ),
        importedCommonNames,
      ),
      classification: row == null
          ? const []
          : [
              TaxonomyClassificationEntry(
                label: TaxonomyRankLabel.family,
                id: row['family_id']?.toString(),
                scientificName: row['family_name'] as String? ?? '',
                commonName: _localizedName(row, 'family'),
              ),
              TaxonomyClassificationEntry(
                label: TaxonomyRankLabel.order,
                id: row['order_id']?.toString(),
                scientificName: row['order_name'] as String? ?? '',
                commonName: _localizedName(row, 'order'),
              ),
              TaxonomyClassificationEntry(
                label: TaxonomyRankLabel.classType,
                id: row['class_id']?.toString(),
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
    Map<Language, List<String>> importedCommonNames,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT
        ${commonNameSubquery(entityAlias: 'f', entityIdColumn: 'id', language: 'de', outputAlias: 'common_name_de')},
        ${commonNameSubquery(entityAlias: 'f', entityIdColumn: 'id', language: 'en', outputAlias: 'common_name_en')},
        ${commonNameSubquery(entityAlias: 'f', entityIdColumn: 'id', language: 'fr', outputAlias: 'common_name_fr')},
        ${commonNameSubquery(entityAlias: 'f', entityIdColumn: 'id', language: 'es', outputAlias: 'common_name_es')},
        f.body_shape,
        f.division,
        o.id AS order_id,
        o.name AS order_name,
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'de', outputAlias: 'order_common_name_de')},
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'en', outputAlias: 'order_common_name_en')},
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'fr', outputAlias: 'order_common_name_fr')},
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'es', outputAlias: 'order_common_name_es')},
        c.id AS class_id,
        c.name AS class_name,
        ${commonNameSubquery(entityAlias: 'c', entityIdColumn: 'id', language: 'en', outputAlias: 'class_common_name')},
        c.super_class AS super_class,
        COUNT(DISTINCT CASE WHEN s.id IS NOT NULL THEN g.id END) AS genera_count,
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
        o.id,
        o.name,
        c.id,
        c.name,
        c.super_class
      LIMIT 1
    '''),
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: _mergeLocalizedCommonNames(
        _mergedCommonNames(result.commonNames, _localizedListMap(row)),
        importedCommonNames,
      ),
      classification: row == null
          ? const []
          : [
              TaxonomyClassificationEntry(
                label: TaxonomyRankLabel.order,
                id: row['order_id']?.toString(),
                scientificName: row['order_name'] as String? ?? '',
                commonName: _localizedName(row, 'order'),
              ),
              TaxonomyClassificationEntry(
                label: TaxonomyRankLabel.classType,
                id: row['class_id']?.toString(),
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
    Map<Language, List<String>> importedCommonNames,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'de', outputAlias: 'common_name_de')},
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'en', outputAlias: 'common_name_en')},
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'fr', outputAlias: 'common_name_fr')},
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'es', outputAlias: 'common_name_es')},
        o.sister_order,
        c.id AS class_id,
        c.name AS class_name,
        ${commonNameSubquery(entityAlias: 'c', entityIdColumn: 'id', language: 'en', outputAlias: 'class_common_name')},
        c.super_class AS super_class,
        COUNT(DISTINCT CASE WHEN s.id IS NOT NULL THEN f.id END) AS families_count,
        COUNT(DISTINCT CASE WHEN s.id IS NOT NULL THEN g.id END) AS genera_count,
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
        c.id,
        c.name,
        c.super_class
      LIMIT 1
    '''),
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: _mergeLocalizedCommonNames(
        _mergedCommonNames(result.commonNames, _localizedListMap(row)),
        importedCommonNames,
      ),
      classification: row == null
          ? const []
          : [
              TaxonomyClassificationEntry(
                label: TaxonomyRankLabel.classType,
                id: row['class_id']?.toString(),
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
    Map<Language, List<String>> importedCommonNames,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT
        ${commonNameSubquery(entityAlias: 'c', entityIdColumn: 'id', language: 'en', outputAlias: 'common_name')},
        c.body_shape,
        c.super_class,
        COUNT(DISTINCT CASE WHEN s.id IS NOT NULL THEN o.id END) AS orders_count,
        COUNT(DISTINCT CASE WHEN s.id IS NOT NULL THEN f.id END) AS families_count,
        COUNT(DISTINCT CASE WHEN s.id IS NOT NULL THEN g.id END) AS genera_count,
        COUNT(DISTINCT s.id) AS species_count
      FROM classes c
      LEFT JOIN orders o ON o.class = c.id
      LEFT JOIN families f ON f."order" = o.id
      LEFT JOIN genera g ON g.family = f.id
      LEFT JOIN species s ON s.genus = g.id AND s.status = 'active'
      WHERE c.id = ?
      GROUP BY c.id, c.body_shape, c.super_class
      LIMIT 1
    '''),
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
              : {Language.en: _wrapName(row['common_name'] as String?)},
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

  Map<Language, List<String>> _mergedCommonNames(
    Map<Language, List<String>> base,
    Map<Language, List<String>> additional,
  ) {
    return {
      for (final language in Language.values)
        language: (base[language]?.isNotEmpty ?? false)
            ? base[language]!
            : (additional[language] ?? const []),
    };
  }

  List<String> _wrapName(String? raw) {
    final value = raw?.trim();
    return (value != null && value.isNotEmpty) ? [value] : const [];
  }

  /// Injects a regional country preference into reference-DB `common_names`
  /// ORDER BY clauses. See [withCountryPreference].
  String _countryAwareQuery(String rawQuery) =>
      withCountryPreference(rawQuery, _localeMapping?.countryCodeNumeric);

  /// ORDER BY fragment for `runtime_common_names` queries.
  String _runtimePlaceOrderBy() {
    final placeId = _localeMapping?.inatPlaceId;
    if (placeId == null) return '(place_id IS NULL) DESC';
    return '(place_id = $placeId) DESC, (place_id IS NULL) DESC';
  }

  Future<Map<Language, List<String>>> _loadImportedCommonNames(
    SearchResult result,
  ) async {
    final userDb = await _userDatabase;
    if (userDb == null) return const {};

    final rows = await userDb.rawQuery(
      '''
      SELECT language_code, name
      FROM runtime_common_names
      WHERE entity_key = ?
      ORDER BY language_code,
               ${_runtimePlaceOrderBy()},
               COALESCE(position, 999999),
               COALESCE(place_position, 999999)
      ''',
      [TaxonRank.fromSearchEntityType(result.type).entityKey(result.name)],
    );

    final namesByLanguage = <Language, List<String>>{};
    for (final row in rows) {
      final name = (row['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final language = _languageFromCode(row['language_code'] as String);
      if (language == null) continue;

      namesByLanguage.putIfAbsent(language, () => []).add(name);
    }
    return namesByLanguage;
  }

  Language? _languageFromCode(String code) {
    for (final language in Language.values) {
      if (language.name == code) return language;
    }
    return null;
  }

  Map<Language, List<String>> _mergeLocalizedCommonNames(
    Map<Language, List<String>> referenceCommonNames,
    Map<Language, List<String>> importedCommonNames,
  ) {
    final merged = <Language, List<String>>{};

    for (final language in Language.values) {
      final imported = importedCommonNames[language] ?? const [];
      final reference = referenceCommonNames[language] ?? const [];
      merged[language] = _mergeNameLists(imported, reference);
    }

    return merged;
  }

  Map<Language, List<String>> _localizedListMap(Map<String, Object?>? row) {
    if (row == null) return const {};

    return {
      Language.en: _wrapName(row['common_name_en'] as String?),
      Language.de: _wrapName(row['common_name_de'] as String?),
      Language.fr: _wrapName(row['common_name_fr'] as String?),
      Language.es: _wrapName(row['common_name_es'] as String?),
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

  Future<List<SearchResult>> getChildren(SearchResult parent) async {
    if (parent.id.startsWith('inat:')) return const [];
    final db = await _database;
    switch (parent.type) {
      case SearchEntityType.classType:
        return _queryOrdersForClass(db, parent.id);
      case SearchEntityType.order:
        return _queryFamiliesForOrder(db, parent.id);
      case SearchEntityType.family:
        return _queryGeneraForFamily(db, parent.id);
      case SearchEntityType.genus:
        return _querySpeciesForGenus(db, parent.id);
      case SearchEntityType.species:
        return const [];
    }
  }

  Future<List<SearchResult>> _queryOrdersForClass(
    Database db,
    String classId,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT o.id, o.name,
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'de', outputAlias: 'cn_de')},
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'en', outputAlias: 'cn_en')},
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'fr', outputAlias: 'cn_fr')},
        ${commonNameSubquery(entityAlias: 'o', entityIdColumn: 'id', language: 'es', outputAlias: 'cn_es')}
      FROM orders o
      WHERE o.class = ?
        AND EXISTS (
          SELECT 1 FROM families f
          JOIN genera g ON g.family = f.id
          JOIN species s ON s.genus = g.id AND s.status = 'active'
          WHERE f."order" = o.id
        )
      ORDER BY o.name
      '''),
      [classId],
    );
    return rows
        .map((r) => _rowToSearchResult(r, SearchEntityType.order))
        .toList();
  }

  Future<List<SearchResult>> _queryFamiliesForOrder(
    Database db,
    String orderId,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT f.id, f.name,
        ${commonNameSubquery(entityAlias: 'f', entityIdColumn: 'id', language: 'de', outputAlias: 'cn_de')},
        ${commonNameSubquery(entityAlias: 'f', entityIdColumn: 'id', language: 'en', outputAlias: 'cn_en')},
        ${commonNameSubquery(entityAlias: 'f', entityIdColumn: 'id', language: 'fr', outputAlias: 'cn_fr')},
        ${commonNameSubquery(entityAlias: 'f', entityIdColumn: 'id', language: 'es', outputAlias: 'cn_es')}
      FROM families f
      WHERE f."order" = ?
        AND EXISTS (
          SELECT 1 FROM genera g
          JOIN species s ON s.genus = g.id AND s.status = 'active'
          WHERE g.family = f.id
        )
      ORDER BY f.name
      '''),
      [orderId],
    );
    return rows
        .map((r) => _rowToSearchResult(r, SearchEntityType.family))
        .toList();
  }

  Future<List<SearchResult>> _queryGeneraForFamily(
    Database db,
    String familyId,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT g.id, g.name,
        ${commonNameSubquery(entityAlias: 'g', entityIdColumn: 'id', language: 'de', outputAlias: 'cn_de')},
        ${commonNameSubquery(entityAlias: 'g', entityIdColumn: 'id', language: 'en', outputAlias: 'cn_en')},
        ${commonNameSubquery(entityAlias: 'g', entityIdColumn: 'id', language: 'fr', outputAlias: 'cn_fr')},
        ${commonNameSubquery(entityAlias: 'g', entityIdColumn: 'id', language: 'es', outputAlias: 'cn_es')}
      FROM genera g
      WHERE g.family = ?
        AND EXISTS (SELECT 1 FROM species s WHERE s.genus = g.id AND s.status = 'active')
      ORDER BY g.name
      '''),
      [familyId],
    );
    return rows
        .map((r) => _rowToSearchResult(r, SearchEntityType.genus))
        .toList();
  }

  Future<List<SearchResult>> _querySpeciesForGenus(
    Database db,
    String genusId,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT s.id, g.name || ' ' || s.name AS name,
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'de', outputAlias: 'cn_de')},
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'en', outputAlias: 'cn_en')},
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'fr', outputAlias: 'cn_fr')},
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'es', outputAlias: 'cn_es')}
      FROM species s
      JOIN genera g ON g.id = s.genus
      WHERE s.genus = ? AND s.status = 'active'
      ORDER BY s.name
      '''),
      [genusId],
    );
    return rows
        .map((r) => _rowToSearchResult(r, SearchEntityType.species))
        .toList();
  }

  /// Resolves every active species under [taxon], regardless of how many
  /// taxonomic levels separate them (e.g. a family's species live two levels
  /// down, via its genera). Used for bulk "add to deck" actions, where the
  /// direct children returned by [getChildren] aren't necessarily species.
  Future<List<SearchResult>> getAllSpeciesUnder(SearchResult taxon) async {
    if (taxon.id.startsWith('inat:')) return const [];
    final db = await _database;
    switch (taxon.type) {
      case SearchEntityType.species:
        return [taxon];
      case SearchEntityType.genus:
        return _querySpeciesForGenus(db, taxon.id);
      case SearchEntityType.family:
        return _querySpeciesForFamily(db, taxon.id);
      case SearchEntityType.order:
        return _querySpeciesForOrder(db, taxon.id);
      case SearchEntityType.classType:
        return _querySpeciesForClass(db, taxon.id);
    }
  }

  static const _regionQueryChunkSize = 500;

  /// Distinct country-level region keys any of [speciesIds] are recorded as
  /// occurring in (excludes rows explicitly marked `absent`), for populating
  /// a region filter/picker. Returns raw codes rather than resolved
  /// [RegionOption]s — display-name resolution is locale-dependent
  /// ([resolveCountryRegionLabel]'s `german` flag), so callers resolve it
  /// themselves once they know the current UI language.
  Future<List<String>> getAvailableRegions(Set<String> speciesIds) async {
    if (speciesIds.isEmpty) return const [];
    final db = await _database;
    final ids = speciesIds.toList();
    final regionKeys = <String>{};
    for (var i = 0; i < ids.length; i += _regionQueryChunkSize) {
      final chunk = ids.skip(i).take(_regionQueryChunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        '''
        SELECT DISTINCT region_key FROM taxonomy_distribution_regions
        WHERE entity_type = 'species' AND region_scope = 'country'
          AND entity_id IN ($placeholders)
          AND (presence_status IS NULL OR lower(presence_status) != 'absent')
        ''',
        chunk,
      );
      regionKeys.addAll(rows.map((r) => r['region_key'] as String));
    }
    return regionKeys.toList();
  }

  /// For species present (not `absent`) in any of [regionKeys], returns the
  /// raw abundance strings recorded across those regions, keyed by species
  /// id. A species with no matching row is omitted entirely — callers use
  /// that to filter a species list down to "occurs in one of these regions".
  /// A present species with only empty/unrated rows still gets an (empty)
  /// list entry, since presence itself is what matters for the filter.
  Future<Map<String, List<String>>> getAbundanceRawValuesByRegion(
    Set<String> speciesIds,
    Set<String> regionKeys,
  ) async {
    if (speciesIds.isEmpty || regionKeys.isEmpty) return const {};
    return _queryAbundanceRawValues(speciesIds, regionKeys: regionKeys);
  }

  /// Raw abundance strings for [speciesIds] across every country they're
  /// recorded in (not restricted to a chosen region), keyed by species id —
  /// lets the "filter by frequency" control work before any region has been
  /// selected. Species with no distribution data at all are omitted, same as
  /// [getAbundanceRawValuesByRegion].
  Future<Map<String, List<String>>> getAllAbundanceRawValues(
    Set<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) return const {};
    return _queryAbundanceRawValues(speciesIds);
  }

  Future<Map<String, List<String>>> _queryAbundanceRawValues(
    Set<String> speciesIds, {
    Set<String>? regionKeys,
  }) async {
    final db = await _database;
    final ids = speciesIds.toList();
    final regionPlaceholders = regionKeys == null
        ? null
        : List.filled(regionKeys.length, '?').join(',');
    final result = <String, List<String>>{};
    for (var i = 0; i < ids.length; i += _regionQueryChunkSize) {
      final chunk = ids.skip(i).take(_regionQueryChunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        '''
        SELECT entity_id, abundance FROM taxonomy_distribution_regions
        WHERE entity_type = 'species' AND region_scope = 'country'
          AND entity_id IN ($placeholders)
          ${regionPlaceholders == null ? '' : 'AND region_key IN ($regionPlaceholders)'}
          AND (presence_status IS NULL OR lower(presence_status) != 'absent')
        ''',
        [...chunk, ...?regionKeys],
      );
      for (final row in rows) {
        final speciesId = row['entity_id'] as String;
        final abundance = (row['abundance'] as String?)?.trim() ?? '';
        final values = result.putIfAbsent(speciesId, () => []);
        if (abundance.isNotEmpty) values.add(abundance);
      }
    }
    return result;
  }

  Future<List<SearchResult>> _querySpeciesForFamily(
    Database db,
    String familyId,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT s.id, g.name || ' ' || s.name AS name,
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'de', outputAlias: 'cn_de')},
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'en', outputAlias: 'cn_en')},
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'fr', outputAlias: 'cn_fr')},
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'es', outputAlias: 'cn_es')}
      FROM species s
      JOIN genera g ON g.id = s.genus
      WHERE g.family = ? AND s.status = 'active'
      ORDER BY s.name
      '''),
      [familyId],
    );
    return rows
        .map((r) => _rowToSearchResult(r, SearchEntityType.species))
        .toList();
  }

  Future<List<SearchResult>> _querySpeciesForOrder(
    Database db,
    String orderId,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT s.id, g.name || ' ' || s.name AS name,
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'de', outputAlias: 'cn_de')},
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'en', outputAlias: 'cn_en')},
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'fr', outputAlias: 'cn_fr')},
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'es', outputAlias: 'cn_es')}
      FROM species s
      JOIN genera g ON g.id = s.genus
      JOIN families f ON f.id = g.family
      WHERE f."order" = ? AND s.status = 'active'
      ORDER BY s.name
      '''),
      [orderId],
    );
    return rows
        .map((r) => _rowToSearchResult(r, SearchEntityType.species))
        .toList();
  }

  Future<List<SearchResult>> _querySpeciesForClass(
    Database db,
    String classId,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT s.id, g.name || ' ' || s.name AS name,
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'de', outputAlias: 'cn_de')},
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'en', outputAlias: 'cn_en')},
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'fr', outputAlias: 'cn_fr')},
        ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'es', outputAlias: 'cn_es')}
      FROM species s
      JOIN genera g ON g.id = s.genus
      JOIN families f ON f.id = g.family
      JOIN orders o ON o.id = f."order"
      WHERE o.class = ? AND s.status = 'active'
      ORDER BY s.name
      '''),
      [classId],
    );
    return rows
        .map((r) => _rowToSearchResult(r, SearchEntityType.species))
        .toList();
  }

  SearchResult _rowToSearchResult(
    Map<String, Object?> row,
    SearchEntityType type,
  ) {
    return SearchResult(
      id: row['id'] as String,
      name: row['name'] as String,
      commonNames: {
        Language.de: _wrapName(row['cn_de'] as String?),
        Language.en: _wrapName(row['cn_en'] as String?),
        Language.fr: _wrapName(row['cn_fr'] as String?),
        Language.es: _wrapName(row['cn_es'] as String?),
      },
      type: type,
    );
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
