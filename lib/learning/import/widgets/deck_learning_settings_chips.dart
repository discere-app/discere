import 'package:discere/learning/decks/learning_mode_style.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The learning mode, name type and review mode a deck is reviewed with,
/// one informational chip each.
class DeckLearningSettingsChips extends StatelessWidget {
  static const _style = LearningModeStyle();
  static const double _iconSize = 14;

  final LearningMode learningMode;
  final NameType nameType;
  final ReviewMode reviewMode;

  const DeckLearningSettingsChips({
    super.key,
    required this.learningMode,
    required this.nameType,
    required this.reviewMode,
  });

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final theme = Theme.of(context);

    // A bare value such as "Species" does not say which setting it is, so
    // the tooltip (also read out by screen readers) names the setting.
    Widget chip(IconData icon, String setting, String value) {
      return Tooltip(
        message: '$setting: $value',
        child: Chip(
          avatar: Icon(icon, size: _iconSize),
          label: Text(value),
          labelStyle: theme.textTheme.labelSmall,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return Wrap(
      spacing: AppSpacing.s4,
      runSpacing: AppSpacing.s4,
      children: [
        chip(
          _style.iconFor(learningMode),
          loc.settingsLearningModeLabel,
          _style.labelFor(learningMode, loc),
        ),
        chip(
          _style.nameTypeIconFor(nameType),
          loc.settingsNameTypeLabel,
          _style.nameTypeLabelFor(nameType, loc),
        ),
        chip(
          _style.reviewModeIconFor(reviewMode),
          loc.settingsReviewModeTitle,
          _style.reviewModeLabelFor(reviewMode, loc),
        ),
      ],
    );
  }
}
