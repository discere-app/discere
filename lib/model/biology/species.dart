import '../language.dart';
import 'classification.dart';
import 'picture.dart';

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
  });

  String getBinomialName() {
    return "${classification.genusScientificName} $scientificName";
  }
}
