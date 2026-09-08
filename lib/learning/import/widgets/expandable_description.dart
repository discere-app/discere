import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class ExpandableDescription extends StatelessWidget {
  final String text;
  final String speciesCountLabel;
  final bool isExpanded;

  const ExpandableDescription({
    super.key,
    required this.text,
    required this.speciesCountLabel,
    required this.isExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!isExpanded) {
      return Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(speciesCountLabel, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
