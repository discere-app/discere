import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

Classification makeClassification({String? genus = 'Carcharodon'}) {
  return Classification(
    genus,
    {
      Language.de: ['Weiße Haie'],
    },
    null,
    'Lamnidae',
    {
      Language.de: ['Makrelenhaie'],
      Language.en: ['Mackerel sharks'],
    },
    'Lamniformes',
    {
      Language.de: ['Makrelenhaiartige'],
      Language.en: ['Mackerel sharks'],
    },
    'Chondrichthyes',
    {
      Language.de: ['Knorpelfische'],
    },
    null,
  );
}

void main() {
  group('Species.getBinomialName', () {
    test('concatenates genus and species name with a single space', () {
      final species = Species(
        '1',
        'ext1',
        'fishbase',
        'carcharias',
        {
          Language.de: ['Weißer Hai'],
          Language.en: ['Great white shark'],
        },
        makeClassification(genus: 'Carcharodon'),
        [],
      );

      expect(species.getBinomialName(), 'Carcharodon carcharias');
    });

    test('does not add leading or trailing whitespace', () {
      final species = Species(
        '2',
        'ext2',
        'fishbase',
        'cuvier',
        {},
        makeClassification(genus: 'Galeocerdo'),
        [],
      );

      final name = species.getBinomialName();
      expect(
        name.trimLeft(),
        name,
        reason: 'Should have no leading whitespace',
      );
      expect(
        name.trimRight(),
        name,
        reason: 'Should have no trailing whitespace',
      );
    });

    test('uses exactly one space between genus and species', () {
      final species = Species(
        '3',
        'ext3',
        'fishbase',
        'typus',
        {},
        makeClassification(genus: 'Rhincodon'),
        [],
      );

      expect(species.getBinomialName(), 'Rhincodon typus');
      final parts = species.getBinomialName().split(' ');
      expect(parts.length, 2, reason: 'Should have exactly two parts');
    });
  });

  group('Species without a genus', () {
    Species genusless({String? preferredScientificName}) => Species(
      '4',
      'ext4',
      'sealifebase',
      'humilis',
      {},
      makeClassification(genus: null),
      [],
      preferredScientificName: preferredScientificName,
    );

    test('is named by its preferred scientific name', () {
      final species = genusless(preferredScientificName: 'Gattya humilis');

      expect(species.binomialName, 'Gattya humilis');
      expect(species.getBinomialName(), 'Gattya humilis');
    });

    test('has no binomial without a preferred scientific name', () {
      final species = genusless();

      expect(species.binomialName, isNull);
      expect(species.getBinomialName(), 'humilis');
    });
  });

  test('a genus outranks the preferred scientific name', () {
    final species = Species(
      '5',
      'ext5',
      'fishbase',
      'carcharias',
      {},
      makeClassification(genus: 'Carcharodon'),
      [],
      preferredScientificName: 'Squalus carcharias',
    );

    expect(species.binomialName, 'Carcharodon carcharias');
  });
}
