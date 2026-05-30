import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

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
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
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
        ],
      ),
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
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
        child: InkWell(
          key: buttonKey,
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 22),
                AppSpacing.heightS8,
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: color,
                  ),
                ),
                AppSpacing.heightS4,
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
