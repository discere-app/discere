import 'package:discere/theme/app_spacing.dart';
import 'package:discere/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';

/// Bordered, softly-filled placeholder shown in place of a missing image —
/// an icon over a caption. Sized by whatever the caller wraps it in
/// (`SizedBox`, `AspectRatio`, a `Stack` with `StackFit.expand`, ...).
class ImagePlaceholder extends StatelessWidget {
  final IconData icon;
  final String label;
  final BorderRadius borderRadius;

  const ImagePlaceholder({
    required this.icon,
    required this.label,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: borderRadius,
        border: Border.all(color: theme.sectionBorderColor),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colorScheme.onSurfaceVariant),
            AppSpacing.heightS8,
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
