import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_ranking.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> row({
  String id = 'sp-1',
  String scientificName = 'Amphiprion ocellaris',
  String? en,
  String? de,
  String entityType = 'species',
}) => {
  'id': id,
  'scientific_name': scientificName,
  'common_name_en': en,
  'common_name_de': de,
  'entity_type': entityType,
};

SearchCandidate reference(
  Map<String, dynamic> r, {
  String term = '',
  int sourcePriority = 1,
}) => candidateFromReferenceRow(
  r,
  normalizedSearchTerm: term,
  sourcePriority: sourcePriority,
);

void main() {
  group('how well a row matches the term', () {
    test('an exact name ranks above a prefix, which ranks above the rest', () {
      final exact = reference(row(scientificName: 'Amphiprion'), term: 'amphiprion');
      final prefix = reference(row(scientificName: 'Amphiprion ocellaris'), term: 'amphiprion');
      final other = reference(row(scientificName: 'Chromis viridis'), term: 'amphiprion');

      expect(exact.matchPriority, lessThan(prefix.matchPriority));
      expect(prefix.matchPriority, lessThan(other.matchPriority));
    });

    test('a common name counts as well as the scientific one', () {
      final byCommonName = reference(
        row(scientificName: 'Amphiprion ocellaris', en: 'Clownfish'),
        term: 'clownfish',
      );

      expect(byCommonName.matchPriority, 0);
    });

    test('one of several semicolon-separated names is enough', () {
      // The reference DB packs alternatives into one column.
      final candidate = reference(
        row(en: 'Anemonefish;Clownfish;Nemo'),
        term: 'clownfish',
      );

      expect(candidate.matchPriority, 0);
    });

    test('an empty term leaves every row equally relevant', () {
      final a = reference(row(scientificName: 'Zebrasoma'));
      final b = reference(row(scientificName: 'Amphiprion'));

      expect(a.matchPriority, b.matchPriority);
    });
  });

  group('ordering', () {
    test('the better match wins regardless of source', () {
      final worseMatchBetterSource = reference(
        row(scientificName: 'Chromis viridis'),
        term: 'amphiprion',
        sourcePriority: 0,
      );
      final betterMatch = reference(
        row(scientificName: 'Amphiprion ocellaris'),
        term: 'amphiprion',
        sourcePriority: 2,
      );

      expect(compareCandidates(betterMatch, worseMatchBetterSource), isNegative);
    });

    test('with equal match, a localized common name wins', () {
      // Someone searching in German should see the row that can name the
      // species in German first.
      final withGerman = reference(
        row(id: 'a', scientificName: 'Amphiprion', de: 'Clownfisch'),
        term: 'amphiprion',
      );
      final withoutGerman = reference(
        row(id: 'b', scientificName: 'Amphiprion'),
        term: 'amphiprion',
      );

      expect(compareCandidates(withGerman, withoutGerman), isNegative);
    });

    test('with equal match and names, the closer source wins', () {
      final near = reference(row(id: 'a'), sourcePriority: 0);
      final far = reference(row(id: 'b'), sourcePriority: 2);

      expect(compareCandidates(near, far), isNegative);
    });

    test('everything else equal, it is alphabetical and case-blind', () {
      final zebra = reference(row(id: 'a', scientificName: 'zebrasoma'));
      final amphi = reference(row(id: 'b', scientificName: 'Amphiprion'));

      expect(compareCandidates(amphi, zebra), isNegative);
    });
  });

  group('what counts as the same entity', () {
    test('two species rows merge when they share an id', () {
      // For species the id is the identity; the same species can come back
      // spelled differently from different sources.
      final merged = mergeCandidates([
        reference(row(id: 'sp-1', scientificName: 'Amphiprion ocellaris')),
        reference(row(id: 'sp-1', scientificName: 'Amphiprion percula')),
      ]);

      expect(merged, hasLength(1));
    });

    test('two species rows with different ids stay apart', () {
      final merged = mergeCandidates([
        reference(row(id: 'sp-1', scientificName: 'Amphiprion ocellaris')),
        reference(row(id: 'sp-2', scientificName: 'Amphiprion ocellaris')),
      ]);

      expect(merged, hasLength(2));
    });

    test('higher ranks merge by name instead, ids differing', () {
      // A genus has no stable id across sources — iNaturalist and the
      // reference DB number them differently — so the name is the identity.
      final merged = mergeCandidates([
        reference(row(id: 'g-1', scientificName: 'Amphiprion', entityType: 'genera')),
        reference(row(id: 'g-2', scientificName: 'amphiprion ', entityType: 'genera')),
      ]);

      expect(merged, hasLength(1));
    });

    test('the same name at different ranks is not the same thing', () {
      final merged = mergeCandidates([
        reference(row(id: 'a', scientificName: 'Amphiprion', entityType: 'genera')),
        reference(row(id: 'b', scientificName: 'Amphiprion', entityType: 'families')),
      ]);

      expect(merged, hasLength(2));
      expect(
        merged.map((c) => c.type),
        containsAll([SearchEntityType.genus, SearchEntityType.family]),
      );
    });
  });

  group('merging two rows for one entity', () {
    test('the closer source decides the id', () {
      final merged = mergeCandidates([
        reference(row(id: 'sp-1', scientificName: 'A'), sourcePriority: 2),
        reference(row(id: 'sp-1', scientificName: 'B'), sourcePriority: 0),
      ]).single;

      expect(merged.id, 'sp-1');
      expect(merged.name, 'B');
    });

    test('the longer name survives — it is the more complete one', () {
      final merged = mergeCandidates([
        reference(row(id: 'sp-1', scientificName: 'Amphiprion ocellaris')),
        reference(row(id: 'sp-1', scientificName: 'Amphiprion')),
      ]).single;

      expect(merged.name, 'Amphiprion ocellaris');
    });

    test('common names from both sides are kept, without duplicates', () {
      final merged = mergeCandidates([
        reference(row(id: 'sp-1', en: 'Clownfish')),
        reference(row(id: 'sp-1', en: 'Clownfish;Nemo')),
      ]).single;

      expect(merged.commonNames[Language.en], containsAll(['Clownfish', 'Nemo']));
      expect(
        merged.commonNames[Language.en]!.where((n) => n == 'Clownfish'),
        hasLength(1),
      );
    });

    test('the best match of the two is what the merged row keeps', () {
      final merged = mergeCandidates([
        reference(row(id: 'sp-1', scientificName: 'Amphiprion ocellaris'), term: 'zzz'),
        reference(
          row(id: 'sp-1', scientificName: 'Amphiprion ocellaris'),
          term: 'amphiprion ocellaris',
        ),
      ]).single;

      expect(merged.matchPriority, 0);
    });
  });
}
