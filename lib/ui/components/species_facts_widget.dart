import 'package:discere/extensions/localization_extension.dart';
import 'package:flutter/material.dart';

import '../../model/ui/species_fact_view_data.dart';
import '../../theme/app_spacing.dart';
import 'detail_content_widgets.dart';

class SpeciesFactsSection extends StatelessWidget {
  final List<SpeciesFactViewData> facts;
  final List<String> habitatTags;

  const SpeciesFactsSection({
    super.key,
    required this.facts,
    required this.habitatTags,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DetailSectionCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.speciesDetailFactsTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (facts.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s12),
              Wrap(
                spacing: AppSpacing.s12,
                runSpacing: AppSpacing.s12,
                children: facts
                    .map(
                      (fact) => _FactCard(
                        label: _label(context, fact.type),
                        value: fact.value,
                        icon: _icon(fact.type),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (habitatTags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s16),
              Text(
                'Habitat',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: habitatTags
                    .map((tag) => _TagPill(label: tag))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _label(BuildContext context, SpeciesFactType type) {
    switch (type) {
      case SpeciesFactType.size:
        return context.loc.speciesSize;
      case SpeciesFactType.depth:
        return context.loc.speciesDepth;
      case SpeciesFactType.habitat:
        return context.loc.speciesDetailHabitat;
      case SpeciesFactType.conservation:
        return context.loc.speciesDetailConservation;
      case SpeciesFactType.bodyForm:
        return 'Body form';
      case SpeciesFactType.humanRisk:
        return 'Human risk';
      case SpeciesFactType.fishingImportance:
        return 'Fishing importance';
      case SpeciesFactType.typicalLifespan:
        return 'Typical lifespan';
      case SpeciesFactType.foodChainLevel:
        return 'Food-chain level';
    }
  }

  IconData _icon(SpeciesFactType type) {
    switch (type) {
      case SpeciesFactType.size:
        return Icons.straighten_rounded;
      case SpeciesFactType.depth:
        return Icons.water_rounded;
      case SpeciesFactType.habitat:
        return Icons.landscape_rounded;
      case SpeciesFactType.conservation:
        return Icons.shield_outlined;
      case SpeciesFactType.bodyForm:
        return Icons.style_outlined;
      case SpeciesFactType.humanRisk:
        return Icons.warning_amber_rounded;
      case SpeciesFactType.fishingImportance:
        return Icons.set_meal_outlined;
      case SpeciesFactType.typicalLifespan:
        return Icons.schedule_outlined;
      case SpeciesFactType.foodChainLevel:
        return Icons.insights_outlined;
    }
  }
}

class _FactCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _FactCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minWidth: 148, maxWidth: 220),
      padding: const EdgeInsets.all(AppSpacing.s16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
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
