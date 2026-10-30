import 'package:discere/learning/decks/learning_mode_style.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

/// Icons for whichever of learning mode / name type / review mode deviate
/// from the deck defaults (species / common name / flip), stacked vertically
/// at the trailing edge of the deck's start/practice button content, using
/// the button's own foreground color (dimmed) so they read as part of the
/// button rather than a separate element next to it. Placed inside the
/// button rather than on the cover image or next to the title because it's
/// the one spot on the card that exists unconditionally, regardless of
/// whether the deck has a cover image. Non-default settings are the
/// exception, not the rule, so decks left on defaults show no icons at all.
class LearningModeIconColumn extends StatelessWidget {
  static const _style = LearningModeStyle();
  static const double _iconSize = 14;

  final LearningMode learningMode;
  final NameType nameType;
  final ReviewMode reviewMode;

  const LearningModeIconColumn({
    super.key,
    required this.learningMode,
    required this.nameType,
    required this.reviewMode,
  });

  static bool hasNonDefault({
    required LearningMode learningMode,
    required NameType nameType,
    required ReviewMode reviewMode,
  }) =>
      learningMode != DeckConfig.defaultLearningMode ||
      nameType != DeckConfig.defaultNameType ||
      reviewMode != DeckConfig.defaultReviewMode;

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final color =
        (IconTheme.of(context).color ?? Theme.of(context).colorScheme.onPrimary)
            .withValues(alpha: 0.7);

    Widget iconWithTooltip(IconData icon, String tooltip) {
      return Tooltip(
        message: tooltip,
        child: Icon(icon, size: _iconSize, color: color),
      );
    }

    final icons = [
      if (learningMode != DeckConfig.defaultLearningMode)
        iconWithTooltip(
          _style.iconFor(learningMode),
          _style.labelFor(learningMode, loc),
        ),
      if (nameType != DeckConfig.defaultNameType)
        iconWithTooltip(
          _style.nameTypeIconFor(nameType),
          _style.nameTypeLabelFor(nameType, loc),
        ),
      if (reviewMode != DeckConfig.defaultReviewMode)
        iconWithTooltip(
          _style.reviewModeIconFor(reviewMode),
          _style.reviewModeLabelFor(reviewMode, loc),
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < icons.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          icons[i],
        ],
      ],
    );
  }
}
