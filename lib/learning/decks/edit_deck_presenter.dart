import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/flashcard/answer_options_presenter.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/model/language.dart';

/// A snapshot of every field EditDeckPage lets the user edit, used to detect
/// unsaved changes and to describe the review-mode-validity inputs. Two
/// drafts (current vs. last-saved) are compared field-by-field in
/// [EditDeckPresenter.isDirty].
class EditDeckDraft {
  final String name;
  final String description;
  final String? coverImagePath;
  final Language language;
  final double desiredRetention;
  final LearningMode learningMode;
  final NameType nameType;
  final ReviewMode reviewMode;
  final Set<String> speciesIds;

  const EditDeckDraft({
    required this.name,
    required this.description,
    required this.coverImagePath,
    required this.language,
    required this.desiredRetention,
    required this.learningMode,
    required this.nameType,
    required this.reviewMode,
    required this.speciesIds,
  });
}

/// Pure derived state for EditDeckPage: unsaved-changes detection and
/// multiple-choice review-mode validity. Kept free of BuildContext/widget
/// state so it can be unit tested directly, mirroring the presenter pattern
/// used elsewhere in catalog/.
class EditDeckPresenter {
  static const int minSpeciesForMultipleChoice = 4;

  final AnswerOptionsPresenter _answerOptionsPresenter;

  const EditDeckPresenter({
    AnswerOptionsPresenter answerOptionsPresenter =
        const AnswerOptionsPresenter(),
  }) : _answerOptionsPresenter = answerOptionsPresenter;

  /// Number of distinct primary names available as multiple-choice
  /// distractors for [species] under [language]/[learningMode]/[nameType].
  int distinctNameCount(
    List<Species> species,
    Language language,
    LearningMode learningMode,
    NameType nameType,
  ) => _answerOptionsPresenter
      .distinctPrimaryNames(species, language, learningMode, nameType)
      .length;

  bool canUseMultipleChoice(int distinctNameCount) =>
      distinctNameCount >= minSpeciesForMultipleChoice;

  /// Reverts [reviewMode] to flip if multiple choice is selected but
  /// [distinctNameCount] no longer supports it (e.g. species removed,
  /// learning mode, name type, or language changed). Called after any
  /// mutation to species/language/learning mode/name type.
  ReviewMode effectiveReviewMode({
    required ReviewMode reviewMode,
    required int distinctNameCount,
  }) {
    if (reviewMode == ReviewMode.multipleChoice &&
        !canUseMultipleChoice(distinctNameCount)) {
      return ReviewMode.flip;
    }
    return reviewMode;
  }

  /// Whether [current] differs from [saved] in any field the Save button
  /// cares about. Name/description are trimmed before comparing, matching
  /// what actually gets persisted.
  bool isDirty(EditDeckDraft current, EditDeckDraft saved) {
    return current.name.trim() != saved.name.trim() ||
        current.description.trim() != saved.description.trim() ||
        current.coverImagePath != saved.coverImagePath ||
        current.language != saved.language ||
        current.desiredRetention != saved.desiredRetention ||
        current.learningMode != saved.learningMode ||
        current.nameType != saved.nameType ||
        current.reviewMode != saved.reviewMode ||
        !_setEquals(current.speciesIds, saved.speciesIds);
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}
