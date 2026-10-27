import 'package:discere/catalog/model/species.dart';
import 'package:discere/learning/decks/deck_form_fields.dart';
import 'package:discere/learning/decks/deck_mode_fields.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Edit-deck section for the deck's learning configuration: language,
/// learning mode, name type, review mode, and desired retention. Language
/// lives here (rather than with the basic-info fields) because it's
/// functionally coupled to the rest — it decides the distinct common names
/// per language and therefore multiple-choice availability, the same kind
/// of dependency [DeckModeFields] manages between learning mode, name type,
/// and review mode.
class LearningSettingsSection extends StatelessWidget {
  final Language language;
  final double desiredRetention;
  final LearningMode learningMode;
  final NameType nameType;
  final ReviewMode reviewMode;

  /// The deck's species, which decide whether multiple choice is offered.
  final List<Species> species;
  final ValueChanged<Language> onLanguageChanged;
  final ValueChanged<double> onRetentionChanged;
  final ValueChanged<LearningMode> onLearningModeChanged;
  final ValueChanged<NameType> onNameTypeChanged;
  final ValueChanged<ReviewMode> onReviewModeChanged;

  /// Coach-mark target for [EditDeckTutorial] — kept on just the section
  /// title rather than the whole (often taller-than-viewport) section, so
  /// the spotlight and its explanation text both actually fit on screen.
  final GlobalKey? titleKey;

  const LearningSettingsSection({
    required this.language,
    required this.desiredRetention,
    required this.learningMode,
    required this.nameType,
    required this.reviewMode,
    required this.species,
    required this.onLanguageChanged,
    required this.onRetentionChanged,
    required this.onLearningModeChanged,
    required this.onNameTypeChanged,
    required this.onReviewModeChanged,
    this.titleKey,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pct = (desiredRetention * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: titleKey,
          child: Text(
            context.loc.settingsLearningTitle,
            style: theme.textTheme.titleSmall,
          ),
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
                DeckLanguageField(
                  value: language,
                  onChanged: onLanguageChanged,
                ),
                AppSpacing.heightS16,
                DeckModeFields(
                  species: species,
                  language: language,
                  learningMode: learningMode,
                  nameType: nameType,
                  reviewMode: reviewMode,
                  onLearningModeChanged: onLearningModeChanged,
                  onNameTypeChanged: onNameTypeChanged,
                  onReviewModeChanged: onReviewModeChanged,
                ),
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
