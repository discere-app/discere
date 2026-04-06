import 'package:flutter/material.dart';

import '../../model/search/search_result.dart';
import '../../theme/app_spacing.dart';

/// Compact card used for genus, family, order, and class search results.
///
/// These entries stay text-first so mixed search result lists remain fast to
/// scan even when species cards contain richer media.
class TaxonomySearchResultCard extends StatelessWidget {
  final String primaryName;
  final String scientificName;
  final String? additionalNames;
  final String entityTypeLabel;
  final SearchEntityType entityType;
  final VoidCallback onTap;

  const TaxonomySearchResultCard({
    super.key,
    required this.primaryName,
    required this.scientificName,
    required this.additionalNames,
    required this.entityTypeLabel,
    required this.entityType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = _accentColor(colorScheme, entityType);
    final accentContainer = _accentContainerColor(colorScheme, entityType);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.elementSpacing),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.38),
              ),
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colorScheme.surfaceContainerLow, colorScheme.surface],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s16,
                vertical: AppSpacing.s12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TaxonomyLeadingMarker(
                    accentColor: accent,
                    accentContainerColor: accentContainer,
                    icon: _iconForEntityType(entityType),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entityTypeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.35,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        if (primaryName != scientificName) ...[
                          Text(
                            primaryName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s4),
                        ],
                        Text(
                          scientificName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurface,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Wrap(
                          spacing: AppSpacing.s8,
                          runSpacing: AppSpacing.s8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _SearchEntityTypeBadge(
                              label: entityTypeLabel,
                              icon: _iconForEntityType(entityType),
                              foregroundColor: accent,
                              backgroundColor: accentContainer,
                            ),
                            if (additionalNames != null &&
                                additionalNames!.trim().isNotEmpty)
                              Text(
                                additionalNames!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.25,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.58),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _iconForEntityType(SearchEntityType entityType) {
  switch (entityType) {
    case SearchEntityType.species:
      return Icons.pets;
    case SearchEntityType.genus:
      return Icons.account_tree_outlined;
    case SearchEntityType.family:
      return Icons.category_outlined;
    case SearchEntityType.order:
      return Icons.schema_outlined;
    case SearchEntityType.classType:
      return Icons.layers_outlined;
  }
}

Color _accentColor(ColorScheme colorScheme, SearchEntityType entityType) {
  switch (entityType) {
    case SearchEntityType.species:
      return colorScheme.tertiary;
    case SearchEntityType.genus:
      return colorScheme.primary;
    case SearchEntityType.family:
      return colorScheme.secondary;
    case SearchEntityType.order:
      return colorScheme.onSurfaceVariant;
    case SearchEntityType.classType:
      return colorScheme.onSurface;
  }
}

Color _accentContainerColor(
  ColorScheme colorScheme,
  SearchEntityType entityType,
) {
  switch (entityType) {
    case SearchEntityType.species:
      return colorScheme.tertiaryContainer.withValues(alpha: 0.7);
    case SearchEntityType.genus:
      return colorScheme.primaryContainer.withValues(alpha: 0.7);
    case SearchEntityType.family:
      return colorScheme.secondaryContainer.withValues(alpha: 0.75);
    case SearchEntityType.order:
      return colorScheme.surfaceContainerHighest;
    case SearchEntityType.classType:
      return colorScheme.surfaceContainerHigh;
  }
}

class _SearchEntityTypeBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;

  const _SearchEntityTypeBadge({
    required this.label,
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaxonomyLeadingMarker extends StatelessWidget {
  final Color accentColor;
  final Color accentContainerColor;
  final IconData icon;

  const _TaxonomyLeadingMarker({
    required this.accentColor,
    required this.accentContainerColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accentContainerColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: accentColor, size: 20),
        ),
        const SizedBox(height: AppSpacing.s8),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
        ),
      ],
    );
  }
}
