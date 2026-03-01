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
            label: 'Again',
            time: '<1m',
            color: Colors.redAccent,
            onPressed: onAgain,
          ),
          _buildRatingButton(
            context,
            label: 'Hard',
            time: '12h',
            color: Colors.orangeAccent,
            onPressed: onHard,
          ),
          _buildRatingButton(
            context,
            label: 'Good',
            time: '1d',
            color: Colors.tealAccent.shade400,
            onPressed: onGood,
          ),
          _buildRatingButton(
            context,
            label: 'Easy',
            time: '4d',
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
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
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
