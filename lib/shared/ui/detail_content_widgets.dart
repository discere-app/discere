import 'package:flutter/material.dart';

import 'package:discere/shared/ui/copyable_text.dart';

import '../../theme/app_spacing.dart';

class DetailSectionCard extends StatelessWidget {
  final Widget child;

  const DetailSectionCard({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
          ),
        ),
        child: child,
      ),
    );
  }
}

class DetailBulletRow extends StatelessWidget {
  final String label;
  final bool copyable;

  const DetailBulletRow({
    required this.label,
    this.copyable = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: AppSpacing.s8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: copyable
                ? CopyableText(
                    text: label,
                    style: theme.textTheme.bodyMedium,
                    copiedStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Text(label, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class DetailKeyValueRow extends StatelessWidget {
  final String label;
  final String primary;
  final String? secondary;
  final bool italicPrimary;
  final bool copyablePrimary;
  final bool copyableSecondary;

  const DetailKeyValueRow({
    required this.label,
    required this.primary,
    this.secondary,
    this.italicPrimary = false,
    this.copyablePrimary = false,
    this.copyableSecondary = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              letterSpacing: 0.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              copyablePrimary
                  ? CopyableText(
                      text: primary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: italicPrimary ? FontStyle.italic : null,
                      ),
                      copiedStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        fontStyle: italicPrimary ? FontStyle.italic : null,
                      ),
                    )
                  : Text(
                      primary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: italicPrimary ? FontStyle.italic : null,
                      ),
                    ),
              if (secondary != null && secondary!.isNotEmpty)
                copyableSecondary
                    ? CopyableText(
                        text: secondary!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        ),
                        copiedStyle: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Text(
                        secondary!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ),
            ],
          ),
        ),
      ],
    );
  }
}
