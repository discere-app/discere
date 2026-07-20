import 'package:discere/catalog/model/region_abundance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RegionAbundance.fromRaw', () {
    final cases = {
      'abundant (always seen in some numbers)': RegionAbundance.abundant,
      'very common': RegionAbundance.abundant,
      'very common but endangered': RegionAbundance.abundant,
      'common (usually seen)': RegionAbundance.common,
      'common but endangered': RegionAbundance.common,
      'fairly common (chances are about 50%)': RegionAbundance.fairlyCommon,
      'occasional (usually not seen)': RegionAbundance.occasional,
      'scarce (very unlikely)': RegionAbundance.scarce,
      'rare': RegionAbundance.scarce,
    };

    cases.forEach((raw, expected) {
      test('parses "$raw" as $expected', () {
        expect(RegionAbundance.fromRaw(raw), expected);
      });
    });

    test('is case-insensitive', () {
      expect(
        RegionAbundance.fromRaw('COMMON (Usually Seen)'),
        RegionAbundance.common,
      );
    });

    test('returns null for unparseable garbage values', () {
      expect(RegionAbundance.fromRaw('Bleeker, 1852'), isNull);
      expect(RegionAbundance.fromRaw('95793'), isNull);
      expect(RegionAbundance.fromRaw(''), isNull);
      expect(RegionAbundance.fromRaw('   '), isNull);
    });
  });

  test('tiers are ordered from most to least common', () {
    expect(RegionAbundance.tiers, [
      RegionAbundance.abundant,
      RegionAbundance.common,
      RegionAbundance.fairlyCommon,
      RegionAbundance.occasional,
      RegionAbundance.scarce,
    ]);
  });
}
