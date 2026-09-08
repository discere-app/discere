import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/repository/taxonomy_hierarchy_sql.dart';
import 'package:flutter_test/flutter_test.dart';

/// The common-name subqueries are the same four in every query and would
/// drown out what each test is about.
String sql({
  required TaxonomyTable descendant,
  required TaxonomyTable ancestor,
}) => descendantsOfAncestorSql(descendant: descendant, ancestor: ancestor)
    .replaceAll(RegExp(r'\(SELECT cn\.name FROM common_names.*?AS cn_\w+'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

void main() {
  test('the chain runs from class down to species', () {
    expect(TaxonomyTable.values.map((t) => t.table), [
      'classes',
      'orders',
      'families',
      'genera',
      'species',
    ]);
  });

  test('a table knows the search entity type it produces', () {
    expect(
      TaxonomyTable.of(SearchEntityType.genus),
      TaxonomyTable.genus,
    );
    expect(TaxonomyTable.species.type, SearchEntityType.species);
  });

  group('joins follow the chain', () {
    test('a direct child needs no join', () {
      expect(
        sql(descendant: TaxonomyTable.genus, ancestor: TaxonomyTable.family),
        contains('FROM genera g WHERE g.family = ?'),
      );
    });

    test('two levels up joins the table in between', () {
      final query = sql(
        descendant: TaxonomyTable.genus,
        ancestor: TaxonomyTable.order,
      );

      expect(query, contains('JOIN families f ON f.id = g.family'));
      expect(query, contains('WHERE f."order" = ?'));
    });

    test('three levels up joins both tables in between', () {
      final query = sql(
        descendant: TaxonomyTable.genus,
        ancestor: TaxonomyTable.taxonomicClass,
      );

      expect(query, contains('JOIN families f ON f.id = g.family'));
      expect(query, contains('JOIN orders o ON o.id = f."order"'));
      expect(query, contains('WHERE o.class = ?'));
    });

    test('species always join genera, even under their own genus', () {
      // Species are shown as "Genus species", so the genus name is needed
      // whether or not the join is required for filtering.
      final query = sql(
        descendant: TaxonomyTable.species,
        ancestor: TaxonomyTable.genus,
      );

      expect(query, contains('JOIN genera g ON g.id = s.genus'));
      expect(query, contains("g.name || ' ' || s.name AS name"));
      expect(query, contains('WHERE s.genus = ?'));
    });
  });

  group('only rows leading to an active species are returned', () {
    test('species are filtered directly', () {
      expect(
        sql(descendant: TaxonomyTable.species, ancestor: TaxonomyTable.family),
        contains("s.status = 'active'"),
      );
    });

    test('a genus needs one active species below it', () {
      expect(
        sql(descendant: TaxonomyTable.genus, ancestor: TaxonomyTable.family),
        contains(
          'EXISTS (SELECT 1 FROM species s '
          "WHERE s.genus = g.id AND s.status = 'active')",
        ),
      );
    });

    test('an order walks all the way down to species', () {
      // Two levels of the chain below it, or an order whose families are all
      // empty would still be offered.
      final query = sql(
        descendant: TaxonomyTable.order,
        ancestor: TaxonomyTable.taxonomicClass,
      );

      expect(query, contains('EXISTS (SELECT 1 FROM families f'));
      expect(query, contains('JOIN genera g ON g.family = f.id'));
      expect(query, contains('JOIN species s ON s.genus = g.id'));
      expect(query, contains('WHERE f."order" = o.id'));
    });
  });

  test('results are ordered by the scientific name', () {
    expect(
      sql(descendant: TaxonomyTable.family, ancestor: TaxonomyTable.order),
      endsWith('ORDER BY f.name'),
    );
  });

  test('an ancestor below the descendant is rejected', () {
    expect(
      () => descendantsOfAncestorSql(
        descendant: TaxonomyTable.family,
        ancestor: TaxonomyTable.genus,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
