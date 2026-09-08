import 'package:discere/catalog/model/continent.dart';
import 'package:discere/catalog/util/continent_for_country.dart';
import 'package:discere/catalog/util/region_label_resolver.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves a plain ISO-numeric country code', () {
    expect(resolveCountryRegionLabel('218'), 'Ecuador');
  });

  test('resolves a curated special territory code', () {
    expect(resolveCountryRegionLabel('218A'), 'Galápagos Islands');
    expect(resolveCountryRegionLabel('840B'), 'Hawaii');
  });

  test('falls back to "country (code)" for an uncurated special territory code '
      'with a known country prefix', () {
    expect(
      resolveCountryRegionLabel('260B'),
      'French Southern Territories (260B)',
    );
  });

  test('leaves a fully unknown code unchanged', () {
    expect(resolveCountryRegionLabel('F111'), 'F111');
    expect(resolveCountryRegionLabel('I555'), 'I555');
  });

  test('resolves a curated subdivision code', () {
    expect(
      resolveCountryRegionLabel('840:US-WA'),
      'United States · Washington',
    );
  });

  test(
    'drops an uncurated subdivision code and returns just the country name',
    () {
      expect(resolveCountryRegionLabel('840:I557'), 'United States');
    },
  );

  test('returns an empty string unchanged', () {
    expect(resolveCountryRegionLabel('  '), '');
  });

  group('language: Language.de', () {
    test('resolves a plain ISO-numeric country code in German', () {
      expect(resolveCountryRegionLabel('818', language: Language.de), 'Ägypten');
      expect(resolveCountryRegionLabel('218', language: Language.de), 'Ecuador');
    });

    test('resolves a curated special territory code in German', () {
      expect(
        resolveCountryRegionLabel('218A', language: Language.de),
        'Galápagosinseln',
      );
    });

    test(
      'falls back to the German country name for an uncurated territory code',
      () {
        expect(
          resolveCountryRegionLabel('260B', language: Language.de),
          'Französische Süd- und Antarktisgebiete (260B)',
        );
      },
    );

    test('leaves a fully unknown code unchanged', () {
      expect(resolveCountryRegionLabel('F111', language: Language.de), 'F111');
    });
  });

  test('resolves the continent for a plain country code', () {
    expect(continentForCountryCode('218'), Continent.southAmerica);
    expect(continentForCountryCode('276'), Continent.europe);
  });

  test(
    'resolves the continent for a special territory code via its country prefix',
    () {
      expect(continentForCountryCode('218A'), Continent.southAmerica);
      expect(continentForCountryCode('840B'), Continent.northAmerica);
    },
  );

  test('resolves the continent for a subregion code', () {
    expect(continentForCountryCode('840:US-WA'), Continent.northAmerica);
  });

  test('returns null for an unresolvable code', () {
    expect(continentForCountryCode('F111'), isNull);
    expect(continentForCountryCode(''), isNull);
  });
}
