import 'package:flutter/material.dart';

import '../../model/ui/species_native_region_view_data.dart';
import '../../theme/app_spacing.dart';
import 'detail_content_widgets.dart';

class SpeciesNativeRegionsSection extends StatelessWidget {
  final List<SpeciesNativeRegionViewData> nativeRegions;

  const SpeciesNativeRegionsSection({super.key, required this.nativeRegions});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (nativeRegions.isEmpty) {
      return const SizedBox.shrink();
    }

    return DetailSectionCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Native regions',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Selected native records from the reference data.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            ...nativeRegions
                .take(12)
                .map(
                  (region) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                    child: _NativeRegionCard(region: region),
                  ),
                ),
            if (nativeRegions.length > 12)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s4),
                child: Text(
                  '+ ${nativeRegions.length - 12} more native regions',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NativeRegionCard extends StatelessWidget {
  final SpeciesNativeRegionViewData region;

  const _NativeRegionCard({required this.region});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = region.secondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s10,
              vertical: AppSpacing.s4,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              region.isSubregion ? 'Subregion' : 'Country',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s10),
          Text(
            region.label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          if (secondary != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              secondary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
