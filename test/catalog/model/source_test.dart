import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:flutter_test/flutter_test.dart';

Classification _makeClassification({String genus = 'Carcharodon'}) {
  return Classification(
    genus,
    const {},
    null,
    'Lamnidae',
    const {},
    'Lamniformes',
    const {},
    'Chondrichthyes',
    const {},
    null,
  );
}

Species _makeSpecies({
  String externalId = '67018',
  String externalSource = 'sealifebase',
  String genus = 'Salarias',
  String scientificName = 'fasciatus',
}) {
  return Species(
    'discere:test_species:1',
    externalId,
    externalSource,
    scientificName,
    const {},
    _makeClassification(genus: genus),
    const [],
  );
}

void main() {
  group('Source.buildSpeciesUrl', () {
    test('replaces template placeholders with URL-encoded species values', () {
      final source = const Source(
        id: 'sealifebase',
        name: 'SeaLifeBase',
        category: 'Biological Data',
        citation: 'citation',
        url: 'https://www.sealifebase.org',
        speciesUrlTemplate:
            'https://sealifebase.org/summary/{genus}-{species}.html',
        licenseKey: 'CC BY-NC 4.0',
        displayOrder: 10,
      );

      final species = _makeSpecies();

      expect(
        source.buildSpeciesUrl(species)?.toString(),
        'https://sealifebase.org/summary/Salarias-fasciatus.html',
      );
    });

    test('builds FishBase detail links with the canonical summary path', () {
      final source = const Source(
        id: 'fishbase',
        name: 'FishBase',
        category: 'Biological Data',
        citation: 'citation',
        url: 'https://www.fishbase.org',
        speciesUrlTemplate:
            'https://www.fishbase.org/summary/{genus}-{species}.html',
        licenseKey: 'CC BY-NC 4.0',
        displayOrder: 20,
      );

      final species = _makeSpecies(
        externalId: '42',
        externalSource: 'fishbase',
        genus: 'Rhincodon',
        scientificName: 'typus',
      );

      expect(
        source.buildSpeciesUrl(species)?.toString(),
        'https://www.fishbase.org/summary/Rhincodon-typus.html',
      );
    });

    test(
      'supports external_id placeholders for source-specific detail links',
      () {
        final source = const Source(
          id: 'custom',
          name: 'Custom',
          category: 'Biological Data',
          citation: 'citation',
          url: 'https://example.org',
          speciesUrlTemplate: 'https://example.org/species/{external_id}',
          licenseKey: 'custom',
          displayOrder: 20,
        );

        final species = _makeSpecies(externalId: '42');

        expect(
          source.buildSpeciesUrl(species)?.toString(),
          'https://example.org/species/42',
        );
      },
    );

    test('returns null when no species template is configured', () {
      final source = const Source(
        id: 'generic',
        name: 'Generic Source',
        category: 'Biological Data',
        citation: 'citation',
        url: 'https://example.org',
        licenseKey: 'custom',
        displayOrder: 100,
      );

      expect(source.buildSpeciesUrl(_makeSpecies()), isNull);
    });

    test('URL-encodes whitespace-sensitive placeholders', () {
      final source = const Source(
        id: 'demo',
        name: 'Demo',
        category: 'Biological Data',
        citation: 'citation',
        url: 'https://example.org',
        speciesUrlTemplate: 'https://example.org/species?name={binomial}',
        licenseKey: 'custom',
        displayOrder: 100,
      );

      final species = _makeSpecies(
        genus: 'Aetobatus',
        scientificName: 'ocellatus test',
      );

      expect(
        source.buildSpeciesUrl(species)?.toString(),
        'https://example.org/species?name=Aetobatus%20ocellatus%20test',
      );
    });
  });
}
