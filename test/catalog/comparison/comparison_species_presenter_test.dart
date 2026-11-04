import 'package:discere/catalog/common/species_facts/species_fact_view_model.dart';
import 'package:discere/catalog/comparison/comparison_species_presenter.dart';
import 'package:discere/catalog/model/body_form.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/habitat_tag.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Species _species({
  double? maxLengthCm,
  double? depthMinM,
  double? depthMaxM,
  HabitatTag? habitatTag,
  List<HabitatTag> traits = const [],
}) => Species(
  'sp1',
  'ext1',
  'fishbase',
  'pastinaca',
  const {
    Language.en: ['Common stingray'],
  },
  Classification(
    'Dasyatis',
    const {},
    null,
    'Dasyatidae',
    const {},
    'Myliobatiformes',
    const {},
    'Elasmobranchii',
    const {},
    null,
  ),
  const [],
  maxLengthCm: maxLengthCm,
  depthMinM: depthMinM,
  depthMaxM: depthMaxM,
  habitatTag: habitatTag,
  traits: traits,
  bodyShape: BodyForm.elongated,
  longevityYears: 20,
);

void main() {
  const presenter = ComparisonSpeciesPresenter();
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('names the species as the watchlist does', () {
    final species = presenter.present(_species(), Language.en, en);

    expect(species.primaryName, 'Common stingray');
    expect(species.scientificName, 'Dasyatis pastinaca');
  });

  test('shows size, depth and the primary habitat, and none of the detail '
      "page's other facts", () {
    final species = presenter.present(
      _species(
        maxLengthCm: 60,
        depthMinM: 0,
        depthMaxM: 200,
        habitatTag: HabitatTag.seagrass,
        traits: const [HabitatTag.reef],
      ),
      Language.en,
      en,
    );

    expect(species.facts.map((fact) => (fact.type, fact.label)), [
      (SpeciesFactType.size, en.speciesSize),
      (SpeciesFactType.depth, en.speciesDepth),
      (SpeciesFactType.habitat, en.speciesDetailHabitat),
    ]);
    expect(species.facts.last.value, en.speciesHabitatSeagrass);
  });

  test('leaves out a fact the species has no data for', () {
    final species = presenter.present(
      _species(depthMinM: 0, depthMaxM: 200),
      Language.en,
      en,
    );

    expect(species.facts.map((fact) => fact.type), [SpeciesFactType.depth]);
  });
}
