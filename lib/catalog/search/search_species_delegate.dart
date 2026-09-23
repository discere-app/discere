import 'dart:async';

import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_result_section_header.dart';
import 'package:discere/catalog/search/search_result_thumbnail.dart';
import 'package:discere/catalog/search/search_results_presenter.dart';
import 'package:discere/catalog/search/search_ui_state.dart';
import 'package:discere/catalog/search/species_search_controller.dart';
import 'package:discere/catalog/search/taxonomy_search_result_card.dart';
import 'package:discere/catalog/service/species_search_service.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_page.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class SearchSpeciesDelegate extends SearchDelegate<String> {
  static final _log = Logger.forType(SearchSpeciesDelegate);
  final SpeciesSearchService _searchService;
  final LanguageService _languageService;
  final Future<List<SearchResult>> Function(String term) _searchOnline;
  final Future<String?> Function(String scientificName) _resolveThumbnailUrl;
  final Widget Function(String speciesId) _buildSpeciesDetailPage;
  final Future<bool> Function(
    BuildContext context,
    Set<String> speciesIds,
    Set<String> speciesNames,
  )?
  _onAddToDeck;
  final SpeciesListItemPresenter _speciesListItemPresenter =
      const SpeciesListItemPresenter();
  static const SearchResultsPresenter _resultsPresenter =
      SearchResultsPresenter();
  late final SpeciesSearchController _controller = SpeciesSearchController(
    searchService: _searchService,
    searchOnline: _searchOnline,
    resultsPresenter: _resultsPresenter,
  );

  SearchSpeciesDelegate(
    this._searchService,
    this._languageService,
    this._searchOnline,
    this._resolveThumbnailUrl,
    this._buildSpeciesDetailPage, [
    this._onAddToDeck,
  ]);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = ''; // Suchfeld leeren
        },
      ),
    ];
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchScaffold(context);
  }

  @override
  void showResults(BuildContext context) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length >= SpeciesSearchController.minimumQueryLength) {
      _controller.search(normalizedQuery, forceFullSearchNow: true);
    }
    super.showResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return query.isEmpty
        ? Center(child: Text(context.loc.speciesSearchStartSearch))
        : _buildSearchScaffold(context);
  }

  @override
  void close(BuildContext context, String result) {
    _controller.dispose();
    super.close(context, result);
  }

  Widget _buildSearchScaffold(BuildContext context) {
    final normalizedQuery = query.trim();
    _controller.search(normalizedQuery);
    _log.debug('Search UI: buildSearch query="$normalizedQuery"');

    return SafeArea(
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final state = _controller.state;
          final hasVisibleResults = state.results.isNotEmpty;
          if (!hasVisibleResults &&
              (state.isRefining ||
                  state.query != normalizedQuery ||
                  state.isLoadingInitial)) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.error != null && !hasVisibleResults) {
            return Center(
              child: Text(
                '${context.loc.error}: ${context.loc.describeError(state.error)}',
              ),
            );
          }

          if (!hasVisibleResults) {
            return _buildEmptySearchState(context, normalizedQuery, state);
          }

          _log.debug(
            'Search UI: rendering ${state.results.length} progressive results',
          );

          final showOnlineSearchAction = _controller.shouldOfferOnlineSearch(
            normalizedQuery,
          );
          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: _buildGroupedResultsList(
                        context,
                        state.results,
                        key: ValueKey('${state.query}:${state.results.length}'),
                        showThumbnails: true,
                        showSectionHeaders: true,
                      ),
                    ),
                  ),
                  if (showOnlineSearchAction)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding,
                        0,
                        AppSpacing.screenPadding,
                        AppSpacing.screenPadding,
                      ),
                      child: _buildOnlineSearchButton(
                        context,
                        normalizedQuery,
                        state,
                      ),
                    ),
                ],
              ),
              if (state.isRefining || state.isSearchingOnline)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, ''); // Schließt die Suche
      },
    );
  }

  void _openSearchDetailView(BuildContext context, SearchResult selectedItem) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _evaluateDetailView(selectedItem),
      ),
    );
  }

  Widget _evaluateDetailView(SearchResult selectedItem) {
    switch (selectedItem.type) {
      case SearchEntityType.species:
        return _buildSpeciesDetailPage(selectedItem.id);
      default:
        return TaxonomyDetailPage(
          searchResult: selectedItem,
          buildSpeciesDetailPage: _buildSpeciesDetailPage,
          onAddToDeck: _onAddToDeck,
        );
    }
  }

  Widget _buildGroupedResultsList(
    BuildContext context,
    List<SearchResult> results, {
    Key? key,
    required bool showThumbnails,
    required bool showSectionHeaders,
  }) {
    final groupedResults = _resultsPresenter.groupByType(results);
    final selectedLanguage = _languageService.getLanguage();
    final shouldShowHeaders = showSectionHeaders && groupedResults.length > 1;
    final entries = <_SearchListEntry>[];

    for (final group in groupedResults) {
      if (shouldShowHeaders) {
        entries.add(
          _SearchListEntry.header(
            title: _pluralLabelForEntityType(context, group.type),
            count: group.results.length,
          ),
        );
      }

      for (final item in group.results) {
        entries.add(_SearchListEntry.result(item));
      }
    }

    return ListView.builder(
      key: key,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.s4,
        AppSpacing.screenPadding,
        AppSpacing.s24,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry.headerTitle != null) {
          return SearchResultSectionHeader(
            title: entry.headerTitle!,
            count: entry.headerCount!,
          );
        }

        return _buildResultCard(
          context,
          entry.result!,
          selectedLanguage,
          showThumbnails: showThumbnails,
        );
      },
    );
  }

  Widget _buildEmptySearchState(
    BuildContext context,
    String normalizedQuery,
    SearchUiState state,
  ) {
    final showOnlineSearchAction = _controller.shouldOfferOnlineSearch(
      normalizedQuery,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.loc.speciesSearchNoResult),
            if (showOnlineSearchAction) ...[
              const SizedBox(height: AppSpacing.s16),
              _buildOnlineSearchButton(context, normalizedQuery, state),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineSearchButton(
    BuildContext context,
    String normalizedQuery,
    SearchUiState state,
  ) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: state.isSearchingOnline
            ? null
            : () => _controller.searchOnline(normalizedQuery),
        icon: state.isSearchingOnline
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_outlined),
        label: Text(
          state.isSearchingOnline
              ? context.loc.speciesSearchSearchingOnline
              : context.loc.speciesSearchSearchOnline,
        ),
      ),
    );
  }

  Widget _buildResultCard(
    BuildContext context,
    SearchResult result,
    Language selectedLanguage, {
    required bool showThumbnails,
  }) {
    final item = _speciesListItemPresenter.presentSearchResult(
      result,
      selectedLanguage,
    );

    if (result.type == SearchEntityType.species) {
      return SpeciesListItem(
        item: item,
        onTap: () => _openSearchDetailView(context, result),
        margin: const EdgeInsets.only(bottom: AppSpacing.elementSpacing),
        leading: showThumbnails
            ? SearchResultThumbnail(
                scientificName: item.scientificName,
                resolveThumbnailUrl: _resolveThumbnailUrl,
                size: 64,
                accentColor: Theme.of(context).colorScheme.tertiary,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.tertiaryContainer.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
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
      onTap: () => _openSearchDetailView(context, result),
    );
  }

  String _pluralLabelForEntityType(
    BuildContext context,
    SearchEntityType entityType,
  ) {
    switch (entityType) {
      case SearchEntityType.species:
        return context.loc.speciesSearchSpeciesSection;
      case SearchEntityType.genus:
        return context.loc.speciesSearchGeneraSection;
      case SearchEntityType.family:
        return context.loc.speciesSearchFamiliesSection;
      case SearchEntityType.order:
        return context.loc.speciesSearchOrdersSection;
      case SearchEntityType.classType:
        return context.loc.speciesSearchClassesSection;
    }
  }

}

class _SearchListEntry {
  final SearchResult? result;
  final String? headerTitle;
  final int? headerCount;

  const _SearchListEntry._({this.result, this.headerTitle, this.headerCount});

  factory _SearchListEntry.result(SearchResult result) {
    return _SearchListEntry._(result: result);
  }

  factory _SearchListEntry.header({required String title, required int count}) {
    return _SearchListEntry._(headerTitle: title, headerCount: count);
  }
}
