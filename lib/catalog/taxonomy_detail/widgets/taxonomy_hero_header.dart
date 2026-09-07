import 'package:discere/catalog/common/taxon_identity/common_name_hint.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_result_card.dart';
import 'package:discere/catalog/taxonomy_detail/search_taxonomy_style.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_view_model.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_metric_chip.dart';
import 'package:discere/shared/ui/copyable_text.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Identity block at the top of the page: rank badge, common and scientific
/// name, and the counts underneath, on a gradient tinted by the rank's
/// accent colour.
class TaxonomyHeroHeader extends StatelessWidget {
  final TaxonomyDetailViewModel viewData;
  final SearchEntityType type;
  final Color accent;

  const TaxonomyHeroHeader({
    required this.viewData,
    required this.type,
    required this.accent,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.16),
            theme.colorScheme.surfaceContainerLow,
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchEntityTypeBadge(
            label: viewData.entityLabel,
            icon: SearchTaxonomyStyle.iconFor(type),
            foregroundColor: accent,
            backgroundColor: accent.withValues(alpha: 0.12),
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: CopyableText(
                  text: viewData.primaryTitle,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  copiedStyle: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              if (viewData.isEnglishFallback)
                const CommonNameHintIcon(isEnglishFallback: true),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          CopyableText(
            text: viewData.scientificName,
            style: theme.textTheme.titleMedium?.copyWith(
              color: accent,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
            ),
            copiedStyle: theme.textTheme.titleMedium?.copyWith(
              color: accent,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (viewData.metrics.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s16),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: viewData.metrics
                  .map(
                    (metric) => TaxonomyMetricChip(
                      label: metric.label,
                      count: metric.count,
                      accent: accent,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
