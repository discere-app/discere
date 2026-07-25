import 'package:discere/learning/decks/edit/edit_deck_presenter.dart';
import 'package:discere/learning/decks/learning_mode_style.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Edit-deck section for the deck's learning configuration: learning mode,
/// name type, review mode, and desired retention. Multiple choice is only
/// selectable when enough distinct answer names exist ([distinctNameCount]
/// vs. [EditDeckPresenter.minSpeciesForMultipleChoice]).
class LearningSettingsSection extends StatelessWidget {
  static const _style = LearningModeStyle();
  static const _presenter = EditDeckPresenter();

  final double desiredRetention;
  final LearningMode learningMode;
  final NameType nameType;
  final ReviewMode reviewMode;
  final int distinctNameCount;
  final ValueChanged<double> onRetentionChanged;
  final ValueChanged<LearningMode> onLearningModeChanged;
  final ValueChanged<NameType> onNameTypeChanged;
  final ValueChanged<ReviewMode> onReviewModeChanged;

  const LearningSettingsSection({
    required this.desiredRetention,
    required this.learningMode,
    required this.nameType,
    required this.reviewMode,
    required this.distinctNameCount,
    required this.onRetentionChanged,
    required this.onLearningModeChanged,
    required this.onNameTypeChanged,
    required this.onReviewModeChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pct = (desiredRetention * 100).round();
    final canUseMultipleChoice = _presenter.canUseMultipleChoice(
      distinctNameCount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.settingsLearningTitle,
          style: theme.textTheme.titleSmall,
        ),
        AppSpacing.heightS8,
        SectionCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s16,
              AppSpacing.s16,
              AppSpacing.s8,
            ),
            child: Column(
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
                      icon: Icon(
                        _style.reviewModeIconFor(ReviewMode.multipleChoice),
                      ),
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
                if (!canUseMultipleChoice) ...[
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
                AppSpacing.heightS16,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.loc.settingsRetentionLabel,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      '$pct %',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                Slider(
                  key: const Key('retention_slider'),
                  value: desiredRetention,
                  min: 0.70,
                  max: 0.97,
                  divisions: 27,
                  onChanged: onRetentionChanged,
                ),
                Text(
                  context.loc.settingsRetentionSliderDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
