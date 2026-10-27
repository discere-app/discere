import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/decks/deck_mode_presenter.dart';
import 'package:discere/learning/decks/learning_mode_style.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// What a deck asks for and how: learning mode, name type and review mode,
/// as the create- and edit-deck pages both offer them. Multiple choice is
/// only selectable when [species] have enough distinct answer names in
/// [language] ([DeckModePresenter.canUseMultipleChoice]).
class DeckModeFields extends StatelessWidget {
  static const _style = LearningModeStyle();
  static const _presenter = DeckModePresenter();

  /// The deck's species, `null` while they are not known yet — which leaves
  /// multiple choice selectable.
  final List<Species>? species;
  final Language language;
  final LearningMode learningMode;
  final NameType nameType;
  final ReviewMode reviewMode;
  final ValueChanged<LearningMode> onLearningModeChanged;
  final ValueChanged<NameType> onNameTypeChanged;
  final ValueChanged<ReviewMode> onReviewModeChanged;

  const DeckModeFields({
    required this.species,
    required this.language,
    required this.learningMode,
    required this.nameType,
    required this.reviewMode,
    required this.onLearningModeChanged,
    required this.onNameTypeChanged,
    required this.onReviewModeChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final distinctNameCount = _presenter.distinctNameCount(
      species,
      language,
      learningMode,
      nameType,
    );
    final canUseMultipleChoice = _presenter.canUseMultipleChoice(
      distinctNameCount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.settingsLearningModeLabel,
          style: theme.textTheme.titleMedium,
        ),
        AppSpacing.heightS8,
        SegmentedButton<LearningMode>(
          key: const Key('learning_mode_segmented_button'),
          segments: [
            for (final mode in LearningMode.values)
              ButtonSegment<LearningMode>(
                value: mode,
                icon: Icon(_style.iconFor(mode)),
                label: Text(_style.labelFor(mode, context.loc)),
              ),
          ],
          selected: {learningMode},
          onSelectionChanged: (selection) {
            onLearningModeChanged(selection.single);
          },
        ),
        AppSpacing.heightS8,
        Text(
          _style.descriptionFor(learningMode, context.loc),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        AppSpacing.heightS16,
        Text(
          context.loc.settingsNameTypeLabel,
          style: theme.textTheme.titleMedium,
        ),
        AppSpacing.heightS8,
        SegmentedButton<NameType>(
          key: const Key('name_type_segmented_button'),
          segments: [
            for (final type in NameType.values)
              ButtonSegment<NameType>(
                value: type,
                icon: Icon(_style.nameTypeIconFor(type)),
                label: Text(_style.nameTypeLabelFor(type, context.loc)),
              ),
          ],
          selected: {nameType},
          onSelectionChanged: (selection) {
            onNameTypeChanged(selection.single);
          },
        ),
        AppSpacing.heightS8,
        Text(
          _style.nameTypeDescriptionFor(nameType, context.loc),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        AppSpacing.heightS16,
        Text(
          context.loc.settingsReviewModeLabel,
          style: theme.textTheme.titleMedium,
        ),
        AppSpacing.heightS8,
        SegmentedButton<ReviewMode>(
          key: const Key('review_mode_segmented_button'),
          segments: [
            ButtonSegment<ReviewMode>(
              value: ReviewMode.flip,
              icon: Icon(_style.reviewModeIconFor(ReviewMode.flip)),
              label: Text(context.loc.settingsReviewModeFlip),
            ),
            ButtonSegment<ReviewMode>(
              value: ReviewMode.multipleChoice,
              icon: Icon(_style.reviewModeIconFor(ReviewMode.multipleChoice)),
              label: Text(context.loc.settingsReviewModeMultipleChoice),
              enabled: canUseMultipleChoice,
            ),
          ],
          selected: {reviewMode},
          onSelectionChanged: (selection) {
            onReviewModeChanged(selection.single);
          },
        ),
        AppSpacing.heightS8,
        Text(
          reviewMode == ReviewMode.multipleChoice
              ? context.loc.settingsReviewModeDescriptionMultipleChoice
              : context.loc.settingsReviewModeDescriptionFlip,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (distinctNameCount != null && !canUseMultipleChoice) ...[
          AppSpacing.heightS8,
          Text(
            context.loc.settingsReviewModeInsufficientSpecies(
              distinctNameCount,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
