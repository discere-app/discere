import 'package:discere/learning/decks/edit/subdeck_draft.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/learning/model/subdeck_membership.dart';
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

  final SubdeckDraft subdecks;

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
    required this.subdecks,
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
      subdecks: subdecks,
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
        !current.subdecks.hasSameContentAs(saved.subdecks);
  }

  /// The subdecks of [subdecks] to have on for a deck of [speciesIds]: the
  /// ones on, or all of them when that leaves a deck with species without a
  /// card — as a draft does that removes the last species outside the subdecks
  /// or moves the last card into a subdeck that is off. A deck without species
  /// has no card to lose. Called after any mutation to species or subdecks,
  /// like the review-mode check.
  Set<String> effectiveActiveSubdecks(
    SubdeckDraft subdecks,
    Set<String> speciesIds,
  ) {
    final membership = SubdeckMembership.of(
      speciesIds,
      subdecks.subdeckIdBySpeciesId,
    );
    if (speciesIds.isEmpty ||
        membership.hasCardWith(subdecks.activeSubdeckIds)) {
      return subdecks.activeSubdeckIds;
    }
    return {for (final subdeck in subdecks.subdecks) subdeck.id};
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}
