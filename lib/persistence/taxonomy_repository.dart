import 'package:discere/model/language.dart';
import 'package:discere/model/search/search_result.dart';
import 'package:discere/model/search/taxonomy_detail.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

class TaxonomyRepository {
  final Database? _injectedDb;

  TaxonomyRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.referenceDb;

  Future<TaxonomyDetail> getDetail(SearchResult result) async {
    if (result.id.startsWith('inat:')) {
      return TaxonomyDetail(
        result: result,
        commonNames: result.commonNames,
        classification: const [],
        metrics: const [],
        isReferenceBacked: false,
      );
    }

    final db = await _database;
    switch (result.type) {
      case SearchEntityType.genus:
        return _getGenusDetail(db, result);
      case SearchEntityType.family:
        return _getFamilyDetail(db, result);
      case SearchEntityType.order:
        return _getOrderDetail(db, result);
      case SearchEntityType.classType:
        return _getClassDetail(db, result);
      case SearchEntityType.species:
        throw ArgumentError(
          'Species details are handled via SpeciesDetailPage.',
        );
    }
  }

  Future<TaxonomyDetail> _getGenusDetail(
    Database db,
    SearchResult result,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        g.common_name AS genus_common_name,
        f.name AS family_name,
        f.common_name_de AS family_common_name_de,
        f.common_name_en AS family_common_name_en,
        f.common_name_fr AS family_common_name_fr,
        f.common_name_es AS family_common_name_es,
        o.name AS order_name,
        o.common_name_de AS order_common_name_de,
        o.common_name_en AS order_common_name_en,
        o.common_name_fr AS order_common_name_fr,
        o.common_name_es AS order_common_name_es,
        c.name AS class_name,
        c.common_name AS class_common_name,
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
        g.common_name,
        f.name,
        f.common_name_de,
        f.common_name_en,
        f.common_name_fr,
        f.common_name_es,
        o.name,
        o.common_name_de,
        o.common_name_en,
        o.common_name_fr,
        o.common_name_es,
        c.name,
        c.common_name,
        c.super_class
      LIMIT 1
    ''',
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: _mergedCommonNames(
        result.commonNames,
        row == null
            ? const {}
            : {Language.en: row['genus_common_name'] as String?},
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
      isReferenceBacked: row != null,
    );
  }

  Future<TaxonomyDetail> _getFamilyDetail(
    Database db,
    SearchResult result,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        f.common_name_de,
        f.common_name_en,
        f.common_name_fr,
        f.common_name_es,
        o.name AS order_name,
        o.common_name_de AS order_common_name_de,
        o.common_name_en AS order_common_name_en,
        o.common_name_fr AS order_common_name_fr,
        o.common_name_es AS order_common_name_es,
        c.name AS class_name,
        c.common_name AS class_common_name,
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
        f.common_name_de,
        f.common_name_en,
        f.common_name_fr,
        f.common_name_es,
        o.name,
        o.common_name_de,
        o.common_name_en,
        o.common_name_fr,
        o.common_name_es,
        c.name,
        c.common_name,
        c.super_class
      LIMIT 1
    ''',
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: _mergedCommonNames(result.commonNames, _localizedMap(row)),
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
      isReferenceBacked: row != null,
    );
  }

  Future<TaxonomyDetail> _getOrderDetail(
    Database db,
    SearchResult result,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        o.common_name_de,
        o.common_name_en,
        o.common_name_fr,
        o.common_name_es,
        c.name AS class_name,
        c.common_name AS class_common_name,
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
        o.common_name_de,
        o.common_name_en,
        o.common_name_fr,
        o.common_name_es,
        c.name,
        c.common_name,
        c.super_class
      LIMIT 1
    ''',
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: _mergedCommonNames(result.commonNames, _localizedMap(row)),
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
      isReferenceBacked: row != null,
    );
  }

  Future<TaxonomyDetail> _getClassDetail(
    Database db,
    SearchResult result,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        c.common_name,
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
      GROUP BY c.id, c.common_name, c.super_class
      LIMIT 1
    ''',
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: _mergedCommonNames(
        result.commonNames,
        row == null ? const {} : {Language.en: row['common_name'] as String?},
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
}
