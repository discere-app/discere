import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_result_thumbnail.dart';
import 'package:discere/catalog/search/taxonomy_search_result_card.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// One row of the search result list, and the choice of which row it is.
///
/// A hit above species rank has no photo and no binomial name to show, so
/// the two ranks get different presentations: species rows carry a thumbnail
/// and the species list item's layout, everything else the text-first
/// [TaxonomySearchResultCard]. Both are filled from the same view model, so
/// the choice is the only thing this widget makes.
class SearchResultListItem extends StatelessWidget {
  static const _presenter = SpeciesListItemPresenter();

  final SearchResult result;
  final Language selectedLanguage;
  final Future<String?> Function(String scientificName) resolveThumbnailUrl;
  final VoidCallback onTap;

  const SearchResultListItem({
    super.key,
    required this.result,
    required this.selectedLanguage,
    required this.resolveThumbnailUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final item = _presenter.presentSearchResult(result, selectedLanguage);

    if (result.type == SearchEntityType.species) {
      return SpeciesListItem(
        item: item,
        onTap: onTap,
        margin: const EdgeInsets.only(bottom: AppSpacing.elementSpacing),
        leading: SearchResultThumbnail(
          scientificName: item.scientificName,
          resolveThumbnailUrl: resolveThumbnailUrl,
          size: 64,
          accentColor: Theme.of(context).colorScheme.tertiary,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.tertiaryContainer.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(8),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      );
    }

    return TaxonomySearchResultCard(
      primaryName: item.primaryName,
      scientificName: result.name.trim(),
      additionalNames: item.additionalNames,
      entityType: result.type,
      onTap: onTap,
    );
  }
}
