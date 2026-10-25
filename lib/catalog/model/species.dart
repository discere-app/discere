import 'package:discere/catalog/model/body_form.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/fishing_importance.dart';
import 'package:discere/catalog/model/habitat_tag.dart';
import 'package:discere/catalog/model/human_risk.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species_native_region.dart';
import 'package:discere/catalog/model/species_status.dart';
import 'package:discere/shared/model/language.dart';

class Species {
  final String id;
  final String externalId;
  final String externalSource;

  /// The epithet, without the genus — see [binomialName] for the full name.
  final String scientificName;

  /// The full scientific name the species' source prefers for it, such as
  /// "Gattya humilis". Only needed — and only loaded — for a species without
  /// a genus, whose epithet alone names nothing; with a genus, the full name
  /// is genus and epithet.
  final String? preferredScientificName;
  final Map<Language, List<String>> commonNames;
  final Classification classification;
  final List<Picture> pictures;
  final double? maxLengthCm;
  final double? depthMinM;
  final double? depthMaxM;
  final String? habitat;
  final HabitatTag? habitatTag;

  /// FishBase/SeaLifeBase vulnerability score on a 0-100 scale.
  final double? conservation;
  final String? dangerousToHumansRaw;
  final HumanRisk? dangerousToHumans;

  /// Candidate for removal from the user-facing species detail quick facts.
  final FishingImportance? fisheriesImportance;

  /// Observed or published lifespan in the wild, measured in years.
  final double? longevityYears;
  final BodyForm? bodyShape;

  /// Food-based trophic level. In FishBase/SeaLifeBase, primary producers and
  /// detritus are level 1, herbivores 2.0, carnivorous fishes typically 3.0
  /// to 4.5, and the highest aquatic values reach about 5.5.
  final double? trophicLevelFood;
  final List<HabitatTag> traits;
  final List<SpeciesNativeRegion> nativeRegions;
  final SpeciesStatus status;

  Species(
    this.id,
    this.externalId,
    this.externalSource,
    this.scientificName,
    this.commonNames,
    this.classification,
    this.pictures, {
    this.preferredScientificName,
    this.maxLengthCm,
    this.depthMinM,
    this.depthMaxM,
    this.habitat,
    this.habitatTag,
    this.conservation,
    this.dangerousToHumansRaw,
    this.dangerousToHumans,
    this.fisheriesImportance,
    this.longevityYears,
    this.bodyShape,
    this.trophicLevelFood,
    this.traits = const [],
    this.nativeRegions = const [],
    this.status = SpeciesStatus.active,
  });

  bool get isDeprecated => status == SpeciesStatus.deprecated;

  /// The species' full scientific name: "Genus epithet", or for a species
  /// without a genus its [preferredScientificName]. `null` when it has
  /// neither — its epithet alone is no binomial, and a search by it would
  /// find whichever species shares the epithet.
  String? get binomialName {
    final genus = classification.genusScientificName;
    return genus == null ? preferredScientificName : '$genus $scientificName';
  }

  /// The species' scientific name to show — its [binomialName], or the
  /// epithet alone when it has none. Not a name to search a source by.
  String getBinomialName() => binomialName ?? scientificName;
}
