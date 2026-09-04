import 'dart:math';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/flashcard/flashcard_species_presenter.dart';
import 'package:discere/learning/flashcard/multiple_choice_option.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';

/// Builds the 4 answer options (1 correct + 3 distractors) for multiple-choice
/// review mode, reusing [FlashcardSpeciesPresenter] so option labels are
/// always identical to what the flip-mode back content would show.
class AnswerOptionsPresenter {
  final FlashcardSpeciesPresenter _speciesPresenter;

  const AnswerOptionsPresenter({
    FlashcardSpeciesPresenter speciesPresenter =
        const FlashcardSpeciesPresenter(),
  }) : _speciesPresenter = speciesPresenter;

  /// The distinct, deduplicated (case-insensitive) primary names for all
  /// species in a deck, given [language], [learningMode] and [nameType]. This
  /// is the pool multiple-choice distractors are drawn from, and also the
  /// source of truth for "does this deck have enough distinct names for
  /// multiple choice".
  List<String> distinctPrimaryNames(
    Iterable<Species> deckSpecies,
    Language language,
    LearningMode learningMode, [
    NameType nameType = NameType.commonName,
  ]) {
    final names = deckSpecies.map(
      (species) => _speciesPresenter
          .present(
            species,
            language,
            learningMode: learningMode,
            nameType: nameType,
          )
          .identity
          .primaryName,
    );
    return deduplicateCommonNames(names);
  }

  /// Taxonomically-scoped candidate names for [currentSpecies]'s multiple-choice
  /// distractors, drawn only from [deckSpecies] (no database access — pure
  /// in-memory filtering). Prefers the rank immediately above the one being
  /// tested (same genus for species mode, same family for genus mode, same
  /// order for family mode); if that doesn't yield [minimumDistinctNames]
  /// distinct names, escalates to progressively coarser ranks (family, order,
  /// class) until enough are found or the chain is exhausted.
  List<String> taxonomicPoolFromDeck({
    required Species currentSpecies,
    required Iterable<Species> deckSpecies,
    required Language language,
    required LearningMode learningMode,
    NameType nameType = NameType.commonName,
    int minimumDistinctNames = 3,
  }) {
    final currentGroupId = _groupId(learningMode, currentSpecies);
    final candidatesByGroupId = <String, Species>{};
    for (final species in deckSpecies) {
      final groupId = _groupId(learningMode, species);
      if (groupId == null || groupId == currentGroupId) continue;
      candidatesByGroupId.putIfAbsent(groupId, () => species);
    }

    final scopeChain = _ancestorIds(learningMode, currentSpecies.classification);
    final collected = <String>[];
    for (var rank = 0; rank < scopeChain.length; rank++) {
      final scopeId = scopeChain[rank];
      if (scopeId == null) continue;

      for (final candidate in candidatesByGroupId.values) {
        final candidateAncestors = _ancestorIds(
          learningMode,
          candidate.classification,
        );
        if (candidateAncestors[rank] != scopeId) continue;
        collected.add(
          _speciesPresenter
              .present(
                candidate,
                language,
                learningMode: learningMode,
                nameType: nameType,
              )
              .identity
              .primaryName,
        );
      }

      if (deduplicateCommonNames(collected).length >= minimumDistinctNames) {
        break;
      }
    }

    return deduplicateCommonNames(collected);
  }

  /// The id identifying which rank-appropriate group [species] belongs to
  /// for [learningMode] — its own id for species mode, its genus id for
  /// genus mode, its family id for family mode.
  String? _groupId(LearningMode learningMode, Species species) =>
      switch (learningMode) {
        LearningMode.species => species.id,
        LearningMode.genus => species.classification.genusId,
        LearningMode.family => species.classification.familyId,
      };

  /// Ancestor ids of [classification], nearest rank first, for the ranks
  /// above the one [learningMode] tests — e.g. for species mode:
  /// [genusId, familyId, orderId, classId].
  List<String?> _ancestorIds(
    LearningMode learningMode,
    Classification classification,
  ) => switch (learningMode) {
    LearningMode.species => [
      classification.genusId,
      classification.familyId,
      classification.orderId,
      classification.classId,
    ],
    LearningMode.genus => [
      classification.familyId,
      classification.orderId,
      classification.classId,
    ],
    LearningMode.family => [classification.orderId, classification.classId],
  };

  /// Builds [optionCount] shuffled answer options for [correctLabel], drawing
  /// distractors from [namePool]. Returns `null` if [namePool] does not
  /// contain enough distinct names (other than [correctLabel]) to fill the
  /// remaining options.
  List<MultipleChoiceOption>? buildOptions({
    required String correctLabel,
    required List<String> namePool,
    int optionCount = 4,
    Random? random,
  }) {
    final normalizedCorrectLabel = normalizeCommonName(correctLabel);
    final distractorPool = namePool
        .where((name) => normalizeCommonName(name) != normalizedCorrectLabel)
        .toList();

    final requiredDistractors = optionCount - 1;
    if (distractorPool.length < requiredDistractors) return null;

    final rng = random ?? Random();
    distractorPool.shuffle(rng);

    final options = <MultipleChoiceOption>[
      MultipleChoiceOption(label: correctLabel, isCorrect: true),
      ...distractorPool
          .take(requiredDistractors)
          .map((label) => MultipleChoiceOption(label: label, isCorrect: false)),
    ];
    options.shuffle(rng);
    return options;
  }
}
