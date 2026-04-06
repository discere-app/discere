import 'package:flutter/material.dart';

import '../../external/inaturalist/inaturalist_service.dart';
import '../../theme/app_spacing.dart';
import 'search_result_thumbnail.dart';

/// Rich search card for species results.
///
/// The card keeps text content immediately available and loads a single remote
/// thumbnail asynchronously in the background when [showThumbnail] is enabled.
class SpeciesSearchResultCard extends StatelessWidget {
  final String primaryName;
  final String scientificName;
  final String? additionalNames;
  final String entityTypeLabel;
  final VoidCallback onTap;
  final INaturalistService iNatService;
  final bool showThumbnail;

  const SpeciesSearchResultCard({
    super.key,
    required this.primaryName,
    required this.scientificName,
    required this.additionalNames,
    required this.entityTypeLabel,
    required this.onTap,
    required this.iNatService,
    this.showThumbnail = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = _speciesAccentColor(colorScheme);
    final accentContainer = _speciesAccentContainerColor(colorScheme);

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
                        const SizedBox(height: AppSpacing.s4),
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
                        const SizedBox(height: AppSpacing.s10),
                        Wrap(
                          spacing: AppSpacing.s8,
                          runSpacing: AppSpacing.s8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _SpeciesTypeBadge(
                              label: entityTypeLabel,
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

Color _speciesAccentColor(ColorScheme colorScheme) {
  return colorScheme.tertiary;
}

Color _speciesAccentContainerColor(ColorScheme colorScheme) {
  return colorScheme.tertiaryContainer.withValues(alpha: 0.7);
}

class _SpeciesTypeBadge extends StatelessWidget {
  final String label;
  final Color foregroundColor;
  final Color backgroundColor;

  const _SpeciesTypeBadge({
    required this.label,
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
          Icon(Icons.pets, size: 14, color: foregroundColor),
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

class _SpeciesLeadingMarker extends StatelessWidget {
  final Color accentColor;
  final Color accentContainerColor;

  const _SpeciesLeadingMarker({
    required this.accentColor,
    required this.accentContainerColor,
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
      child: Stack(
        children: [
          Center(child: Icon(Icons.pets, color: accentColor, size: 24)),
          Align(
            alignment: Alignment.topRight,
            child: Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
