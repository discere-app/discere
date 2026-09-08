import 'package:discere/catalog/util/region_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a blank key resolves to nothing at all', () {
    expect(RegionKey.parse(''), isNull);
    expect(RegionKey.parse('   '), isNull);
  });

  test('a plain country code has no subdivision', () {
    final key = RegionKey.parse('840')!;

    expect(key.countryCode, '840');
    expect(key.paddedCountryCode, '840');
    expect(key.subdivisionCode, isNull);
  });

  test('a short numeric code is padded for the lookup tables', () {
    // The tables are keyed by three digits; the raw form is what territory
    // names use, so both are kept.
    final key = RegionKey.parse('12')!;

    expect(key.countryCode, '12');
    expect(key.paddedCountryCode, '012');
  });

  test('the part after the colon is the subdivision', () {
    final key = RegionKey.parse('840:US-WA')!;

    expect(key.countryCode, '840');
    expect(key.subdivisionCode, 'US-WA');
  });

  test('a subdivision containing a colon stays whole', () {
    expect(RegionKey.parse('840:a:b')!.subdivisionCode, 'a:b');
  });

  test('surrounding whitespace is not part of the key', () {
    final key = RegionKey.parse('  840  ')!;

    expect(key.raw, '840');
    expect(key.countryCode, '840');
  });

  group('the mainland country a territory hangs off', () {
    test('is the leading digits of a territory code', () {
      // 218A is the Galápagos, off 218 Ecuador — this is what makes a
      // territory nobody curated resolvable at all.
      expect(RegionKey.parse('218A')!.mainlandCountryCode, '218');
    });

    test('is padded like any other country code', () {
      expect(RegionKey.parse('12B')!.mainlandCountryCode, '012');
    });

    test('is the code itself when it is already a country', () {
      expect(RegionKey.parse('840')!.mainlandCountryCode, '840');
    });

    test('is nothing for a code that does not start with digits', () {
      // How FishBase-internal codes like F111 are told apart from territories.
      expect(RegionKey.parse('F111')!.mainlandCountryCode, isNull);
      expect(RegionKey.parse('I557')!.mainlandCountryCode, isNull);
    });
  });
}
