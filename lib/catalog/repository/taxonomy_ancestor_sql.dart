/// The ranks a taxonomy detail page lists above its own taxon, as its query
/// selects them and as its row maps back to [TaxonomyClassificationEntry]s.
///
/// Every detail query joins the same chain upward — family `f`, order `o`,
/// class `c` — and only starts it at a different rank, so selecting and
/// reading an ancestor is the same for all of them.
library;

import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/repository/common_name_merging.dart';
import 'package:discere/catalog/repository/locale_aware_common_name_sql.dart';
import 'package:discere/catalog/repository/taxon_placeholder_sql.dart';
import 'package:discere/catalog/repository/taxonomy_hierarchy_sql.dart';

/// The ancestors of [rank], nearest first: a genus has family, order and
/// class above it, a class none.
List<TaxonomyTable> _ancestorsOf(TaxonomyTable rank) =>
    TaxonomyTable.values.sublist(0, rank.index).reversed.toList();

/// The column prefix an ancestor's values carry in a detail row.
String _prefixOf(TaxonomyTable ancestor) => switch (ancestor) {
  TaxonomyTable.taxonomicClass => 'class',
  TaxonomyTable.order => 'order',
  TaxonomyTable.family => 'family',
  TaxonomyTable.genus || TaxonomyTable.species => throw ArgumentError(
    'No detail page lists ${ancestor.name} as an ancestor.',
  ),
};

TaxonomyRankLabel _labelOf(TaxonomyTable ancestor) => switch (ancestor) {
  TaxonomyTable.taxonomicClass => TaxonomyRankLabel.classType,
  TaxonomyTable.order => TaxonomyRankLabel.order,
  TaxonomyTable.family => TaxonomyRankLabel.family,
  TaxonomyTable.genus || TaxonomyTable.species => throw ArgumentError(
    'No detail page lists ${ancestor.name} as an ancestor.',
  ),
};

/// Select-list columns for every ancestor of [rank] — id, name, placeholder
/// flag and common names — followed by the class's super class, which the
/// class table carries for itself and every rank below.
String ancestorColumnsSql(TaxonomyTable rank, TaxonPlaceholderSql placeholders) {
  final columns = [
    for (final ancestor in _ancestorsOf(rank))
      '${ancestor.alias}.id AS ${_prefixOf(ancestor)}_id, '
          '${ancestor.alias}.name AS ${_prefixOf(ancestor)}_name, '
          '${placeholders.sqlFor(ancestor.alias)} '
          'AS ${_prefixOf(ancestor)}_${TaxonPlaceholderSql.column}, '
          '${localizedCommonNameSubqueries(entityAlias: ancestor.alias, entityIdColumn: 'id', prefix: _prefixOf(ancestor))}',
    'c.super_class AS super_class',
  ];
  return columns.join(',\n        ');
}

/// The classification entries a detail row selected through
/// [ancestorColumnsSql] carries, nearest ancestor first and the super class
/// last. A rank the chain does not reach — the joins upward are left joins —
/// is unassigned, like a placeholder.
List<TaxonomyClassificationEntry> ancestorEntries(
  Map<String, Object?> row,
  TaxonomyTable rank,
) {
  final superClass = row['super_class'] as String?;
  return [
    for (final ancestor in _ancestorsOf(rank))
      TaxonomyClassificationEntry(
        label: _labelOf(ancestor),
        id: row['${_prefixOf(ancestor)}_id']?.toString(),
        scientificName: row['${_prefixOf(ancestor)}_name'] as String? ?? '',
        commonNames: localizedListMap(row, prefix: _prefixOf(ancestor)),
        isUnassigned:
            row['${_prefixOf(ancestor)}_id'] == null ||
            TaxonPlaceholderSql.isSet(
              row,
              '${_prefixOf(ancestor)}_${TaxonPlaceholderSql.column}',
            ),
      ),
    if (superClass != null && superClass.isNotEmpty)
      TaxonomyClassificationEntry(
        label: TaxonomyRankLabel.superClass,
        scientificName: superClass,
      ),
  ].where((e) => e.isUnassigned || e.scientificName.isNotEmpty).toList();
}
