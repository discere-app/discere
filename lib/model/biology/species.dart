import '../language.dart';
import 'classification.dart';
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
  final String? size;
  final String? depth;
  final String? habitat;
  final String? conservation;
  final String? dangerousToHumans;
  final String? fisheriesImportance;
  final String? longevityYears;
  final String? bodyShape;
  final String? trophicLevelFood;
  final List<String> traits;
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
    this.size,
    this.depth,
    this.habitat,
    this.conservation,
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
