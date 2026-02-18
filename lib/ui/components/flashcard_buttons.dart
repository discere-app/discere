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
    ThemeData theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          onPressed: onThumbDown,
          icon: Icon(
            Icons.thumb_down,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          label: Text(context.loc.flashcardButtonNegative),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.secondary,
            foregroundColor: theme.colorScheme.onError,
          ),
        ),
        ElevatedButton.icon(
          onPressed: onThumbUp,
          icon: Icon(
            Icons.thumb_up,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          label: Text(context.loc.flashcardButtonPositive),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
        ),
      ],
    );
  }
}
