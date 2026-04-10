import 'package:flutter/material.dart';

import 'package:discere/catalog/model/search_result.dart';
import '../../theme/app_spacing.dart';
import '../../theme/search_taxonomy_style.dart';

/// Compact card used for genus, family, order, and class search results.
///
/// These entries stay text-first so mixed search result lists remain fast to
/// scan even when species cards contain richer media.
class TaxonomySearchResultCard extends StatelessWidget {
  final String primaryName;
  final String scientificName;
  final String? additionalNames;
  final SearchEntityType entityType;
  final VoidCallback onTap;

  const TaxonomySearchResultCard({
    super.key,
    required this.primaryName,
    required this.scientificName,
    required this.additionalNames,
    required this.entityType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = SearchTaxonomyStyle.colorFor(entityType);
    final accentContainer = colorScheme.surfaceContainerHighest;

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
                  Container(
                    width: 4,
                    height: 70,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  _TaxonomyLeadingMarker(
                    accentColor: accent,
                    accentContainerColor: accentContainer,
                    icon: SearchTaxonomyStyle.iconFor(entityType),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: accentContainerColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: accentColor, size: 20),
    );
  }
}
