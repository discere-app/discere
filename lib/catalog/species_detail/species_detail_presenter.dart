import 'package:discere/catalog/common/taxon_classification/taxon_classification_presenter.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_presenter.dart';
import 'package:discere/catalog/model/body_form.dart';
import 'package:discere/catalog/model/continent.dart';
import 'package:discere/catalog/model/habitat_tag.dart';
import 'package:discere/catalog/model/human_risk.dart';
import 'package:discere/catalog/model/region_abundance.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_native_region.dart';
import 'package:discere/catalog/species_detail/species_detail_view_model.dart';
import 'package:discere/catalog/species_detail/species_fact_view_model.dart';
import 'package:discere/catalog/species_detail/species_facts_section_view_model.dart';
import 'package:discere/catalog/species_detail/species_native_region_view_model.dart';
import 'package:discere/catalog/species_detail/species_native_regions_section_view_model.dart';
import 'package:discere/catalog/util/trophic_level_format.dart';
import 'package:discere/catalog/util/vulnerability_format.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/depth_format.dart';
import 'package:discere/shared/util/length_format.dart';
import 'package:discere/shared/util/years_format.dart';

class SpeciesDetailPresenter {
  final TaxonIdentityPresenter _identityPresenter;
  final TaxonClassificationPresenter _classificationPresenter;

  const SpeciesDetailPresenter({
    TaxonIdentityPresenter identityPresenter = const TaxonIdentityPresenter(),
    TaxonClassificationPresenter classificationPresenter =
        const TaxonClassificationPresenter(),
  }) : _identityPresenter = identityPresenter,
       _classificationPresenter = classificationPresenter;

  SpeciesDetailViewModel present(
    Species species,
    Language language,
    AppLocalizations loc,
  ) {
    final builtRegions = _buildNativeRegions(species.nativeRegions, loc);
    final habitatTags = _buildHabitatTags(species, loc);

    return SpeciesDetailViewModel(
      identity: _identityPresenter.present(species, language),
      isDeprecated: species.isDeprecated,
      classificationRows: _classificationPresenter.present(species, language),
      factsSection: SpeciesFactsSectionViewModel(
        title: loc.speciesDetailFactsTitle,
        facts: _buildFacts(species, loc),
      ),
      nativeRegionsSection: builtRegions.regions.isEmpty && habitatTags.isEmpty
          ? null
          : SpeciesNativeRegionsSectionViewModel(
              title: loc.speciesDetailRegionsHabitatsTitle,
              nativeRegions: builtRegions.regions,
              habitatTags: habitatTags,
              continents: builtRegions.continents,
              bestAbundance: builtRegions.regions.isEmpty
                  ? null
                  : RegionAbundance.best(
                      species.nativeRegions.map((r) => r.abundance).nonNulls,
                    ),
            ),
    );
  }

  List<SpeciesFactViewModel> _buildFacts(
    Species species,
    AppLocalizations loc,
  ) {
    final facts = <SpeciesFactViewModel>[];
    final vulnerabilityLevel = mapVulnerabilityLevel(species.conservation);
    final trophicLevelCategory = mapTrophicLevelCategory(
      species.trophicLevelFood,
    );

    void addFact(
      SpeciesFactType type,
      String label,
      String? value, {
      SpeciesFactTone tone = SpeciesFactTone.neutral,
    }) {
      if (value == null || value.trim().isEmpty) return;
      facts.add(
        SpeciesFactViewModel(
          type: type,
          label: label,
          value: value,
          tone: tone,
        ),
      );
    }

    addFact(
      SpeciesFactType.size,
      loc.speciesSize,
      formatLengthCm(species.maxLengthCm),
    );
    addFact(
      SpeciesFactType.depth,
      loc.speciesDepth,
      formatDepthRangeM(species.depthMinM, species.depthMaxM),
    );
    addFact(
      SpeciesFactType.conservation,
      loc.speciesDetailFishingVulnerability,
      vulnerabilityLevel == null
          ? null
          : _vulnerabilityLabel(loc, vulnerabilityLevel),
      tone: _vulnerabilityTone(vulnerabilityLevel),
    );
    addFact(
      SpeciesFactType.bodyForm,
      loc.speciesDetailBodyForm,
      species.bodyShape == null
          ? null
          : _bodyFormLabel(loc, species.bodyShape!),
    );
    addFact(
      SpeciesFactType.humanRisk,
      loc.speciesDetailHumanRisk,
      species.dangerousToHumans == null
          ? species.dangerousToHumansRaw
          : _humanRiskLabel(loc, species.dangerousToHumans!),
      tone: _humanRiskTone(species),
    );
    addFact(
      SpeciesFactType.typicalLifespan,
      loc.speciesDetailTypicalLifespan,
      formatYears(species.longevityYears, loc.speciesDetailLifespanYears),
    );
    addFact(
      SpeciesFactType.foodChainLevel,
      loc.speciesDetailFoodChainLevel,
      trophicLevelCategory == null
          ? null
          : _trophicLevelLabel(loc, trophicLevelCategory),
      tone: _trophicLevelTone(trophicLevelCategory),
    );

    return facts;
  }

  SpeciesFactTone _humanRiskTone(Species species) {
    switch (species.dangerousToHumans) {
      case HumanRisk.harmless:
        return SpeciesFactTone.safe;
      case HumanRisk.venomous:
      case HumanRisk.ciguateraRisk:
      case HumanRisk.poisonousToEat:
        return SpeciesFactTone.danger;
      case HumanRisk.traumatogenic:
      case HumanRisk.potentialPest:
      case HumanRisk.other:
        return SpeciesFactTone.caution;
      case null:
        return species.dangerousToHumansRaw == null
            ? SpeciesFactTone.neutral
            : SpeciesFactTone.caution;
    }
  }

  SpeciesFactTone _vulnerabilityTone(VulnerabilityLevel? level) {
    switch (level) {
      case VulnerabilityLevel.low:
        return SpeciesFactTone.safe;
      case VulnerabilityLevel.moderate:
        return SpeciesFactTone.caution;
      case VulnerabilityLevel.high:
        return SpeciesFactTone.warning;
      case VulnerabilityLevel.veryHigh:
        return SpeciesFactTone.danger;
      case null:
        return SpeciesFactTone.neutral;
    }
  }

  SpeciesFactTone _trophicLevelTone(TrophicLevelCategory? category) {
    switch (category) {
      case TrophicLevelCategory.herbivore:
        return SpeciesFactTone.safe;
      case TrophicLevelCategory.omnivore:
        return SpeciesFactTone.caution;
      case TrophicLevelCategory.carnivore:
        return SpeciesFactTone.warning;
      case TrophicLevelCategory.apexPredator:
        return SpeciesFactTone.danger;
      case null:
        return SpeciesFactTone.neutral;
    }
  }

  List<String> _buildHabitatTags(Species species, AppLocalizations loc) {
    final tags = <String>[];
    final seenTags = <HabitatTag>{};

    final habitatTag = species.habitatTag;
    if (habitatTag != null && seenTags.add(habitatTag)) {
      tags.add(_habitatTagLabel(loc, habitatTag));
    } else if (habitatTag == null) {
      final rawHabitat = species.habitat?.trim();
      if (rawHabitat != null && rawHabitat.isNotEmpty) {
        tags.add(rawHabitat);
      }
    }

    for (final trait in species.traits) {
      if (seenTags.add(trait)) {
        final label = _habitatTagLabel(loc, trait);
        if (!tags.contains(label)) {
          tags.add(label);
        }
      }
    }

    return tags;
  }

  String _habitatTagLabel(AppLocalizations loc, HabitatTag tag) {
    switch (tag) {
      case HabitatTag.estuary:
        return loc.speciesHabitatEstuary;
      case HabitatTag.stream:
        return loc.speciesHabitatStream;
      case HabitatTag.lake:
        return loc.speciesHabitatLake;
      case HabitatTag.mangrove:
        return loc.speciesHabitatMangrove;
      case HabitatTag.reef:
        return loc.speciesHabitatReef;
      case HabitatTag.seagrass:
        return loc.speciesHabitatSeagrass;
      case HabitatTag.freshwater:
        return loc.speciesHabitatFreshwater;
      case HabitatTag.lagoon:
        return loc.speciesHabitatLagoon;
      case HabitatTag.cave:
        return loc.speciesHabitatCave;
      case HabitatTag.openOcean:
        return loc.speciesHabitatOpenOcean;
      case HabitatTag.openOceanEpipelagic:
        return loc.speciesHabitatOpenOceanEpipelagic;
      case HabitatTag.openOceanMesopelagic:
        return loc.speciesHabitatOpenOceanMesopelagic;
      case HabitatTag.hardBottom:
        return loc.speciesHabitatHardBottom;
      case HabitatTag.softBottom:
        return loc.speciesHabitatSoftBottom;
      case HabitatTag.demersal:
        return loc.speciesHabitatDemersal;
      case HabitatTag.bathydemersal:
        return loc.speciesHabitatBathydemersal;
      case HabitatTag.pelagic:
        return loc.speciesHabitatPelagic;
      case HabitatTag.epipelagic:
        return loc.speciesHabitatEpipelagic;
      case HabitatTag.bathypelagic:
        return loc.speciesHabitatBathypelagic;
      case HabitatTag.benthic:
        return loc.speciesHabitatBenthic;
      case HabitatTag.benthopelagic:
        return loc.speciesHabitatBenthopelagic;
      case HabitatTag.littoral:
        return loc.speciesHabitatLittoral;
      case HabitatTag.neritic:
        return loc.speciesHabitatNeritic;
      case HabitatTag.pelagicNeritic:
        return loc.speciesHabitatPelagicNeritic;
      case HabitatTag.pelagicOceanic:
        return loc.speciesHabitatPelagicOceanic;
    }
  }

  String _bodyFormLabel(AppLocalizations loc, BodyForm bodyForm) {
    switch (bodyForm) {
      case BodyForm.elongated:
        return loc.speciesBodyFormElongated;
      case BodyForm.fusiformNormal:
        return loc.speciesBodyFormFusiformNormal;
      case BodyForm.shortOrDeep:
        return loc.speciesBodyFormShortOrDeep;
      case BodyForm.eelLike:
        return loc.speciesBodyFormEelLike;
      case BodyForm.other:
        return loc.speciesBodyFormOther;
    }
  }

  String _humanRiskLabel(AppLocalizations loc, HumanRisk risk) {
    switch (risk) {
      case HumanRisk.harmless:
        return loc.speciesHumanRiskHarmless;
      case HumanRisk.venomous:
        return loc.speciesHumanRiskVenomous;
      case HumanRisk.traumatogenic:
        return loc.speciesHumanRiskTraumatogenic;
      case HumanRisk.ciguateraRisk:
        return loc.speciesHumanRiskCiguateraRisk;
      case HumanRisk.poisonousToEat:
        return loc.speciesHumanRiskPoisonousToEat;
      case HumanRisk.potentialPest:
        return loc.speciesHumanRiskPotentialPest;
      case HumanRisk.other:
        return loc.speciesHumanRiskOther;
    }
  }

  String _vulnerabilityLabel(AppLocalizations loc, VulnerabilityLevel level) {
    switch (level) {
      case VulnerabilityLevel.low:
        return loc.speciesVulnerabilityLow;
      case VulnerabilityLevel.moderate:
        return loc.speciesVulnerabilityModerate;
      case VulnerabilityLevel.high:
        return loc.speciesVulnerabilityHigh;
      case VulnerabilityLevel.veryHigh:
        return loc.speciesVulnerabilityVeryHigh;
    }
  }

  String _trophicLevelLabel(
    AppLocalizations loc,
    TrophicLevelCategory category,
  ) {
    switch (category) {
      case TrophicLevelCategory.herbivore:
        return loc.speciesTrophicHerbivore;
      case TrophicLevelCategory.omnivore:
        return loc.speciesTrophicOmnivore;
      case TrophicLevelCategory.carnivore:
        return loc.speciesTrophicCarnivore;
      case TrophicLevelCategory.apexPredator:
        return loc.speciesTrophicApexPredator;
    }
  }

  static const int _manyCountriesThreshold = 10;

  ({List<SpeciesNativeRegionViewModel> regions, List<String> continents})
  _buildNativeRegions(List<SpeciesNativeRegion> regions, AppLocalizations loc) {
    final subregionsByCountry = <String, List<String>>{};
    final isEndemicByCountry = <String, bool>{};
    final continentsSeen = <Continent>{};

    void markEndemic(String country, SpeciesNativeRegion region) {
      if (region.establishmentStatus?.toLowerCase().contains('endemic') ??
          false) {
        isEndemicByCountry[country] = true;
      } else {
        isEndemicByCountry.putIfAbsent(country, () => false);
      }
    }

    for (final region in regions) {
      if (region.continent != null) {
        continentsSeen.add(region.continent!);
      }

      if (region.scope == 'subregion') {
        final parts = region.label.split(' · ');
        final country = parts.first.trim();
        final subregion = parts.length > 1
            ? parts.sublist(1).join(' · ').trim()
            : region.label.trim();
        if (country.isEmpty) continue;
        final subregions = subregionsByCountry.putIfAbsent(country, () => []);
        if (subregion.isNotEmpty && !subregions.contains(subregion)) {
          subregions.add(subregion);
        }
        markEndemic(country, region);
        continue;
      }

      final country = region.label.trim();
      if (country.isEmpty) continue;
      subregionsByCountry.putIfAbsent(country, () => []);
      markEndemic(country, region);
    }

    final isWidespread = subregionsByCountry.length > _manyCountriesThreshold;
    final builtRegions = subregionsByCountry.entries
        .map(
          (entry) => SpeciesNativeRegionViewModel(
            label: entry.key,
            subregions: isWidespread
                ? const []
                : List.unmodifiable(entry.value),
            isEndemic: isEndemicByCountry[entry.key] ?? false,
          ),
        )
        .toList(growable: false);

    return (
      regions: builtRegions,
      continents: isWidespread
          ? continentsSeen.map((c) => _continentLabel(loc, c)).toList()
          : const [],
    );
  }

  String _continentLabel(AppLocalizations loc, Continent continent) {
    switch (continent) {
      case Continent.africa:
        return loc.speciesDetailContinentAfrica;
      case Continent.antarctica:
        return loc.speciesDetailContinentAntarctica;
      case Continent.asia:
        return loc.speciesDetailContinentAsia;
      case Continent.europe:
        return loc.speciesDetailContinentEurope;
      case Continent.northAmerica:
        return loc.speciesDetailContinentNorthAmerica;
      case Continent.oceania:
        return loc.speciesDetailContinentOceania;
      case Continent.southAmerica:
        return loc.speciesDetailContinentSouthAmerica;
    }
  }
}
