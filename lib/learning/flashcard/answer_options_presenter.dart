import 'dart:math';

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
