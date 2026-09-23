import 'package:discere/catalog/model/body_form.dart';
import 'package:discere/catalog/model/habitat_tag.dart';
import 'package:discere/catalog/model/human_risk.dart';
import 'package:discere/catalog/util/trophic_level_format.dart';
import 'package:discere/catalog/util/vulnerability_format.dart';
import 'package:discere/l10n/app_localizations.dart';

/// The localized names of the species traits the detail page shows.
///
/// Five vocabularies, one case per enum value and nothing else. They sit
/// here rather than in `SpeciesDetailPresenter` because they are tables, not
/// derived state: adding a habitat or a body form is a row, and a row should
/// not have to be found inside the class that decides which facts a species
/// gets and what tone each one carries.
///
/// Same shape as `continent_label.dart`, the other vocabulary in this slice.

String habitatTagLabel(AppLocalizations loc, HabitatTag tag) =>
    switch (tag) {
      HabitatTag.estuary => loc.speciesHabitatEstuary,
      HabitatTag.stream => loc.speciesHabitatStream,
      HabitatTag.lake => loc.speciesHabitatLake,
      HabitatTag.mangrove => loc.speciesHabitatMangrove,
      HabitatTag.reef => loc.speciesHabitatReef,
      HabitatTag.seagrass => loc.speciesHabitatSeagrass,
      HabitatTag.freshwater => loc.speciesHabitatFreshwater,
      HabitatTag.lagoon => loc.speciesHabitatLagoon,
      HabitatTag.cave => loc.speciesHabitatCave,
      HabitatTag.openOcean => loc.speciesHabitatOpenOcean,
      HabitatTag.openOceanEpipelagic => loc.speciesHabitatOpenOceanEpipelagic,
      HabitatTag.openOceanMesopelagic => loc.speciesHabitatOpenOceanMesopelagic,
      HabitatTag.hardBottom => loc.speciesHabitatHardBottom,
      HabitatTag.softBottom => loc.speciesHabitatSoftBottom,
      HabitatTag.demersal => loc.speciesHabitatDemersal,
      HabitatTag.bathydemersal => loc.speciesHabitatBathydemersal,
      HabitatTag.pelagic => loc.speciesHabitatPelagic,
      HabitatTag.epipelagic => loc.speciesHabitatEpipelagic,
      HabitatTag.bathypelagic => loc.speciesHabitatBathypelagic,
      HabitatTag.benthic => loc.speciesHabitatBenthic,
      HabitatTag.benthopelagic => loc.speciesHabitatBenthopelagic,
      HabitatTag.littoral => loc.speciesHabitatLittoral,
      HabitatTag.neritic => loc.speciesHabitatNeritic,
      HabitatTag.pelagicNeritic => loc.speciesHabitatPelagicNeritic,
      HabitatTag.pelagicOceanic => loc.speciesHabitatPelagicOceanic,
    };

String bodyFormLabel(AppLocalizations loc, BodyForm bodyForm) =>
    switch (bodyForm) {
      BodyForm.elongated => loc.speciesBodyFormElongated,
      BodyForm.fusiformNormal => loc.speciesBodyFormFusiformNormal,
      BodyForm.shortOrDeep => loc.speciesBodyFormShortOrDeep,
      BodyForm.eelLike => loc.speciesBodyFormEelLike,
      BodyForm.other => loc.speciesBodyFormOther,
    };

String humanRiskLabel(AppLocalizations loc, HumanRisk risk) =>
    switch (risk) {
      HumanRisk.harmless => loc.speciesHumanRiskHarmless,
      HumanRisk.venomous => loc.speciesHumanRiskVenomous,
      HumanRisk.traumatogenic => loc.speciesHumanRiskTraumatogenic,
      HumanRisk.ciguateraRisk => loc.speciesHumanRiskCiguateraRisk,
      HumanRisk.poisonousToEat => loc.speciesHumanRiskPoisonousToEat,
      HumanRisk.potentialPest => loc.speciesHumanRiskPotentialPest,
      HumanRisk.other => loc.speciesHumanRiskOther,
    };

String vulnerabilityLabel(AppLocalizations loc, VulnerabilityLevel level) =>
    switch (level) {
      VulnerabilityLevel.low => loc.speciesVulnerabilityLow,
      VulnerabilityLevel.moderate => loc.speciesVulnerabilityModerate,
      VulnerabilityLevel.high => loc.speciesVulnerabilityHigh,
      VulnerabilityLevel.veryHigh => loc.speciesVulnerabilityVeryHigh,
    };

String trophicLevelLabel(AppLocalizations loc, TrophicLevelCategory category,) =>
    switch (category) {
      TrophicLevelCategory.herbivore => loc.speciesTrophicHerbivore,
      TrophicLevelCategory.omnivore => loc.speciesTrophicOmnivore,
      TrophicLevelCategory.carnivore => loc.speciesTrophicCarnivore,
      TrophicLevelCategory.apexPredator => loc.speciesTrophicApexPredator,
    };
