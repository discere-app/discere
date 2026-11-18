import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/taxonomy_detail/search_taxonomy_style.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:material_ui/material_ui.dart';

class SearchResultCard extends StatelessWidget {
  /// Shown left of the names, centred on them.
  final Widget leading;
  final String primaryName;

  /// Left out when empty, as for a rank placeholder, which has none.
  final String scientificName;
  final String? additionalNames;
  final String entityTypeLabel;
  final SearchEntityType entityType;
  final VoidCallback onTap;

  const SearchResultCard({
    super.key,
    required this.leading,
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
    final accent = SearchTaxonomyStyle.accentFor(colorScheme, entityType);
    final accentContainer = SearchTaxonomyStyle.accentContainerFor(
      colorScheme,
      entityType,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.elementSpacing),
      child: TappableSectionCard(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    if (scientificName.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        scientificName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.s8),
                    Wrap(
                      spacing: AppSpacing.s8,
                      runSpacing: AppSpacing.s8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SearchEntityTypeBadge(
                          label: entityTypeLabel,
                          icon: SearchTaxonomyStyle.iconFor(entityType),
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
            ],
          ),
        ),
      ),
    );
  }
}

class SearchEntityTypeBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;

  const SearchEntityTypeBadge({
    super.key,
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
          // Flexible so a label wider than the room the badge is given is
          // cut off with an ellipsis rather than overflowing the pill.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
