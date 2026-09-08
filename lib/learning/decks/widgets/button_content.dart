import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

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
