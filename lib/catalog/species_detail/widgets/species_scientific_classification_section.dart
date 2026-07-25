import 'package:discere/catalog/common/taxon_classification/classification_row_view_model.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/taxonomy_detail/search_taxonomy_style.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/ui/detail_content_widgets.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class SpeciesScientificClassificationSection extends StatelessWidget {
  final List<ClassificationRowViewModel> rows;
  final void Function(SearchResult)? onNavigate;

  const SpeciesScientificClassificationSection({
    super.key,
    required this.rows,
    this.onNavigate,
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
                Icon(
                  Icons.account_tree_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                AppSpacing.widthS8,
                Text(
                  context.loc.classification,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            AppSpacing.heightS12,
            ...rows
                .where((row) => row.scientificName.isNotEmpty)
                .map(
                  (row) => _ClassificationRow(row: row, onNavigate: onNavigate),
                ),
          ],
        ),
      ),
    );
  }
}

class _ClassificationRow extends StatelessWidget {
  final ClassificationRowViewModel row;
  final void Function(SearchResult)? onNavigate;

  const _ClassificationRow({required this.row, this.onNavigate});

  SearchEntityType? get _entityType {
    switch (row.type) {
      case ClassificationRowType.species:
        // The species row represents the entity already shown on this page —
        // there is nowhere else to navigate to.
        return null;
      case ClassificationRowType.genus:
        return SearchEntityType.genus;
      case ClassificationRowType.family:
        return SearchEntityType.family;
      case ClassificationRowType.order:
        return SearchEntityType.order;
      case ClassificationRowType.classType:
        return SearchEntityType.classType;
      case ClassificationRowType.superClass:
        return null;
    }
  }

  // Same rank icon/color as everywhere else in the app (SearchTaxonomyStyle),
  // except superClass, which has its own dedicated style since it has no
  // SearchEntityType of its own.
  IconData get _icon => row.type == ClassificationRowType.superClass
      ? SearchTaxonomyStyle.superClassIcon
      : SearchTaxonomyStyle.iconFor(_rank);

  Color get _color => row.type == ClassificationRowType.superClass
      ? SearchTaxonomyStyle.superClassColor
      : SearchTaxonomyStyle.colorFor(_rank);

  SearchEntityType get _rank => switch (row.type) {
    ClassificationRowType.species => SearchEntityType.species,
    ClassificationRowType.genus => SearchEntityType.genus,
    ClassificationRowType.family => SearchEntityType.family,
    ClassificationRowType.order => SearchEntityType.order,
    ClassificationRowType.classType => SearchEntityType.classType,
    ClassificationRowType.superClass => SearchEntityType.classType,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entityType = _entityType;
    final id = row.id;
    final canNavigate = onNavigate != null && id != null && entityType != null;

    final content = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_icon, size: 16, color: _color),
          ),
          AppSpacing.widthS8,
          Expanded(
            child: DetailKeyValueRow(
              label: _label(context, row.type),
              primary: row.scientificName,
              secondary: row.commonName,
              italicPrimary: true,
              copyablePrimary: !canNavigate,
              copyableSecondary: !canNavigate,
            ),
          ),
          if (canNavigate)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
            ),
        ],
      ),
    );

    if (!canNavigate) return content;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onNavigate!(
        SearchResult(
          id: id,
          name: row.scientificName,
          commonNames: const {},
          type: entityType,
        ),
      ),
      child: content,
    );
  }

  String _label(BuildContext context, ClassificationRowType type) {
    switch (type) {
      case ClassificationRowType.species:
        return context.loc.classificationSpecies;
      case ClassificationRowType.genus:
        return context.loc.classificationGenus;
      case ClassificationRowType.family:
        return context.loc.classificationFamily;
      case ClassificationRowType.order:
        return context.loc.classificationOrder;
      case ClassificationRowType.classType:
        return context.loc.classificationClass;
      case ClassificationRowType.superClass:
        return context.loc.classificationSuperClass;
    }
  }
}
