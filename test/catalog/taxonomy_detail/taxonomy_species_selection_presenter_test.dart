import 'package:discere/catalog/model/iucn_status.dart';
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

  test('sorts alphabetically by default, ignoring status', () {
    final species = [
      _species('a', 'Zebra fish'),
      _species('b', 'Anemone fish'),
    ];

    final sorted = presenter.sort(species, const {}, byRarity: false);

    expect(sorted.map((s) => s.id), ['b', 'a']);
  });

  test('sorts by IUCN threat severity when byRarity is true', () {
    final species = [
      _species('common', 'Common species'),
      _species('critical', 'Critical species'),
      _species('vulnerable', 'Vulnerable species'),
    ];
    final statusById = {
      'common': IucnStatus.leastConcern,
      'critical': IucnStatus.criticallyEndangered,
      'vulnerable': IucnStatus.vulnerable,
    };

    final sorted = presenter.sort(species, statusById, byRarity: true);

    expect(sorted.map((s) => s.id), ['critical', 'vulnerable', 'common']);
  });

  test(
    'places data-deficient/not-evaluated species after the threat spectrum',
    () {
      final species = [
        _species('lc', 'Least concern species'),
        _species('dd', 'Data deficient species'),
      ];
      final statusById = {
        'lc': IucnStatus.leastConcern,
        'dd': IucnStatus.dataDeficient,
      };

      final sorted = presenter.sort(species, statusById, byRarity: true);

      expect(sorted.map((s) => s.id), ['lc', 'dd']);
    },
  );

  test('places species with no cached status last of all', () {
    final species = [
      _species('unknown', 'Unknown species'),
      _species('dd', 'Data deficient species'),
      _species('en', 'Endangered species'),
    ];
    final statusById = {
      'dd': IucnStatus.dataDeficient,
      'en': IucnStatus.endangered,
    };

    final sorted = presenter.sort(species, statusById, byRarity: true);

    expect(sorted.map((s) => s.id), ['en', 'dd', 'unknown']);
  });

  test('breaks ties within the same tier alphabetically', () {
    final species = [
      _species('z', 'Zebra species'),
      _species('a', 'Anemone species'),
    ];
    final statusById = {
      'z': IucnStatus.vulnerable,
      'a': IucnStatus.vulnerable,
    };

    final sorted = presenter.sort(species, statusById, byRarity: true);

    expect(sorted.map((s) => s.id), ['a', 'z']);
  });
}
