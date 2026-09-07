import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_result_thumbnail.dart';
import 'package:discere/catalog/search/taxonomy_search_result_card.dart';
import 'package:discere/catalog/taxonomy_detail/search_taxonomy_style.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The rank one level down — genera under a family, species under a genus.
/// Loads separately from the detail itself, so the rest of the page is
/// readable while a large child list is still arriving.
class TaxonomyChildrenSection extends StatelessWidget {
  final Future<List<SearchResult>> future;
  final SearchEntityType parentType;
  final Color accent;
  final Language language;
  final SpeciesListItemPresenter speciesListItemPresenter;
  final void Function(SearchResult) onNavigate;
  final bool canNavigateToSpecies;

  const TaxonomyChildrenSection({
    required this.future,
    required this.parentType,
    required this.accent,
    required this.language,
    required this.speciesListItemPresenter,
    required this.onNavigate,
    required this.canNavigateToSpecies,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<SearchResult>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.s16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
            child: Text(
              '${context.loc.error}: ${context.loc.describeError(snapshot.error)}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }
        final children = snapshot.data ?? const [];
        if (children.isEmpty) return const SizedBox.shrink();

        final childType = children.first.type;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: Row(
                children: [
                  Icon(
                    SearchTaxonomyStyle.iconFor(childType),
                    color: accent,
                    size: 18,
                  ),
                  AppSpacing.widthS8,
                  Text(
                    _sectionTitle(context, childType, children.length),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ...children.map(
              (child) => Padding(
                padding: const EdgeInsets.only(
                  bottom: AppSpacing.elementSpacing,
                ),
                child: _childCard(context, child),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _childCard(BuildContext context, SearchResult child) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = speciesListItemPresenter.presentSearchResult(child, language);

    if (child.type == SearchEntityType.species) {
      final resolveThumbnailUrl = context
          .read<INaturalistService>()
          .fetchThumbnailUrl;
      return SpeciesListItem(
        item: item,
        onTap: canNavigateToSpecies ? () => onNavigate(child) : null,
        margin: EdgeInsets.zero,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SearchResultThumbnail(
            scientificName: child.name,
            resolveThumbnailUrl: resolveThumbnailUrl,
            size: 64,
            accentColor: colorScheme.tertiary,
            backgroundColor: colorScheme.tertiaryContainer.withValues(
              alpha: 0.65,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        trailing: canNavigateToSpecies
            ? Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              )
            : null,
      );
    }

    return TaxonomySearchResultCard(
      primaryName: item.primaryName,
      scientificName: child.name,
      additionalNames: item.additionalNames,
      entityType: child.type,
      onTap: () => onNavigate(child),
    );
  }

  String _sectionTitle(
    BuildContext context,
    SearchEntityType childType,
    int count,
  ) {
    final loc = context.loc;
    switch (childType) {
      case SearchEntityType.order:
        return '${loc.classificationOrder} ($count)';
      case SearchEntityType.family:
        return '${loc.classificationFamily} ($count)';
      case SearchEntityType.genus:
        return '${loc.classificationGenus} ($count)';
      case SearchEntityType.species:
        return '${loc.classificationSpecies} ($count)';
      case SearchEntityType.classType:
        return '${loc.classificationClass} ($count)';
    }
  }
}
