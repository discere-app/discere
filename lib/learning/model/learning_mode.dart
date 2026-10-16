import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/taxon_rank.dart';

/// Which taxonomic rank a deck asks the user to recall.
///
/// A species deck shows the animal and asks for the species; a genus deck
/// asks only for the genus, which is what a beginner can realistically name
/// from a photo.
enum LearningMode {
  species,
  genus,
  family;

  String get storageValue => name;

  /// Whether this mode would ask for a source's rank placeholder ("Not
  /// assigned") when shown [species] — a name that is no answer, and no
  /// distractor either.
  bool asksPlaceholderFor(Species species) {
    final rank = switch (this) {
      LearningMode.species => null,
      LearningMode.genus => TaxonRank.genus,
      LearningMode.family => TaxonRank.family,
    };
    return rank != null && species.classification.isPlaceholder(rank);
  }

  static LearningMode fromStorage(String? value) {
    return LearningMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => LearningMode.species,
    );
  }
}
