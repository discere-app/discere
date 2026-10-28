import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/learning/model/subdeck.dart';
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

  /// The subdecks switched on; empty for a deck without subdecks.
  final Set<String> activeSubdeckIds;

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
    required this.activeSubdeckIds,
  });

  /// Partial update for the fields the async loaders deliver piecemeal
  /// (deck config and species list). Deliberately excludes the fields that
  /// are only ever replaced wholesale via a fresh draft — in particular the
  /// nullable [coverImagePath], which a copyWith could not reset to null.
  EditDeckDraft copyWith({
    double? desiredRetention,
    LearningMode? learningMode,
    NameType? nameType,
    ReviewMode? reviewMode,
    Set<String>? speciesIds,
  }) {
    return EditDeckDraft(
      name: name,
      description: description,
      coverImagePath: coverImagePath,
      language: language,
      desiredRetention: desiredRetention ?? this.desiredRetention,
      learningMode: learningMode ?? this.learningMode,
      nameType: nameType ?? this.nameType,
      reviewMode: reviewMode ?? this.reviewMode,
      speciesIds: speciesIds ?? this.speciesIds,
      activeSubdeckIds: activeSubdeckIds,
    );
  }
}

/// Pure derived state for EditDeckPage: unsaved-changes detection and which
/// subdecks a draft leaves switched on. Kept free of BuildContext/widget
/// state so it can be unit tested directly, mirroring the presenter pattern
/// used elsewhere in catalog/. Multiple-choice validity is the create page's
/// too, and sits in `DeckModePresenter`; which subdecks may be switched off
/// is the merge dialog's too, and sits in `SubdeckMembership`.
class EditDeckPresenter {
  const EditDeckPresenter();

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
        !_setEquals(current.speciesIds, saved.speciesIds) ||
        !_setEquals(current.activeSubdeckIds, saved.activeSubdeckIds);
  }

  /// [activeSubdeckIds], or every one of [subdecks] when none is on and no
  /// species stands outside them any more — a draft that removes the last
  /// such species must not leave the deck without a card. Called after any
  /// mutation to species or subdecks, like the review-mode check.
  Set<String> effectiveActiveSubdecks({
    required Set<String> activeSubdeckIds,
    required List<Subdeck> subdecks,
    required bool hasSpeciesOutsideSubdecks,
  }) {
    if (activeSubdeckIds.isNotEmpty || hasSpeciesOutsideSubdecks) {
      return activeSubdeckIds;
    }
    return {for (final subdeck in subdecks) subdeck.id};
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}
