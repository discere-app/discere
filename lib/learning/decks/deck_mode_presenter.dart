import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/flashcard/answer_options_presenter.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/shared/model/language.dart';

/// Whether a deck's species support multiple choice, under the learning
/// mode, name type and language chosen for it — the one rule the create-
/// and edit-deck pages offer that review mode by.
class DeckModePresenter {
  /// As many distinct names as a distractor pool needs: the pool builder
  /// falls back to the whole deck, so a deck that holds them gives every
  /// card its answer options (see `MultipleChoiceDistractorPoolService`).
  static const int minSpeciesForMultipleChoice =
      AnswerOptionsPresenter.minimumPoolSize;

  final AnswerOptionsPresenter _answerOptionsPresenter;

  const DeckModePresenter({
    AnswerOptionsPresenter answerOptionsPresenter =
        const AnswerOptionsPresenter(),
  }) : _answerOptionsPresenter = answerOptionsPresenter;

  /// Number of distinct primary names available as multiple-choice
  /// distractors for [species] under [language]/[learningMode]/[nameType];
  /// `null` while the species are not known yet.
  int? distinctNameCount(
    List<Species>? species,
    Language language,
    LearningMode learningMode,
    NameType nameType,
  ) => species == null
      ? null
      : _answerOptionsPresenter
            .distinctPrimaryNames(species, language, learningMode, nameType)
            .length;

  /// Whether multiple choice can be chosen for [distinctNameCount] names. A
  /// count not known yet does not rule it out: a card short of answer
  /// options falls back to flipping during review on its own.
  bool canUseMultipleChoice(int? distinctNameCount) =>
      distinctNameCount == null ||
      distinctNameCount >= minSpeciesForMultipleChoice;

  /// [reviewMode], or flip where it is multiple choice and
  /// [distinctNameCount] does not support it.
  ReviewMode effectiveReviewMode({
    required ReviewMode reviewMode,
    required int? distinctNameCount,
  }) {
    if (reviewMode == ReviewMode.multipleChoice &&
        !canUseMultipleChoice(distinctNameCount)) {
      return ReviewMode.flip;
    }
    return reviewMode;
  }
}
