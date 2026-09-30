import 'dart:async';

import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_empty_state.dart';
import 'package:discere/catalog/search/search_failure_notice.dart';
import 'package:discere/catalog/search/search_online_button.dart';
import 'package:discere/catalog/search/search_online_exhausted_notice.dart';
import 'package:discere/catalog/search/search_results_grouped_list.dart';
import 'package:discere/catalog/search/search_results_presenter.dart';
import 'package:discere/catalog/search/species_search_controller.dart';
import 'package:discere/catalog/service/species_search_service.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_page.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
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
    return _buildSearchScaffold(context);
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

    if (normalizedQuery.length < SpeciesSearchController.minimumQueryLength) {
      // The guard sits here rather than in the two builders above because
      // both of them end up in this method, and nothing below it holds for
      // a query this short: `search` has just reset the controller, so the
      // state carries an empty query, and every loading condition would
      // read that mismatch as "the answer for this query is still out" and
      // show a spinner for work that was never started.
      return SafeArea(
        child: Center(child: Text(context.loc.speciesSearchStartSearch)),
      );
    }

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

          if (!hasVisibleResults) {
            return SearchEmptyState(
              onlineSearch: _controller.onlineSearchStage(normalizedQuery),
              onSearchOnline: () => _controller.searchOnline(normalizedQuery),
              error: state.error,
            );
          }

          _log.debug(
            'Search UI: rendering ${state.results.length} progressive results',
          );

          final onlineSearch = _controller.onlineSearchStage(normalizedQuery);
          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: SearchResultsGroupedList(
                        key: ValueKey('${state.query}:${state.results.length}'),
                        results: state.results,
                        selectedLanguage: _languageService.getLanguage(),
                        resolveThumbnailUrl: _resolveThumbnailUrl,
                        onResultTap: (result) =>
                            _openSearchDetailView(context, result),
                      ),
                    ),
                  ),
                  if (state.error != null)
                    SearchFailureNotice(error: state.error!)
                  else if (onlineSearch == OnlineSearchStage.finished)
                    const SearchOnlineExhaustedNotice(),
                  if (onlineSearch.offersAction)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding,
                        0,
                        AppSpacing.screenPadding,
                        AppSpacing.screenPadding,
                      ),
                      child: SearchOnlineButton(
                        isSearchingOnline: onlineSearch.isRunning,
                        onSearchOnline: () =>
                            _controller.searchOnline(normalizedQuery),
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
}
