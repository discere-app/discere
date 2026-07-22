import 'package:discere/catalog/common/region_abundance_chip.dart';
import 'package:discere/catalog/species_detail/species_native_region_view_model.dart';
import 'package:discere/catalog/species_detail/species_native_regions_section_view_model.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class SpeciesNativeRegionsSection extends StatefulWidget {
  final SpeciesNativeRegionsSectionViewModel section;

  const SpeciesNativeRegionsSection({super.key, required this.section});

  @override
  State<SpeciesNativeRegionsSection> createState() =>
      _SpeciesNativeRegionsSectionState();
}

class _SpeciesNativeRegionsSectionState
    extends State<SpeciesNativeRegionsSection> {
  static const int _collapsedCount = 5;

  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final section = widget.section;

    if (section.nativeRegions.isEmpty && section.habitatTags.isEmpty) {
      return const SizedBox.shrink();
    }

    final isWidespread = section.continents.isNotEmpty;
    final collapsedCount = isWidespread ? 0 : _collapsedCount;
    final visibleRegions =
        _isExpanded || section.nativeRegions.length <= collapsedCount
        ? section.nativeRegions
        : section.nativeRegions.take(collapsedCount).toList(growable: false);
    final hiddenCount = section.nativeRegions.length - visibleRegions.length;
    final hasEndemicRegion = section.nativeRegions.any(
      (region) => region.isEndemic,
    );

    return SectionCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    section.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (section.bestAbundance != null) ...[
                  const SizedBox(width: AppSpacing.s8),
                  RegionAbundanceChip(abundance: section.bestAbundance),
                ],
                if (hasEndemicRegion) ...[
                  const SizedBox(width: AppSpacing.s8),
                  _EndemicBadge(),
                ],
              ],
            ),
            if (section.habitatTags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s12),
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: section.habitatTags
                    .map((tag) => _TagPill(label: tag))
                    .toList(growable: false),
              ),
            ],
            if (isWidespread) ...[
              const SizedBox(height: AppSpacing.s12),
              Text(
                context.loc.speciesDetailWidespreadSummary(
                  section.continents.join(', '),
                  section.nativeRegions.length,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (visibleRegions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s12),
              ...visibleRegions.map(
                (region) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                  child: _NativeRegionBlock(region: region),
                ),
              ),
            ],
            if (hiddenCount > 0)
              TextButton(
                onPressed: () => setState(() => _isExpanded = true),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  context.loc.speciesDetailMoreCountries(hiddenCount),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (_isExpanded && section.nativeRegions.length > collapsedCount)
              TextButton(
                onPressed: () => setState(() => _isExpanded = false),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  context.loc.speciesDetailShowLess,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  final String label;

  const _TagPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _NativeRegionBlock extends StatelessWidget {
  final SpeciesNativeRegionViewModel region;

  const _NativeRegionBlock({required this.region});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          region.label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        if (region.subregions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: region.subregions
                .map(
                  (subregion) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s10,
                      vertical: AppSpacing.s4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      subregion,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}

class _EndemicBadge extends StatelessWidget {
  const _EndemicBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s10,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.loc.speciesDetailEndemicBadge,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onTertiaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
