import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class FlashcardButtons extends StatelessWidget {
  final VoidCallback onAgain;
  final VoidCallback onHard;
  final VoidCallback onGood;
  final VoidCallback onEasy;
  final String timeAgain;
  final String timeHard;
  final String timeGood;
  final String timeEasy;
  final GlobalKey? againKey;
  final GlobalKey? hardKey;
  final GlobalKey? goodKey;
  final GlobalKey? easyKey;

  /// Renders as a vertical rail (icon + label, no time preview) instead of
  /// the default horizontal row — used in landscape, where the rail sits
  /// beside the card instead of below it and every bit of extra card height
  /// matters more than the time-preview text.
  final bool vertical;

  const FlashcardButtons({
    required this.onAgain,
    required this.onHard,
    required this.onGood,
    required this.onEasy,
    this.timeAgain = '',
    this.timeHard = '',
    this.timeGood = '',
    this.timeEasy = '',
    this.againKey,
    this.hardKey,
    this.goodKey,
    this.easyKey,
    this.vertical = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = [
      _buildRatingButton(
        context,
        buttonKey: againKey,
        label: context.loc.flashcardButtonAgain,
        time: timeAgain,
        icon: Icons.sentiment_very_dissatisfied,
        color: Colors.redAccent,
        onPressed: onAgain,
      ),
      _buildRatingButton(
        context,
        buttonKey: hardKey,
        label: context.loc.flashcardButtonHard,
        time: timeHard,
        icon: Icons.sentiment_neutral,
        color: Colors.orangeAccent,
        onPressed: onHard,
      ),
      _buildRatingButton(
        context,
        buttonKey: goodKey,
        label: context.loc.flashcardButtonGood,
        time: timeGood,
        icon: Icons.sentiment_very_satisfied,
        color: Colors.tealAccent.shade400,
        onPressed: onGood,
      ),
      _buildRatingButton(
        context,
        buttonKey: easyKey,
        label: context.loc.flashcardButtonEasy,
        time: timeEasy,
        icon: Icons.thumb_up_rounded,
        color: Colors.blueAccent,
        onPressed: onEasy,
      ),
    ];

    if (vertical) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: buttons,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s8,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: buttons),
    );
  }

  Widget _buildRatingButton(
    BuildContext context, {
    GlobalKey? buttonKey,
    required String label,
    required String time,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    // Landscape screens are short (a typical phone landscape body is only
    // ~256 logical px tall after system bars — easy to misjudge from a
    // screenshot, since those are physical pixels scaled by the device
    // pixel ratio), so the vertical rail has LESS headroom per button than
    // the horizontal row's own padding already uses, not more. Keep the
    // icon modestly bigger than portrait (users asked for more visual
    // presence) but keep padding/gap tight so it fits without the
    // FittedBox safety net having to shrink it back down.
    final iconSize = vertical ? 24.0 : 22.0;
    final content = Container(
      width: vertical ? double.infinity : null,
      padding: vertical
          ? const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s4,
            )
          : const EdgeInsets.symmetric(vertical: AppSpacing.s12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: iconSize),
            AppSpacing.heightS4,
            Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
            if (!vertical) ...[
              AppSpacing.heightS4,
              Text(
                time,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final tile = InkWell(
      key: buttonKey,
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: content,
    );

    return vertical
        ? Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
              child: tile,
            ),
          )
        : Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: tile,
            ),
          );
  }
}
