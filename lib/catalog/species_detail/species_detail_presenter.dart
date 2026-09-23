import 'package:discere/catalog/common/continent_label.dart';
import 'package:discere/catalog/common/taxon_classification/taxon_classification_presenter.dart';
import 'package:discere/catalog/common/taxon_identity/taxon_identity_presenter.dart';
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
import 'package:discere/catalog/species_detail/species_trait_labels.dart';
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
          : vulnerabilityLabel(loc, vulnerabilityLevel),
      tone: _vulnerabilityTone(vulnerabilityLevel),
    );
    addFact(
      SpeciesFactType.bodyForm,
      loc.speciesDetailBodyForm,
      species.bodyShape == null
          ? null
          : bodyFormLabel(loc, species.bodyShape!),
    );
    addFact(
      SpeciesFactType.humanRisk,
      loc.speciesDetailHumanRisk,
      species.dangerousToHumans == null
          ? species.dangerousToHumansRaw
          : humanRiskLabel(loc, species.dangerousToHumans!),
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
          : trophicLevelLabel(loc, trophicLevelCategory),
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
      tags.add(habitatTagLabel(loc, habitatTag));
    } else if (habitatTag == null) {
      final rawHabitat = species.habitat?.trim();
      if (rawHabitat != null && rawHabitat.isNotEmpty) {
        tags.add(rawHabitat);
      }
    }

    for (final trait in species.traits) {
      if (seenTags.add(trait)) {
        final label = habitatTagLabel(loc, trait);
        if (!tags.contains(label)) {
          tags.add(label);
        }
      }
    }

    return tags;
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
        // A label with no " · " separator means the subdivision code had no
        // curated name (resolveCountryRegionLabel already dropped it) — the
        // country itself still counts as a native region, just without a
        // subregion pill.
        final parts = region.label.split(' · ');
        final country = parts.first.trim();
        if (country.isEmpty) continue;
        final subregions = subregionsByCountry.putIfAbsent(country, () => []);
        if (parts.length > 1) {
          final subregion = parts.sublist(1).join(' · ').trim();
          if (subregion.isNotEmpty && !subregions.contains(subregion)) {
            subregions.add(subregion);
          }
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
          ? continentsSeen.map((c) => continentLabel(loc, c)).toList()
          : const [],
    );
  }

}
