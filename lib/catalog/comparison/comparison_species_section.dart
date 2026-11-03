import 'package:discere/catalog/common/species_facts/species_fact_view_model.dart';
import 'package:discere/catalog/comparison/comparison_species_view_model.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/species_detail/widgets/species_media_carousel.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// One species of a comparison: its names, which open its detail page, its
/// pictures to swipe through, and a few facts.
class ComparisonSpeciesSection extends StatelessWidget {
  static const _carouselHeight = 220.0;

  final ComparisonSpeciesViewModel species;
  final SpeciesWithLocalImages speciesWithLocalImages;
  final VoidCallback onOpen;

  const ComparisonSpeciesSection({
    required this.species,
    required this.speciesWithLocalImages,
    required this.onOpen,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: AppSpacing.elementSpacing,
      ),
      child: SectionCard(
        child: Padding(
          padding: AppSpacing.cardPaddingAll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      species.primaryName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    AppSpacing.heightS4,
                    Text(
                      species.scientificName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              AppSpacing.heightS12,
              SpeciesMediaCarousel(
                speciesWithLocalImages: speciesWithLocalImages,
                height: _carouselHeight,
                borderRadius: BorderRadius.circular(12),
              ),
              if (species.facts.isNotEmpty) ...[
                AppSpacing.heightS12,
                Wrap(
                  spacing: AppSpacing.s16,
                  runSpacing: AppSpacing.s8,
                  children: [
                    for (final fact in species.facts) _fact(theme, fact),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _fact(ThemeData theme, SpeciesFactViewModel fact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fact.label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          fact.value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
