import 'package:discere/learning/decks/learning_mode_style.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

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
      learningMode != LearningMode.species ||
      nameType != NameType.commonName ||
      reviewMode != ReviewMode.flip;

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
      if (learningMode != LearningMode.species)
        iconWithTooltip(
          _style.iconFor(learningMode),
          _style.labelFor(learningMode, loc),
        ),
      if (nameType != NameType.commonName)
        iconWithTooltip(
          _style.nameTypeIconFor(nameType),
          _style.nameTypeLabelFor(nameType, loc),
        ),
      if (reviewMode != ReviewMode.flip)
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
