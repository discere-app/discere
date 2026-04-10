import 'package:flutter/material.dart';

import '../view_data/species_detail_view_data.dart';
import '../view_data/species_fact_view_data.dart';
import '../../theme/app_spacing.dart';
import 'package:discere/shared/ui/detail_content_widgets.dart';

class SpeciesFactsSection extends StatelessWidget {
  final SpeciesFactsSectionViewData section;

  const SpeciesFactsSection({super.key, required this.section});

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
              section.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (section.facts.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s12),
              Wrap(
                spacing: AppSpacing.s12,
                runSpacing: AppSpacing.s12,
                children: section.facts
                    .map(
                      (fact) => _FactCard(
                        label: fact.label,
                        value: fact.value,
                        icon: _icon(fact.type),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (section.habitatTags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s16),
              Text(
                section.habitatTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: section.habitatTags
                    .map((tag) => _TagPill(label: tag))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
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
