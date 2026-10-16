import 'package:discere/catalog/model/locale_place_mapping.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/repository/common_name_merging.dart';
import 'package:discere/catalog/repository/common_name_repository.dart';
import 'package:discere/catalog/repository/locale_aware_common_name_sql.dart';
import 'package:discere/catalog/repository/taxon_placeholder_sql.dart';
import 'package:discere/catalog/repository/taxonomy_ancestor_sql.dart';
import 'package:discere/catalog/repository/taxonomy_common_name_enricher.dart';
import 'package:discere/catalog/repository/taxonomy_hierarchy_sql.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class TaxonomyRepository {
  final Database? _injectedDb;
  final Database? _injectedUserDb;
  final LocalePlaceMapping? _localeMapping;
  late final _commonNameEnricher = TaxonomyCommonNameEnricher(
    CommonNameRepository(localeMapping: _localeMapping),
    userDatabase: () => _userDatabase,
  );

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
    final placeholders = await TaxonPlaceholderSql.of(db);
    final detail = await switch (result.type) {
      SearchEntityType.genus => _getGenusDetail(db, result, placeholders),
      SearchEntityType.family => _getFamilyDetail(db, result, placeholders),
      SearchEntityType.order => _getOrderDetail(db, result, placeholders),
      SearchEntityType.classType => _getClassDetail(db, result, placeholders),
      SearchEntityType.species => throw ArgumentError(
        'Species details are handled via SpeciesDetailPage.',
      ),
    };
    return _commonNameEnricher.enrichDetail(detail);
  }

  // Each detail query groups by its own taxon's id alone: every join above
  // it is to-one, so the selected ancestor columns are the same on every row
  // of the group, and only the species below are counted across rows.

  Future<TaxonomyDetail> _getGenusDetail(
    Database db,
    SearchResult result,
    TaxonPlaceholderSql placeholders,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT
        ${commonNameSubquery(entityAlias: 'g', entityIdColumn: 'id', language: 'en', outputAlias: 'genus_common_name')},
        g.subfamily AS genus_subfamily,
        g.body_shape AS genus_body_shape,
        ${placeholders.sqlFor('g')} AS ${TaxonPlaceholderSql.column},
        ${ancestorColumnsSql(TaxonomyTable.genus, placeholders)},
        COUNT(DISTINCT s.id) AS species_count
      FROM genera g
      LEFT JOIN families f ON f.id = g.family
      LEFT JOIN orders o ON o.id = f."order"
      LEFT JOIN classes c ON c.id = o.class
      LEFT JOIN species s ON s.genus = g.id AND s.status = 'active'
      WHERE g.id = ?
      GROUP BY g.id
      LIMIT 1
    '''),
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: preferOwnNames(
        result.commonNames,
        row == null
            ? const {}
            : englishNames(row['genus_common_name'] as String?),
      ),
      classification: row == null
          ? const []
          : ancestorEntries(row, TaxonomyTable.genus),
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
      isPlaceholder: TaxonPlaceholderSql.isSet(row),
    );
  }

  Future<TaxonomyDetail> _getFamilyDetail(
    Database db,
    SearchResult result,
    TaxonPlaceholderSql placeholders,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT
        ${localizedCommonNameSubqueries(entityAlias: 'f', entityIdColumn: 'id')},
        f.body_shape,
        f.division,
        ${placeholders.sqlFor('f')} AS ${TaxonPlaceholderSql.column},
        ${ancestorColumnsSql(TaxonomyTable.family, placeholders)},
        COUNT(DISTINCT CASE WHEN s.id IS NOT NULL THEN g.id END) AS genera_count,
        COUNT(DISTINCT s.id) AS species_count
      FROM families f
      LEFT JOIN orders o ON o.id = f."order"
      LEFT JOIN classes c ON c.id = o.class
      LEFT JOIN genera g ON g.family = f.id
      LEFT JOIN species s ON s.genus = g.id AND s.status = 'active'
      WHERE f.id = ?
      GROUP BY f.id
      LIMIT 1
    '''),
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: preferOwnNames(result.commonNames, localizedListMap(row)),
      classification: row == null
          ? const []
          : ancestorEntries(row, TaxonomyTable.family),
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
      isPlaceholder: TaxonPlaceholderSql.isSet(row),
    );
  }

  Future<TaxonomyDetail> _getOrderDetail(
    Database db,
    SearchResult result,
    TaxonPlaceholderSql placeholders,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT
        ${localizedCommonNameSubqueries(entityAlias: 'o', entityIdColumn: 'id')},
        o.sister_order,
        ${placeholders.sqlFor('o')} AS ${TaxonPlaceholderSql.column},
        ${ancestorColumnsSql(TaxonomyTable.order, placeholders)},
        COUNT(DISTINCT CASE WHEN s.id IS NOT NULL THEN f.id END) AS families_count,
        COUNT(DISTINCT CASE WHEN s.id IS NOT NULL THEN g.id END) AS genera_count,
        COUNT(DISTINCT s.id) AS species_count
      FROM orders o
      LEFT JOIN classes c ON c.id = o.class
      LEFT JOIN families f ON f."order" = o.id
      LEFT JOIN genera g ON g.family = f.id
      LEFT JOIN species s ON s.genus = g.id AND s.status = 'active'
      WHERE o.id = ?
      GROUP BY o.id
      LIMIT 1
    '''),
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: preferOwnNames(result.commonNames, localizedListMap(row)),
      classification: row == null
          ? const []
          : ancestorEntries(row, TaxonomyTable.order),
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
      isPlaceholder: TaxonPlaceholderSql.isSet(row),
    );
  }

  Future<TaxonomyDetail> _getClassDetail(
    Database db,
    SearchResult result,
    TaxonPlaceholderSql placeholders,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery('''
      SELECT
        ${localizedCommonNameSubqueries(entityAlias: 'c', entityIdColumn: 'id')},
        c.body_shape,
        ${placeholders.sqlFor('c')} AS ${TaxonPlaceholderSql.column},
        ${ancestorColumnsSql(TaxonomyTable.taxonomicClass, placeholders)},
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
      GROUP BY c.id
      LIMIT 1
    '''),
      [result.id],
    );

    final row = rows.isEmpty ? null : rows.first;
    return TaxonomyDetail(
      result: result,
      commonNames: preferOwnNames(result.commonNames, localizedListMap(row)),
      classification: row == null
          ? const []
          : ancestorEntries(row, TaxonomyTable.taxonomicClass),
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
      isPlaceholder: TaxonPlaceholderSql.isSet(row),
    );
  }

  /// Injects a regional country preference into reference-DB `common_names`
  /// ORDER BY clauses. See [withCountryPreference].
  String _countryAwareQuery(String rawQuery) =>
      withCountryPreference(rawQuery, _localeMapping?.countryCodeNumeric);

  Future<List<SearchResult>> getChildren(SearchResult parent) async {
    if (parent.id.startsWith('inat:')) return const [];
    if (parent.type == SearchEntityType.species) return const [];
    final table = TaxonomyTable.of(parent.type);
    return _commonNameEnricher.enrichChildren(
      await _queryDescendants(
        await _database,
        TaxonomyTable.values[table.index + 1],
        table,
        parent.id,
      ),
    );
  }

  /// Resolves every active species under [taxon], regardless of how many
  /// taxonomic levels separate them (e.g. a family's species live two levels
  /// down, via its genera). Used for bulk "add to deck" actions, where the
  /// direct children returned by [getChildren] aren't necessarily species.
  Future<List<SearchResult>> getAllSpeciesUnder(SearchResult taxon) async {
    if (taxon.id.startsWith('inat:')) return const [];
    if (taxon.type == SearchEntityType.species) return [taxon];
    return _queryDescendants(
      await _database,
      TaxonomyTable.species,
      TaxonomyTable.of(taxon.type),
      taxon.id,
    );
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
      final rows = await db.rawQuery('''
        SELECT DISTINCT region_key FROM taxonomy_distribution_regions
        WHERE entity_type = 'species' AND region_scope = 'country'
          AND entity_id IN ($placeholders)
          AND (presence_status IS NULL OR lower(presence_status) != 'absent')
        ''', chunk);
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

  /// All entities of [targetType] under [scope] (a coarser rank) — e.g. every
  /// genus under a family, or every species under an order. Used to build
  /// taxonomically-scoped multiple-choice distractor pools.
  Future<List<SearchResult>> getDescendantsOfType(
    SearchEntityType targetType,
    SearchResult scope,
  ) async {
    if (targetType == SearchEntityType.species) {
      return getAllSpeciesUnder(scope);
    }
    if (scope.id.startsWith('inat:')) return const [];
    final target = TaxonomyTable.of(targetType);
    final scopeTable = TaxonomyTable.of(scope.type);
    if (!target.isBelow(scopeTable)) {
      throw ArgumentError(
        'Unsupported target/scope combination: $targetType under ${scope.type}',
      );
    }
    return _queryDescendants(await _database, target, scopeTable, scope.id);
  }

  /// Runs the descendant query for one (descendant, ancestor) pair. Which
  /// pairs make sense is [TaxonomyTable]'s business; this only executes.
  Future<List<SearchResult>> _queryDescendants(
    Database db,
    TaxonomyTable descendant,
    TaxonomyTable ancestor,
    String ancestorId,
  ) async {
    final rows = await db.rawQuery(
      _countryAwareQuery(
        descendantsOfAncestorSql(
          descendant: descendant,
          ancestor: ancestor,
          placeholders: await TaxonPlaceholderSql.of(db),
        ),
      ),
      [ancestorId],
    );
    return rows
        .map((row) => _rowToSearchResult(row, descendant.type))
        .toList(growable: false);
  }

  SearchResult _rowToSearchResult(
    Map<String, Object?> row,
    SearchEntityType type,
  ) {
    return SearchResult(
      id: row['id'] as String,
      name: row['name'] as String,
      commonNames: localizedListMap(row),
      type: type,
      isPlaceholder: TaxonPlaceholderSql.isSet(row),
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
