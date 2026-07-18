import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TaxonRank', () {
    test('rankName and entityType round-trip through fromRankName/fromEntityType', () {
      for (final rank in TaxonRank.values) {
        expect(TaxonRank.fromRankName(rank.rankName), rank);
        expect(TaxonRank.fromEntityType(rank.entityType), rank);
      }
    });

    test('rankName and entityType have the expected reference-DB spellings', () {
      expect(TaxonRank.genus.rankName, 'genus');
      expect(TaxonRank.genus.entityType, 'genera');
      expect(TaxonRank.family.rankName, 'family');
      expect(TaxonRank.family.entityType, 'families');
      expect(TaxonRank.order.rankName, 'order');
      expect(TaxonRank.order.entityType, 'orders');
      expect(TaxonRank.classRank.rankName, 'class');
      expect(TaxonRank.classRank.entityType, 'classes');
    });

    test('fromRankName and fromEntityType return null for unrelated strings', () {
      expect(TaxonRank.fromRankName('species'), isNull);
      expect(TaxonRank.fromRankName(null), isNull);
      expect(TaxonRank.fromEntityType('species'), isNull);
      expect(TaxonRank.fromEntityType(null), isNull);
    });

    test('fromSearchEntityType maps taxonomy entity types and rejects species', () {
      expect(
        TaxonRank.fromSearchEntityType(SearchEntityType.genus),
        TaxonRank.genus,
      );
      expect(
        TaxonRank.fromSearchEntityType(SearchEntityType.family),
        TaxonRank.family,
      );
      expect(
        TaxonRank.fromSearchEntityType(SearchEntityType.order),
        TaxonRank.order,
      );
      expect(
        TaxonRank.fromSearchEntityType(SearchEntityType.classType),
        TaxonRank.classRank,
      );
      expect(
        () => TaxonRank.fromSearchEntityType(SearchEntityType.species),
        throwsArgumentError,
      );
    });

    test('entityKey trims and lowercases the scientific name', () {
      expect(TaxonRank.genus.entityKey('  Barbus  '), 'genus:barbus');
      expect(TaxonRank.classRank.entityKey('Actinopterygii'), 'class:actinopterygii');
    });
  });
}
