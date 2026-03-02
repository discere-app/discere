import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

class FlashCardButtons extends StatelessWidget {
  final VoidCallback onAgain;
  final VoidCallback onHard;
  final VoidCallback onGood;
  final VoidCallback onEasy;

  const FlashCardButtons({
    required this.onAgain,
    required this.onHard,
    required this.onGood,
    required this.onEasy,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildRatingButton(
            context,
            label: context.loc.flashcardButtonAgain,
            time: '<1m',
            icon: Icons.sentiment_very_dissatisfied,
            color: Colors.redAccent,
            onPressed: onAgain,
          ),
          _buildRatingButton(
            context,
            label: context.loc.flashcardButtonHard,
            time: '12h',
            icon: Icons.sentiment_neutral,
            color: Colors.orangeAccent,
            onPressed: onHard,
          ),
          _buildRatingButton(
            context,
            label: context.loc.flashcardButtonGood,
            time: '1d',
            icon: Icons.sentiment_very_satisfied,
            color: Colors.tealAccent.shade400,
            onPressed: onGood,
          ),
          _buildRatingButton(
            context,
            label: context.loc.flashcardButtonEasy,
            time: '4d',
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
    required String label,
    required String time,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 6),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
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
