import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_view_model.dart';
import 'package:discere/shared/ui/detail_content_widgets.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Rank-specific key/value facts — what the reference DB knows about this
/// taxon beyond its names and its place in the tree.
class TaxonomyAttributesCard extends StatelessWidget {
  final TaxonomyDetailViewModel viewData;
  final Color accent;

  const TaxonomyAttributesCard({
    required this.viewData,
    required this.accent,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      child: Padding(
        padding: AppSpacing.cardPaddingAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sell_outlined, color: accent, size: 20),
                AppSpacing.widthS8,
                Text(
                  viewData.attributesTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            ...viewData.attributes.map(
              (attribute) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                child: DetailKeyValueRow(
                  label: attribute.label,
                  primary: attribute.value,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
