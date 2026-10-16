import 'package:discere/catalog/repository/search_sql.dart';
import 'package:discere/catalog/repository/taxon_placeholder_sql.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const withColumn = TaxonPlaceholderSql(databaseHasColumn: true);
  const withoutColumn = TaxonPlaceholderSql(databaseHasColumn: false);

  group('every higher-taxon branch leaves rank placeholders out', () {
    test('in the FTS query', () {
      final sql = referenceFtsUnionAllSql(20, withColumn);

      // Scientific name and common name for genus, family and order; the
      // class has only its scientific-name branch.
      expect('g.is_placeholder = 0'.allMatches(sql), hasLength(2));
      expect('f.is_placeholder = 0'.allMatches(sql), hasLength(2));
      expect('o.is_placeholder = 0'.allMatches(sql), hasLength(2));
      expect('c.is_placeholder = 0'.allMatches(sql), hasLength(1));
    });

    test('in the LIKE fallback', () {
      final statements = referenceLikeFallbackSqlStatements(20, withColumn);

      expect(statements.first, isNot(contains('is_placeholder')));
      expect(statements[1], contains('g.is_placeholder = 0'));
      expect(statements[2], contains('f.is_placeholder = 0'));
      expect(statements[3], contains('o.is_placeholder = 0'));
      expect(statements[4], contains('c.is_placeholder = 0'));
    });
  });

  test('a database without the column filters on a constant', () {
    final sql = [
      referenceFtsUnionAllSql(20, withoutColumn),
      ...referenceLikeFallbackSqlStatements(20, withoutColumn),
    ].join();

    expect(sql, isNot(contains('is_placeholder')));
    expect('AND 0 = 0'.allMatches(sql), hasLength(11));
  });
}
