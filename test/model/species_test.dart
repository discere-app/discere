import 'package:discere/model/biology/classification.dart';
import 'package:discere/model/biology/species.dart';
import 'package:discere/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

Classification makeClassification({String genus = 'Carcharodon'}) {
  return Classification(
    genus,
    {Language.de: 'Weiße Haie'},
    null,
    'Lamnidae',
    {Language.de: 'Makrelenhaie', Language.en: 'Mackerel sharks'},
    'Lamniformes',
    {Language.de: 'Makrelenhaiartige', Language.en: 'Mackerel sharks'},
    'Chondrichthyes',
    {Language.de: 'Knorpelfische'},
    null,
  );
}

void main() {
  group('Species.getBinomialName', () {
    test('concatenates genus and species name with a single space', () {
      final species = Species(
        '1',
        'carcharias',
        {Language.de: 'Weißer Hai', Language.en: 'Great white shark'},
        makeClassification(genus: 'Carcharodon'),
        [],
      );

      expect(species.getBinomialName(), 'Carcharodon carcharias');
    });

    test('does not add leading or trailing whitespace', () {
      final species = Species(
        '2',
        'cuvier',
        {},
        makeClassification(genus: 'Galeocerdo'),
        [],
      );

      final name = species.getBinomialName();
      expect(name.trimLeft(), name,
          reason: 'Should have no leading whitespace');
      expect(name.trimRight(), name,
          reason: 'Should have no trailing whitespace');
    });

    test('uses exactly one space between genus and species', () {
      final species = Species(
        '3',
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
}
