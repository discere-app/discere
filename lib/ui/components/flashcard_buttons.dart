import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

class FlashCardButtons extends StatelessWidget {
  final VoidCallback onThumbUp;
  final VoidCallback onThumbDown;

  const FlashCardButtons({
    required this.onThumbUp,
    required this.onThumbDown,
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
            onPressed: onThumbDown,
          ),
          _buildRatingButton(
            context,
            label: 'Hard',
            time: '10m',
            color: Colors.orangeAccent,
            onPressed: onThumbDown,
          ),
          _buildRatingButton(
            context,
            label: 'Good',
            time: '1d',
            color: Colors.tealAccent.shade400,
            onPressed: onThumbUp,
          ),
          _buildRatingButton(
            context,
            label: 'Easy',
            time: '4d',
            color: Colors.blueAccent,
            onPressed: onThumbUp,
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
