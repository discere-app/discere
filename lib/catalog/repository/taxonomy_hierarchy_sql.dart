import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/repository/locale_aware_common_name_sql.dart';

/// The reference DB's taxonomy tables, broadest first, with how each links
/// to the one above it.
///
/// Writing the chain down once is what makes ten different descendant
/// queries — species under a family, genera under a class, and so on — fall
/// out of it. Each used to spell out its own joins and its own filter
/// column, so the shape of the taxonomy was re-encoded ten times in SQL
/// strings and could only be checked by reading all ten.
///
/// Deliberately not `TaxonRank`, which is the domain vocabulary shared
/// across slices: that one covers the four ranks *above* species, which is
/// the right set for enrichment and one short for a join path that ends at
/// species. This one is about tables and how they join in one database.
enum TaxonomyTable {
  taxonomicClass(
    table: 'classes',
    alias: 'c',
    type: SearchEntityType.classType,
    parentLink: null,
  ),
  order(
    table: 'orders',
    alias: 'o',
    type: SearchEntityType.order,
    // Quoted: `order` is a SQL keyword.
    parentLink: 'o.class',
  ),
  family(
    table: 'families',
    alias: 'f',
    type: SearchEntityType.family,
    parentLink: 'f."order"',
  ),
  genus(
    table: 'genera',
    alias: 'g',
    type: SearchEntityType.genus,
    parentLink: 'g.family',
  ),
  species(
    table: 'species',
    alias: 's',
    type: SearchEntityType.species,
    parentLink: 's.genus',
  );

  final String table;
  final String alias;
  final SearchEntityType type;

  /// The column on this rank's own table that points at its parent — the
  /// only thing a join up the chain, or a filter on an ancestor, needs.
  /// Null for the broadest rank, which has no parent.
  final String? parentLink;

  const TaxonomyTable({
    required this.table,
    required this.alias,
    required this.type,
    required this.parentLink,
  });

  static TaxonomyTable of(SearchEntityType type) =>
      values.firstWhere((rank) => rank.type == type);

  bool isBelow(TaxonomyTable other) => index > other.index;

  /// The ranks strictly between this one and [ancestor], narrowest first —
  /// the tables a query has to join through to get from here to there.
  List<TaxonomyTable> _pathUpTo(TaxonomyTable ancestor) =>
      values.sublist(ancestor.index + 1, index).reversed.toList();
}

/// Selects every [descendant] under one [ancestor], with its common names,
/// leaving the ancestor's id as the single `?` parameter.
///
/// Only rows that lead to an active species are returned: a genus whose
/// species are all inactive is not a genus a user can do anything with, and
/// showing it would end in an empty list one tap later.
String descendantsOfAncestorSql({
  required TaxonomyTable descendant,
  required TaxonomyTable ancestor,
}) {
  assert(descendant.isBelow(ancestor), 'descendant must sit below ancestor');
  final a = descendant.alias;

  // Species are shown as "Genus species", so their query joins genera even
  // when the ancestor is the genus itself and no join would be needed.
  final joins = [
    // Only needed for the genus itself; for anything higher the path up
    // already joins genera.
    if (descendant == TaxonomyTable.species && ancestor == TaxonomyTable.genus)
      _join(TaxonomyTable.genus, descendant),
    ...descendant._pathUpTo(ancestor).map((r) => _join(r, _childOf(r))),
  ];

  final nameExpression = descendant == TaxonomyTable.species
      ? "g.name || ' ' || s.name AS name"
      : '$a.name';

  return '''
      SELECT $a.id, $nameExpression,
        ${_commonNames(a)}
      FROM ${descendant.table} $a
      ${joins.join('\n      ')}
      WHERE ${_childOf(ancestor).parentLink} = ?
        AND ${_activeSpeciesCondition(descendant)}
      ORDER BY $a.name
      ''';
}

/// `JOIN <parent table> <alias> ON <alias>.id = <child>.<parent link>`
String _join(TaxonomyTable parent, TaxonomyTable child) =>
    'JOIN ${parent.table} ${parent.alias} '
    'ON ${parent.alias}.id = ${child.parentLink}';

TaxonomyTable _childOf(TaxonomyTable rank) => TaxonomyTable.values[rank.index + 1];

/// A species is active in its own right; anything above it is active when
/// some species below it is, which is a walk down the same chain.
String _activeSpeciesCondition(TaxonomyTable descendant) {
  if (descendant == TaxonomyTable.species) return "s.status = 'active'";

  final below = TaxonomyTable.values.sublist(descendant.index + 1);
  final buffer = StringBuffer(
    'EXISTS (SELECT 1 FROM ${below.first.table} ${below.first.alias}',
  );
  for (var i = 1; i < below.length; i++) {
    final rank = below[i];
    buffer.write(
      ' JOIN ${rank.table} ${rank.alias} '
      'ON ${rank.parentLink} = ${below[i - 1].alias}.id',
    );
  }
  buffer.write(
    ' WHERE ${below.first.parentLink} = ${descendant.alias}.id'
    " AND s.status = 'active')",
  );
  return buffer.toString();
}

String _commonNames(String alias) => [
  for (final language in const ['de', 'en', 'fr', 'es'])
    commonNameSubquery(
      entityAlias: alias,
      entityIdColumn: 'id',
      language: language,
      outputAlias: 'cn_$language',
    ),
].join(',\n        ');
