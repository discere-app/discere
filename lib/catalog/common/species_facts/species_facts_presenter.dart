import 'package:discere/catalog/common/species_facts/species_fact_view_model.dart';
import 'package:discere/catalog/common/species_facts/species_trait_labels.dart';
import 'package:discere/catalog/model/habitat_tag.dart';
import 'package:discere/catalog/model/human_risk.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/util/trophic_level_format.dart';
import 'package:discere/catalog/util/vulnerability_format.dart';
import 'package:discere/catalog/util/years_format.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/util/depth_format.dart';
import 'package:discere/shared/util/length_format.dart';

/// A species' facts and habitats as labelled, formatted values — the species
/// detail page shows all of them, a comparison a few of each species.
class SpeciesFactsPresenter {
  const SpeciesFactsPresenter();

  /// The facts the species has data for, in the order the detail page shows
  /// them.
  List<SpeciesFactViewModel> facts(Species species, AppLocalizations loc) {
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
      species.bodyShape == null ? null : bodyFormLabel(loc, species.bodyShape!),
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

  /// Its habitats, the primary one first: the source's habitat tag, or its
  /// raw habitat text when the tag is missing, then the trait tags.
  List<String> habitatTags(Species species, AppLocalizations loc) {
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
}
