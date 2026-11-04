import 'package:discere/catalog/common/species_facts/species_fact_view_model.dart';
import 'package:discere/catalog/comparison/comparison_species_view_model.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/species_detail/widgets/species_media_carousel.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// One species of a comparison: its names, which open its detail page, its
/// pictures to swipe through, a few facts, and a button that takes it out of
/// the comparison — a button rather than a swipe, which the pictures already
/// answer to.
class ComparisonSpeciesSection extends StatelessWidget {
  final ComparisonSpeciesViewModel species;
  final SpeciesWithLocalImages speciesWithLocalImages;

  /// See `comparisonImageHeight`.
  final double imageHeight;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  const ComparisonSpeciesSection({
    required this.species,
    required this.speciesWithLocalImages,
    required this.imageHeight,
    required this.onOpen,
    required this.onRemove,
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
              Row(
                children: [
                  Expanded(child: _names(theme)),
                  IconButton(
                    key: const Key('comparison_species_remove'),
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: context.loc.comparisonRemoveSpecies,
                    onPressed: onRemove,
                  ),
                ],
              ),
              AppSpacing.heightS8,
              SpeciesMediaCarousel(
                speciesWithLocalImages: speciesWithLocalImages,
                height: imageHeight,
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

  Widget _names(ThemeData theme) {
    return InkWell(
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
