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

  /// The rank this mode asks for, `null` for the species itself.
  TaxonRank? get askedRank => switch (this) {
    LearningMode.species => null,
    LearningMode.genus => TaxonRank.genus,
    LearningMode.family => TaxonRank.family,
  };

  /// Whether [species] has no answer in this mode: the rank asked for
  /// assigns it to no taxon, being a source's rank placeholder ("Not
  /// assigned") or missing from its chain. Such a species is no card in
  /// this mode, and its name no distractor. Every species has an answer in
  /// species mode.
  bool hasNoAnswerFor(Species species) =>
      hasNoAnswerGiven(species.classification.unassignedRanks);

  /// [hasNoAnswerFor] for a species known only by the ranks that assign it
  /// to no taxon (`Classification.unassignedRanks`) — what a check across a
  /// whole deck loads instead of every species in full.
  bool hasNoAnswerGiven(Set<TaxonRank> unassignedRanks) {
    final rank = askedRank;
    return rank != null && unassignedRanks.contains(rank);
  }

  static LearningMode fromStorage(String? value) {
    return LearningMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => LearningMode.species,
    );
  }
}
