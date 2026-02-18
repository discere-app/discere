import '../language.dart';
import 'classification.dart';

class Species {
  final String id;
  final String scientificName;
  final Map<Language, String> commonNames;
  final Classification classification;
  final List<String> images;

  Species(
    this.id,
    this.scientificName,
    this.commonNames,
    this.classification,
    this.images,
  );

  String getBinomialName() {
    return "${classification.genusScientificName} $scientificName";
  }
}
