import 'package:flutter/material.dart';

import '../../external/inaturalist/inaturalist_service.dart';
import '../../model/search/search_result.dart';
import '../../theme/app_spacing.dart';
import '../../theme/search_taxonomy_style.dart';
import 'search_result_thumbnail.dart';

/// Rich search card for species results.
///
/// The card keeps text content immediately available and loads a single remote
/// thumbnail asynchronously in the background when [showThumbnail] is enabled.
class SpeciesSearchResultCard extends StatelessWidget {
  final String primaryName;
  final String scientificName;
  final String? additionalNames;
  final VoidCallback onTap;
  final INaturalistService iNatService;
  final bool showThumbnail;

  const SpeciesSearchResultCard({
    super.key,
    required this.primaryName,
    required this.scientificName,
    required this.additionalNames,
    required this.onTap,
    required this.iNatService,
    this.showThumbnail = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = SearchTaxonomyStyle.colorFor(SearchEntityType.species);
    final accentContainer = colorScheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.elementSpacing),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.34),
              ),
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colorScheme.surfaceContainerLow, colorScheme.surface],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 92,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  if (showThumbnail)
                    SearchResultThumbnail(
                      scientificName: scientificName,
                      iNatService: iNatService,
                      size: 80,
                      accentColor: accent,
                      backgroundColor: accentContainer.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(18),
                    )
                  else
                    _SpeciesLeadingMarker(
                      accentColor: accent,
                      accentContainerColor: accentContainer,
                      icon: SearchTaxonomyStyle.iconFor(
                        SearchEntityType.species,
                      ),
                    ),
                  const SizedBox(width: AppSpacing.s16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          primaryName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.12,
                            letterSpacing: -0.2,
                          ),
                        ),
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
                        const SizedBox(height: AppSpacing.s10),
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
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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

class _SpeciesLeadingMarker extends StatelessWidget {
  final Color accentColor;
  final Color accentContainerColor;
  final IconData icon;

  const _SpeciesLeadingMarker({
    required this.accentColor,
    required this.accentContainerColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: accentContainerColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: accentColor, size: 24),
    );
  }
}
