import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_view_model.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/detail_content_widgets.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The vernacular names for this taxon, expanded by default — for most
/// visitors this is the reason they opened the page.
class TaxonomyCommonNamesCard extends StatelessWidget {
  final TaxonomyDetailViewModel viewData;
  final Color accent;

  const TaxonomyCommonNamesCard({
    required this.viewData,
    required this.accent,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      child: Theme(
        // The tile draws its own separators; the default divider would add a
        // second line right under the header.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            0,
            AppSpacing.s16,
            AppSpacing.s12,
          ),
          leading: Icon(Icons.translate, color: accent, size: 20),
          title: Text(
            context.loc.commonNames,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          children: viewData.commonNames.isEmpty
              ? [
                  Text(
                    viewData.emptyCommonNamesLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ]
              : viewData.commonNames
                    .map((name) => DetailBulletRow(label: name, copyable: true))
                    .toList(),
        ),
      ),
    );
  }
}
