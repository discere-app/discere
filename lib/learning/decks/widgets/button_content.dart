import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Lays out an action button's icon + label + trailing mode-icon column in
/// one row, so the mode icons render as part of the button's own content
/// (inheriting its foreground color) instead of a separately styled sibling.
class ButtonContent extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? modeIcons;

  const ButtonContent({
    super.key,
    required this.icon,
    required this.label,
    required this.modeIcons,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        AppSpacing.widthS8,
        Expanded(
          child: Center(child: Text(label, textAlign: TextAlign.left)),
        ),
        if (modeIcons != null) ...[AppSpacing.widthS8, modeIcons!],
      ],
    );
  }
}
