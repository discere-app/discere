import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class ParticipateItem extends StatelessWidget {
  const ParticipateItem({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colorScheme.primary),
        AppSpacing.widthS12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              AppSpacing.heightS4,
              Text(description),
            ],
          ),
        ),
      ],
    );
  }
}
