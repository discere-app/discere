import 'package:discere/catalog/species_detail/species_fact_view_model.dart';
import 'package:discere/catalog/species_detail/species_facts_section_view_model.dart';
import 'package:discere/shared/ui/detail_content_widgets.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class SpeciesFactsSection extends StatelessWidget {
  final SpeciesFactsSectionViewModel section;

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
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = (constraints.maxWidth - AppSpacing.s10) / 2;

                  return Wrap(
                    spacing: AppSpacing.s10,
                    runSpacing: AppSpacing.s10,
                    children: section.facts
                        .map(
                          (fact) => SizedBox(
                            width: cardWidth,
                            child: _FactCard(
                              label: fact.label,
                              value: fact.value,
                              icon: _icon(fact.type),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  );
                },
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
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
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
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
