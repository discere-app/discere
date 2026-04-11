import 'package:discere/shared/model/language.dart';
import 'body_form.dart';
import 'classification.dart';
import 'fishing_importance.dart';
import 'habitat_tag.dart';
import 'human_risk.dart';
import 'picture.dart';
import 'species_native_region.dart';

class Species {
  final String id;
  final String externalId;
  final String externalSource;
  final String scientificName;
  final Map<Language, String> commonNames;
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
  final FishingImportance? fisheriesImportance;
  /// Observed or published lifespan in the wild, measured in years.
  final double? longevityYears;
  final BodyForm? bodyShape;
  final String? trophicLevelFood;
  final List<HabitatTag> traits;
  final List<SpeciesNativeRegion> nativeRegions;
  final String status;

  Species(
    this.id,
    this.externalId,
    this.externalSource,
    this.scientificName,
    this.commonNames,
    this.classification,
    this.pictures, {
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
    this.status = 'active',
  });

  bool get isDeprecated => status == 'deprecated';

  String getBinomialName() {
    return "${classification.genusScientificName} $scientificName";
  }
}
