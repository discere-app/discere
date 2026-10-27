import 'package:discere/learning/decks/learning_mode_style.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The learning mode, name type and review mode a deck is reviewed with,
/// one icon each.
class DeckLearningSettingsIcons extends StatelessWidget {
  static const _style = LearningModeStyle();
  static const double _iconSize = 16;

  final LearningMode learningMode;
  final NameType nameType;
  final ReviewMode reviewMode;

  const DeckLearningSettingsIcons({
    super.key,
    required this.learningMode,
    required this.nameType,
    required this.reviewMode,
  });

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    // The icons carry no label, so the tooltip is the value's only text and
    // what screen readers read out; it names the setting too, since a bare
    // value such as "Species" does not say which setting it is.
    Widget iconWithTooltip(IconData icon, String setting, String value) {
      return Tooltip(
        message: loc.importOnlineLearningSettingTooltip(setting, value),
        child: Icon(icon, size: _iconSize, color: color),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.s8,
      children: [
        iconWithTooltip(
          _style.iconFor(learningMode),
          loc.settingsLearningModeLabel,
          _style.labelFor(learningMode, loc),
        ),
        iconWithTooltip(
          _style.nameTypeIconFor(nameType),
          loc.settingsNameTypeLabel,
          _style.nameTypeLabelFor(nameType, loc),
        ),
        iconWithTooltip(
          _style.reviewModeIconFor(reviewMode),
          loc.settingsReviewModeTitle,
          _style.reviewModeLabelFor(reviewMode, loc),
        ),
      ],
    );
  }
}
