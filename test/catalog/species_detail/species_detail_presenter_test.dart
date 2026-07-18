import 'package:discere/catalog/model/body_form.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/continent.dart';
import 'package:discere/catalog/model/fishing_importance.dart';
import 'package:discere/catalog/model/habitat_tag.dart';
import 'package:discere/catalog/model/human_risk.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_native_region.dart';
import 'package:discere/catalog/species_detail/species_detail_presenter.dart';
import 'package:discere/catalog/species_detail/species_fact_view_model.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SpeciesDetailPresenter presenter;
  late AppLocalizations en;
  late AppLocalizations de;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    de = await AppLocalizations.delegate.load(const Locale('de'));
  });

  setUp(() {
    presenter = const SpeciesDetailPresenter();
  });

  test('shows all native regions and groups subregions under the country', () {
    final species = _sampleSpecies();

    final viewData = presenter.present(species, Language.en, en);
    final section = viewData.nativeRegionsSection;

    expect(section, isNotNull);
    expect(section!.title, en.speciesDetailRegionsHabitatsTitle);
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
      en.speciesVulnerabilityModerate,
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'conservation')
          .tone,
      SpeciesFactTone.caution,
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'typicalLifespan')
          .value,
      en.speciesDetailLifespanYears(13),
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'foodChainLevel')
          .value,
      en.speciesTrophicCarnivore,
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'foodChainLevel')
          .tone,
      SpeciesFactTone.warning,
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'bodyForm')
          .value,
      en.speciesBodyFormElongated,
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'humanRisk')
          .value,
      en.speciesHumanRiskVenomous,
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type.name == 'humanRisk')
          .tone,
      SpeciesFactTone.danger,
    );
    expect(
      viewData.factsSection.facts.any(
        (fact) => fact.type == SpeciesFactType.fishingImportance,
      ),
      isFalse,
    );
    expect(section.nativeRegions, hasLength(7));
    expect(
      section.habitatTags,
      containsAll([
        en.speciesHabitatEstuary,
        en.speciesHabitatSeagrass,
        en.speciesHabitatReef,
      ]),
    );
    expect(
      section.nativeRegions.map((region) => region.label),
      containsAll(['Country 1', 'Country 6', 'Australia']),
    );

    final australia = section.nativeRegions.singleWhere(
      (region) => region.label == 'Australia',
    );
    expect(
      australia.subregions,
      containsAll(['Queensland', 'New South Wales']),
    );
  });

  test('localizes species detail enum values without translating regions', () {
    final species = _sampleSpecies();

    final viewData = presenter.present(species, Language.de, de);
    final section = viewData.nativeRegionsSection!;

    expect(section.title, de.speciesDetailRegionsHabitatsTitle);
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type == SpeciesFactType.conservation)
          .value,
      de.speciesVulnerabilityModerate,
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type == SpeciesFactType.foodChainLevel)
          .value,
      de.speciesTrophicCarnivore,
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type == SpeciesFactType.bodyForm)
          .value,
      de.speciesBodyFormElongated,
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type == SpeciesFactType.humanRisk)
          .value,
      de.speciesHumanRiskVenomous,
    );
    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type == SpeciesFactType.typicalLifespan)
          .value,
      de.speciesDetailLifespanYears(13),
    );
    expect(
      section.habitatTags,
      containsAll([
        de.speciesHabitatEstuary,
        de.speciesHabitatSeagrass,
        de.speciesHabitatReef,
      ]),
    );
    expect(
      section.nativeRegions.map((region) => region.label),
      containsAll(['Country 1', 'Country 6', 'Australia']),
    );
    expect(
      section.nativeRegions
          .singleWhere((region) => region.label == 'Australia')
          .subregions,
      containsAll(['Queensland', 'New South Wales']),
    );
  });

  test('marks a region as endemic based on establishment status', () {
    final species = _sampleSpecies(
      nativeRegions: const [
        SpeciesNativeRegion(
          scope: 'country',
          label: 'Galápagos Islands',
          establishmentStatus: 'endemic',
        ),
        SpeciesNativeRegion(
          scope: 'country',
          label: 'Ecuador',
          establishmentStatus: 'native',
        ),
      ],
    );

    final section = presenter
        .present(species, Language.en, en)
        .nativeRegionsSection!;

    expect(
      section.nativeRegions
          .singleWhere((region) => region.label == 'Galápagos Islands')
          .isEndemic,
      isTrue,
    );
    expect(
      section.nativeRegions
          .singleWhere((region) => region.label == 'Ecuador')
          .isEndemic,
      isFalse,
    );
  });

  test(
    'collapses many countries into a continent summary and hides subregions',
    () {
      final manyCountryRegions = [
        for (var i = 0; i < 9; i++)
          SpeciesNativeRegion(
            scope: 'country',
            label: 'Europe Country $i',
            continent: Continent.europe,
          ),
        const SpeciesNativeRegion(
          scope: 'country',
          label: 'Japan',
          continent: Continent.asia,
        ),
        const SpeciesNativeRegion(
          scope: 'country',
          label: 'Canada',
          continent: Continent.northAmerica,
        ),
        const SpeciesNativeRegion(
          scope: 'subregion',
          label: 'Canada · Ontario',
          continent: Continent.northAmerica,
        ),
      ];
      final species = _sampleSpecies(nativeRegions: manyCountryRegions);

      final section = presenter
          .present(species, Language.en, en)
          .nativeRegionsSection!;

      expect(section.nativeRegions, hasLength(11));
      expect(
        section.continents,
        containsAll([
          en.speciesDetailContinentEurope,
          en.speciesDetailContinentAsia,
          en.speciesDetailContinentNorthAmerica,
        ]),
      );
      expect(
        section.nativeRegions
            .singleWhere((region) => region.label == 'Canada')
            .subregions,
        isEmpty,
      );
    },
  );

  test('uses injury-focused German label for traumatogenic human risk', () {
    final species = _sampleSpecies(dangerousToHumans: HumanRisk.traumatogenic);

    final viewData = presenter.present(species, Language.de, de);

    expect(
      viewData.factsSection.facts
          .singleWhere((fact) => fact.type == SpeciesFactType.humanRisk)
          .value,
      de.speciesHumanRiskTraumatogenic,
    );
  });

  test('localizes normalized habitat values and keeps unknown fallback', () {
    expect(HabitatTag.fromRawHabitat('open ocean'), HabitatTag.openOcean);
    expect(HabitatTag.fromRawHabitat('host'), isNull);

    final openOceanSpecies = _sampleSpecies(
      habitat: 'open ocean',
      habitatTag: HabitatTag.openOcean,
      traits: const [],
    );
    final hostSpecies = _sampleSpecies(
      habitat: 'host',
      habitatTag: null,
      traits: const [],
    );

    final openOceanViewData = presenter.present(
      openOceanSpecies,
      Language.de,
      de,
    );
    final hostViewData = presenter.present(hostSpecies, Language.de, de);

    expect(
      openOceanViewData.nativeRegionsSection!.habitatTags,
      contains(de.speciesHabitatOpenOcean),
    );
    expect(hostViewData.nativeRegionsSection!.habitatTags, contains('host'));
  });
}

Species _sampleSpecies({
  HumanRisk dangerousToHumans = HumanRisk.venomous,
  String habitat = 'estuary',
  HabitatTag? habitatTag = HabitatTag.estuary,
  List<HabitatTag> traits = const [HabitatTag.seagrass, HabitatTag.reef],
  List<SpeciesNativeRegion>? nativeRegions,
}) {
  return Species(
    'species-1',
    'external-1',
    'fishbase',
    'trutta',
    const {
      Language.en: ['Brown trout'],
    },
    Classification(
      'Salmo',
      const {
        Language.en: ['Trouts'],
      },
      null,
      'Salmonidae',
      const {
        Language.en: ['Salmonids'],
      },
      'Salmoniformes',
      const {
        Language.en: ['Salmoniformes'],
      },
      'Actinopterygii',
      const {
        Language.en: ['Ray-finned fishes'],
      },
      null,
    ),
    const [],
    maxLengthCm: 0.8,
    depthMinM: 5,
    depthMaxM: 25,
    habitat: habitat,
    habitatTag: habitatTag,
    conservation: 44,
    longevityYears: 12.5,
    bodyShape: BodyForm.elongated,
    trophicLevelFood: 3.8,
    dangerousToHumans: dangerousToHumans,
    fisheriesImportance: FishingImportance.minorCommercial,
    traits: traits,
    nativeRegions:
        nativeRegions ??
        List.generate(
              6,
              (index) => SpeciesNativeRegion(
                scope: 'country',
                label: 'Country ${index + 1}',
              ),
            )
            .followedBy([
              const SpeciesNativeRegion(scope: 'country', label: 'Australia'),
              const SpeciesNativeRegion(
                scope: 'subregion',
                label: 'Australia · Queensland',
              ),
              const SpeciesNativeRegion(
                scope: 'subregion',
                label: 'Australia · New South Wales',
              ),
            ])
            .toList(growable: false),
  );
}
