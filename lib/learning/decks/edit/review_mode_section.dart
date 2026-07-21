import 'package:discere/learning/decks/learning_mode_style.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Edit-deck section for choosing the review mode. Multiple choice is only
/// selectable when enough distinct answer names exist ([distinctNameCount]
/// vs. [minSpeciesRequired]).
class ReviewModeSection extends StatelessWidget {
  static const _style = LearningModeStyle();

  final ReviewMode reviewMode;
  final int distinctNameCount;
  final int minSpeciesRequired;
  final ValueChanged<ReviewMode> onReviewModeChanged;

  const ReviewModeSection({
    required this.reviewMode,
    required this.distinctNameCount,
    required this.minSpeciesRequired,
    required this.onReviewModeChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canUseMultipleChoice = distinctNameCount >= minSpeciesRequired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.loc.settingsReviewModeTitle,
          style: theme.textTheme.titleSmall,
        ),
        AppSpacing.heightS8,
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.s16),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.loc.settingsReviewModeLabel,
                style: theme.textTheme.bodyMedium,
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
            ],
          ),
        ),
      ],
    );
  }
}
