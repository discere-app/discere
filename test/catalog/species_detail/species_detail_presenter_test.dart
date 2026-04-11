import 'package:discere/catalog/model/body_form.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/fishing_importance.dart';
import 'package:discere/catalog/model/habitat_tag.dart';
import 'package:discere/catalog/model/human_risk.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_native_region.dart';
import 'package:discere/catalog/species_detail/species_detail_presenter.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SpeciesDetailPresenter presenter;
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() {
    presenter = const SpeciesDetailPresenter();
  });

  test('shows all native regions and groups subregions under the country', () {
    final species = Species(
      'species-1',
      'external-1',
      'fishbase',
      'trutta',
      const {Language.en: 'Brown trout'},
      Classification(
        'Salmo',
        const {Language.en: 'Trouts'},
        null,
        'Salmonidae',
        const {Language.en: 'Salmonids'},
        'Salmoniformes',
        const {Language.en: 'Salmoniformes'},
        'Actinopterygii',
        const {Language.en: 'Ray-finned fishes'},
        null,
      ),
      const [],
      maxLengthCm: 0.8,
      depthMinM: 5,
      depthMaxM: 25,
      habitat: 'estuary',
      habitatTag: HabitatTag.estuary,
      conservation: 44,
      longevityYears: 12.5,
      bodyShape: BodyForm.elongated,
      trophicLevelFood: 3.8,
      dangerousToHumans: HumanRisk.venomous,
      fisheriesImportance: FishingImportance.minorCommercial,
      traits: const [HabitatTag.seagrass, HabitatTag.reef],
      nativeRegions: List.generate(
        13,
        (index) => SpeciesNativeRegion(
          scope: 'country',
          label: 'Country ${index + 1}',
        ),
      ).followedBy([
        const SpeciesNativeRegion(
          scope: 'country',
          label: 'Australia',
        ),
        const SpeciesNativeRegion(
          scope: 'subregion',
          label: 'Australia · Queensland',
        ),
        const SpeciesNativeRegion(
          scope: 'subregion',
          label: 'Australia · New South Wales',
        ),
      ]).toList(growable: false),
    );

    final viewData = presenter.present(species, Language.en, en);
    final section = viewData.nativeRegionsSection;

    expect(section, isNotNull);
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'size')
          .value,
      '8 mm',
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'depth')
          .value,
      '5-25 m',
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'conservation')
          .value,
      '44/100',
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'typicalLifespan')
          .value,
      '12.5 years',
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'foodChainLevel')
          .value,
      '3.8',
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'bodyForm')
          .value,
      'Elongated',
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'humanRisk')
          .value,
      'Venomous',
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'fishingImportance')
          .value,
      'Minor commercial',
    );
    expect(section!.nativeRegions, hasLength(14));
    expect(
      section.habitatTags,
      containsAll(['Estuary', 'Seagrass', 'Coral reef']),
    );
    expect(
      section.nativeRegions.map((region) => region.label),
      containsAll(['Country 1', 'Country 13', 'Australia']),
    );

    final australia = section.nativeRegions.singleWhere(
      (region) => region.label == 'Australia',
    );
    expect(
      australia.subregions,
      containsAll(['Queensland', 'New South Wales']),
    );
  });
}
