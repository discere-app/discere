import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_classification_row_view_model.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/detail_content_widgets.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Where this taxon sits in the tree. Each ancestor is tappable when the
/// reference DB knows its id, which is how the user walks upward.
class TaxonomyClassificationSection extends StatelessWidget {
  final List<TaxonomyClassificationRowViewModel> rows;
  final Color accent;
  final String emptyLabel;
  final void Function(SearchResult) onNavigate;

  const TaxonomyClassificationSection({
    required this.rows,
    required this.accent,
    required this.emptyLabel,
    required this.onNavigate,
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
                Icon(Icons.account_tree_outlined, color: accent, size: 20),
                AppSpacing.widthS8,
                Text(
                  context.loc.classification,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            if (rows.isEmpty)
              Text(
                emptyLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...rows.map(
                (row) => _ClassificationRow(
                  row: row,
                  accent: accent,
                  onNavigate: onNavigate,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One ancestor rank. Private: it is the section's row shape, not a widget
/// anything else has a use for.
class _ClassificationRow extends StatelessWidget {
  final TaxonomyClassificationRowViewModel row;
  final Color accent;
  final void Function(SearchResult) onNavigate;

  const _ClassificationRow({
    required this.row,
    required this.accent,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Without an id and a type there is nothing to navigate to, so the row
    // stays plain text — and its names become copyable instead, since a tap
    // would otherwise do nothing.
    final isNavigable = row.id != null && row.entityType != null;

    final content = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: Row(
        children: [
          Expanded(
            child: DetailKeyValueRow(
              label: row.label,
              primary: row.scientificName,
              secondary: row.commonName,
              italicPrimary: true,
              copyablePrimary: !isNavigable,
              copyableSecondary: !isNavigable,
            ),
          ),
          if (isNavigable)
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              size: 20,
            ),
        ],
      ),
    );

    if (!isNavigable) return content;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onNavigate(
        SearchResult(
          id: row.id!,
          name: row.scientificName,
          commonNames: const {},
          type: row.entityType!,
        ),
      ),
      child: content,
    );
  }
}
