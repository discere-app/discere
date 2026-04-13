import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const presenter = SpeciesListItemPresenter();

  group('SpeciesListItemPresenter', () {
    test('uses first localized common name for species lists', () {
      final viewModel = presenter.presentSpecies(_species(), Language.de);

      expect(viewModel.primaryName, 'Falscher Clownfisch');
      expect(viewModel.additionalNames, 'Anemonenfisch');
      expect(viewModel.scientificName, 'Amphiprion ocellaris');
    });

    test('falls back to English names when selected language is missing', () {
      final species = Species(
        'sp1',
        'sp1',
        'fishbase',
        'ocellaris',
        {
          Language.en: ['Clown anemonefish', 'False clownfish'],
        },
        _classification(),
        const [],
      );

      final viewModel = presenter.presentSpecies(species, Language.fr);

      expect(viewModel.primaryName, 'Clown anemonefish');
      expect(viewModel.additionalNames, 'False clownfish');
    });

    test('applies the same common-name selection to local-image items', () {
      final viewModel = presenter.presentSpeciesWithLocalImages(
        SpeciesWithLocalImages(_species(), const []),
        Language.de,
      );

      expect(viewModel.primaryName, 'Falscher Clownfisch');
      expect(viewModel.additionalNames, 'Anemonenfisch');
    });
  });
}

Species _species() {
  return Species(
    'sp1',
    'sp1',
    'fishbase',
    'ocellaris',
    {
      Language.de: ['Falscher Clownfisch', 'Anemonenfisch'],
      Language.en: ['Clown anemonefish', 'False clownfish'],
    },
    _classification(),
    const [],
  );
}

Classification _classification() {
  return Classification(
    'Amphiprion',
    const {},
    null,
    'Pomacentridae',
    const {},
    'Perciformes',
    const {},
    'Actinopterygii',
    const {},
    null,
  );
}
