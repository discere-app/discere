import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class HintRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;

  /// Label above value instead of side-by-side — used in the narrow
  /// landscape hints column, where there isn't room for the portrait
  /// Row layout's fixed-width label column.
  final bool stacked;

  /// Portrait dims this to a quiet secondary note below the image. Landscape
  /// has nothing else in its hints column competing for attention, so it
  /// uses full contrast instead of reading as a disabled/low-priority label.
  final bool muted;

  const HintRow({
    super.key,
    required this.label,
    required this.value,
    required this.theme,
    this.stacked = false,
    this.muted = true,
  });

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label.toUpperCase(),
      style: theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
        color: theme.colorScheme.onSurface.withValues(alpha: muted ? 0.4 : 0.6),
      ),
    );
    final valueText = Text(
      value,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: muted ? null : 14,
        color: muted
            ? theme.colorScheme.onSurface.withValues(alpha: 0.85)
            : theme.colorScheme.primary,
      ),
    );

    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [labelText, AppSpacing.heightS4, valueText],
      );
    }

    return Row(
      children: [
        SizedBox(width: 80, child: labelText),
        AppSpacing.widthS12,
        Expanded(child: valueText),
      ],
    );
  }
}
