import 'package:discere/catalog/model/region_abundance.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_species_selection_presenter.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

SearchResult _species(String id, String name) => SearchResult(
  id: id,
  name: name,
  commonNames: const {Language.en: []},
  type: SearchEntityType.species,
);

void main() {
  const presenter = TaxonomySpeciesSelectionPresenter();

  group('filterAndSort', () {
    test('sorts alphabetically when no region filter is active', () {
      final species = [
        _species('a', 'Zebra fish'),
        _species('b', 'Anemone fish'),
      ];

      final result = presenter.filterAndSort(
        species,
        regionFilterActive: false,
      );

      expect(result.map((s) => s.id), ['b', 'a']);
    });

    test('drops species absent from the abundance map when filtering', () {
      final species = [
        _species('in-region', 'In region species'),
        _species('outside', 'Outside species'),
      ];
      final abundance = {
        'in-region': ['common (usually seen)'],
      };

      final result = presenter.filterAndSort(
        species,
        regionFilterActive: true,
        abundanceRawValuesBySpeciesId: abundance,
      );

      expect(result.map((s) => s.id), ['in-region']);
    });

    test('keeps a present species with no rated abundance', () {
      final species = [_species('present-unrated', 'Present unrated')];
      final abundance = {'present-unrated': <String>[]};

      final result = presenter.filterAndSort(
        species,
        regionFilterActive: true,
        abundanceRawValuesBySpeciesId: abundance,
      );

      expect(result.map((s) => s.id), ['present-unrated']);
    });

    test('sorts by best abundance tier, most common first', () {
      final species = [
        _species('scarce', 'Scarce species'),
        _species('abundant', 'Abundant species'),
        _species('common', 'Common species'),
      ];
      final abundance = {
        'scarce': ['scarce (very unlikely)'],
        'abundant': ['abundant (always seen in some numbers)'],
        'common': ['common (usually seen)'],
      };

      final result = presenter.filterAndSort(
        species,
        regionFilterActive: true,
        abundanceRawValuesBySpeciesId: abundance,
      );

      expect(result.map((s) => s.id), ['abundant', 'common', 'scarce']);
    });

    test('places present-but-unrated species after rated ones', () {
      final species = [
        _species('unrated', 'Unrated species'),
        _species('rated', 'Rated species'),
      ];
      final abundance = {
        'unrated': <String>[],
        'rated': ['occasional (usually not seen)'],
      };

      final result = presenter.filterAndSort(
        species,
        regionFilterActive: true,
        abundanceRawValuesBySpeciesId: abundance,
      );

      expect(result.map((s) => s.id), ['rated', 'unrated']);
    });

    test('picks the best rating across multiple selected regions', () {
      final abundance = [
        'scarce (very unlikely)',
        'abundant (always seen in some numbers)',
      ];

      final best = presenter.bestAbundanceFor(abundance);

      expect(best, RegionAbundance.abundant);
    });

    test('breaks ties within the same tier alphabetically', () {
      final species = [
        _species('z', 'Zebra species'),
        _species('a', 'Anemone species'),
      ];
      final abundance = {
        'z': ['common (usually seen)'],
        'a': ['common (usually seen)'],
      };

      final result = presenter.filterAndSort(
        species,
        regionFilterActive: true,
        abundanceRawValuesBySpeciesId: abundance,
      );

      expect(result.map((s) => s.id), ['a', 'z']);
    });

    test('keeps everything when all frequency tiers are selected', () {
      final species = [
        _species('a', 'Zebra fish'),
        _species('b', 'Anemone fish'),
      ];

      final result = presenter.filterAndSort(
        species,
        regionFilterActive: false,
        selectedTiers: TaxonomySpeciesSelectionPresenter.allFrequencyTiers,
      );

      expect(result.map((s) => s.id), ['b', 'a']);
    });

    test('filters by frequency tier without a region filter active', () {
      final species = [
        _species('abundant', 'Abundant species'),
        _species('scarce', 'Scarce species'),
        _species('no-data', 'No data species'),
      ];
      final abundance = {
        'abundant': ['abundant (always seen in some numbers)'],
        'scarce': ['scarce (very unlikely)'],
      };

      final result = presenter.filterAndSort(
        species,
        regionFilterActive: false,
        abundanceRawValuesBySpeciesId: abundance,
        selectedTiers: const {RegionAbundance.abundant},
      );

      expect(result.map((s) => s.id), ['abundant']);
    });

    test('a null tier in selectedTiers keeps unrated/no-data species', () {
      final species = [
        _species('abundant', 'Abundant species'),
        _species('no-data', 'No data species'),
      ];
      final abundance = {
        'abundant': ['abundant (always seen in some numbers)'],
      };

      final result = presenter.filterAndSort(
        species,
        regionFilterActive: false,
        abundanceRawValuesBySpeciesId: abundance,
        selectedTiers: const {null},
      );

      expect(result.map((s) => s.id), ['no-data']);
    });

    test('combines an active region filter with a frequency filter', () {
      final species = [
        _species('in-region-common', 'In region, common'),
        _species('in-region-scarce', 'In region, scarce'),
        _species('outside', 'Outside region'),
      ];
      final abundance = {
        'in-region-common': ['common (usually seen)'],
        'in-region-scarce': ['scarce (very unlikely)'],
      };

      final result = presenter.filterAndSort(
        species,
        regionFilterActive: true,
        abundanceRawValuesBySpeciesId: abundance,
        selectedTiers: const {RegionAbundance.common},
      );

      expect(result.map((s) => s.id), ['in-region-common']);
    });
  });

  group('bestAbundanceFor', () {
    test('returns null when nothing parses', () {
      expect(presenter.bestAbundanceFor(['Bleeker, 1852', '95793']), isNull);
    });

    test('returns null for an empty list', () {
      expect(presenter.bestAbundanceFor(const []), isNull);
    });
  });
}
