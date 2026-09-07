import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/taxonomy_detail/search_taxonomy_style.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_view_model.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_attributes_card.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_children_section.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_classification_section.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_common_names_card.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_hero_header.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/ui/section_card.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The loaded page body. Every section is optional except the header, the
/// names and the children, so the order here is the page's structure: who
/// this taxon is, what it is called, where it sits, what is known about it,
/// and what is below it.
class TaxonomyDetailContent extends StatelessWidget {
  final TaxonomyDetailViewModel viewData;
  final SearchEntityType type;
  final Future<List<SearchResult>> childrenFuture;
  final Language language;
  final SpeciesListItemPresenter speciesListItemPresenter;
  final void Function(SearchResult) onNavigate;
  final bool canNavigateToSpecies;

  const TaxonomyDetailContent({
    required this.viewData,
    required this.type,
    required this.childrenFuture,
    required this.language,
    required this.speciesListItemPresenter,
    required this.onNavigate,
    required this.canNavigateToSpecies,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = SearchTaxonomyStyle.colorFor(type);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s20,
        AppSpacing.s16,
        AppSpacing.s24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TaxonomyHeroHeader(viewData: viewData, type: type, accent: accent),
          const SizedBox(height: AppSpacing.s16),
          TaxonomyCommonNamesCard(viewData: viewData, accent: accent),
          if (viewData.classificationRows.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s12),
            TaxonomyClassificationSection(
              rows: viewData.classificationRows,
              accent: accent,
              emptyLabel: viewData.emptyClassificationLabel,
              onNavigate: onNavigate,
            ),
          ],
          if (viewData.attributes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s12),
            TaxonomyAttributesCard(viewData: viewData, accent: accent),
          ],
          // Shown only for a taxon the reference DB does not back, to
          // explain why the page is thinner than usual.
          if (!viewData.isReferenceBacked) ...[
            const SizedBox(height: AppSpacing.s12),
            SectionCard(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Text(
                  viewData.referenceHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          TaxonomyChildrenSection(
            future: childrenFuture,
            parentType: type,
            accent: accent,
            language: language,
            speciesListItemPresenter: speciesListItemPresenter,
            onNavigate: onNavigate,
            canNavigateToSpecies: canNavigateToSpecies,
          ),
        ],
      ),
    );
  }
}
