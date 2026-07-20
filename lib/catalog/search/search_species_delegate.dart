import 'dart:async';

import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/catalog/search/search_result_section_header.dart';
import 'package:discere/catalog/search/search_result_thumbnail.dart';
import 'package:discere/catalog/search/search_results_presenter.dart';
import 'package:discere/catalog/search/taxonomy_search_result_card.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_page.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class SearchSpeciesDelegate extends SearchDelegate<String> {
  static final _log = Logger.forType(SearchSpeciesDelegate);
  static const Duration _quickSearchDebounce = Duration(milliseconds: 180);
  static const Duration _fullSearchDebounce = Duration(milliseconds: 320);
  static const int _minimumQueryLength = 2;
  static const bool _enableSearchDebugLogging = true;

  final SearchRepository _searchRepository;
  final LanguageService _languageService;
  final Future<List<SearchResult>> Function(String term) _searchOnline;
  final Future<String?> Function(String scientificName) _resolveThumbnailUrl;
  final Widget Function(String speciesId) _buildSpeciesDetailPage;
  final Future<void> Function(
    BuildContext context,
    Set<String> speciesIds,
    Set<String> speciesNames,
  )?
  _onAddToDeck;
  final SpeciesListItemPresenter _speciesListItemPresenter =
      const SpeciesListItemPresenter();
  static const SearchResultsPresenter _resultsPresenter =
      SearchResultsPresenter();
  Timer? _quickSearchDebounceTimer;
  Timer? _searchDebounceTimer;
  String? _activeSearchQuery;
  int _searchGeneration = 0;
  final ValueNotifier<_SearchUiState> _searchState = ValueNotifier(
    const _SearchUiState.idle(),
  );

  SearchSpeciesDelegate(
    this._searchRepository,
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
    if (normalizedQuery.length >= _minimumQueryLength) {
      _ensureProgressiveSearch(normalizedQuery, forceFullSearchNow: true);
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
    _resetSearchState();
    _searchState.dispose();
    super.close(context, result);
  }

  Widget _buildSearchScaffold(BuildContext context) {
    final normalizedQuery = query.trim();
    _ensureProgressiveSearch(normalizedQuery);
    _logDebug('Search UI: buildSearch query="$normalizedQuery"');

    return SafeArea(
      child: ValueListenableBuilder<_SearchUiState>(
        valueListenable: _searchState,
        builder: (context, state, _) {
        final hasVisibleResults = state.results.isNotEmpty;
        if (!hasVisibleResults &&
            (state.isRefining ||
                state.query != normalizedQuery ||
                state.isLoadingInitial)) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.error != null && !hasVisibleResults) {
          return Center(child: Text('${context.loc.error}: ${state.error}'));
        }

        if (!hasVisibleResults) {
          return _buildEmptySearchState(context, normalizedQuery, state);
        }

        _logDebug(
          'Search UI: rendering ${state.results.length} progressive results',
        );

        final showOnlineSearchAction = _shouldShowOnlineSearchAction(
          state,
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

  void _ensureProgressiveSearch(
    String normalizedQuery, {
    bool forceFullSearchNow = false,
  }) {
    if (normalizedQuery.length < _minimumQueryLength) {
      _resetSearchState();
      return;
    }

    if (_activeSearchQuery == normalizedQuery) {
      if (forceFullSearchNow && _searchState.value.isRefining) {
        _runFullSearch(
          normalizedQuery,
          generation: _searchGeneration,
          quickResults: _searchState.value.results,
          delay: Duration.zero,
        );
      }
      return;
    }

    _startProgressiveSearch(
      normalizedQuery,
      forceFullSearchNow: forceFullSearchNow,
    );
  }

  void _startProgressiveSearch(
    String normalizedQuery, {
    bool forceFullSearchNow = false,
  }) {
    _cancelPendingSearch();
    final previousResults = _searchState.value.query.isNotEmpty
        ? _searchState.value.results
        : const <SearchResult>[];
    _activeSearchQuery = normalizedQuery;
    final generation = ++_searchGeneration;
    _searchState.value = _SearchUiState.loading(
      normalizedQuery,
      previousResults: previousResults,
    );

    () async {
      _quickSearchDebounceTimer = Timer(
        forceFullSearchNow ? Duration.zero : _quickSearchDebounce,
        () async {
          try {
            final quickSearchStopwatch = Stopwatch()..start();
            _logDebug('Search UI: running quick search for "$normalizedQuery"');
            final quickResults = await _searchRepository.searchQuick(
              normalizedQuery,
            );
            _logDebug(
              'Search UI: quick search finished for "$normalizedQuery" '
              'in ${quickSearchStopwatch.elapsedMilliseconds}ms '
              '(${quickResults.length} results)',
            );
            if (!_isActiveSearch(normalizedQuery, generation)) return;

            _searchState.value = _SearchUiState.partial(
              query: normalizedQuery,
              results: quickResults,
            );

            _runFullSearch(
              normalizedQuery,
              generation: generation,
              quickResults: quickResults,
              delay: forceFullSearchNow ? Duration.zero : _fullSearchDebounce,
            );
          } catch (error) {
            if (!_isActiveSearch(normalizedQuery, generation)) return;
            _searchState.value = _SearchUiState.error(
              query: normalizedQuery,
              error: error,
            );
          }
        },
      );
    }();
  }

  void _runFullSearch(
    String normalizedQuery, {
    required int generation,
    required List<SearchResult> quickResults,
    required Duration delay,
  }) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(delay, () async {
      try {
        final fullSearchStopwatch = Stopwatch()..start();
        _logDebug('Search UI: running full search for "$normalizedQuery"');
        final fullResults = await _searchRepository.searchAll(normalizedQuery);
        _logDebug(
          'Search UI: full search finished for "$normalizedQuery" '
          'in ${fullSearchStopwatch.elapsedMilliseconds}ms '
          '(${fullResults.length} results)',
        );
        if (!_isActiveSearch(normalizedQuery, generation)) return;

        final mergedResults = _resultsPresenter.mergeResults(
          quickResults,
          fullResults,
        );
        _searchState.value = _SearchUiState.complete(
          query: normalizedQuery,
          results: mergedResults,
        );
      } catch (error) {
        if (!_isActiveSearch(normalizedQuery, generation)) return;
        _searchState.value = _SearchUiState.complete(
          query: normalizedQuery,
          results: _searchState.value.results,
          error: error,
        );
      }
    });
  }

  Future<void> _runOnlineSearch(
    String normalizedQuery, {
    required int generation,
  }) async {
    if (!_isActiveSearch(normalizedQuery, generation)) return;

    _searchState.value = _searchState.value.copyWith(
      isSearchingOnline: true,
      hasPerformedOnlineSearch: true,
      error: null,
    );

    try {
      final onlineSearchStopwatch = Stopwatch()..start();
      _logDebug('Search UI: running online search for "$normalizedQuery"');
      final onlineResults = await _searchOnline(normalizedQuery);
      _logDebug(
        'Search UI: online search finished for "$normalizedQuery" '
        'in ${onlineSearchStopwatch.elapsedMilliseconds}ms '
        '(${onlineResults.length} results)',
      );
      if (!_isActiveSearch(normalizedQuery, generation)) return;

      final mergedResults = _resultsPresenter.mergeResults(
        _searchState.value.results,
        onlineResults,
      );
      _searchState.value = _searchState.value.copyWith(
        results: mergedResults,
        isSearchingOnline: false,
        hasPerformedOnlineSearch: true,
      );
    } catch (error) {
      if (!_isActiveSearch(normalizedQuery, generation)) return;
      _searchState.value = _searchState.value.copyWith(
        isSearchingOnline: false,
        hasPerformedOnlineSearch: true,
        error: error,
      );
    }
  }

  bool _isActiveSearch(String normalizedQuery, int generation) {
    return _activeSearchQuery == normalizedQuery &&
        _searchGeneration == generation;
  }

  void _resetSearchState() {
    _cancelPendingSearch();
    _activeSearchQuery = null;
    _searchState.value = const _SearchUiState.idle();
  }

  void _cancelPendingSearch() {
    _quickSearchDebounceTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _searchRepository.cancelCurrentSearch();
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
    _SearchUiState state,
  ) {
    final showOnlineSearchAction = _shouldShowOnlineSearchAction(
      state,
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

  bool _shouldShowOnlineSearchAction(
    _SearchUiState state,
    String normalizedQuery,
  ) {
    return _resultsPresenter.shouldShowOnlineSearchAction(
      normalizedQuery: normalizedQuery,
      minimumQueryLength: _minimumQueryLength,
      stateQuery: state.query,
      isRefining: state.isRefining,
      isSearchingOnline: state.isSearchingOnline,
      hasPerformedOnlineSearch: state.hasPerformedOnlineSearch,
    );
  }

  Widget _buildOnlineSearchButton(
    BuildContext context,
    String normalizedQuery,
    _SearchUiState state,
  ) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: state.isSearchingOnline
            ? null
            : () => _runOnlineSearch(
                normalizedQuery,
                generation: _searchGeneration,
              ),
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

  void _logDebug(String message) {
    if (_enableSearchDebugLogging) {
      _log.debug(message);
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

class _SearchUiState {
  final String query;
  final List<SearchResult> results;
  final bool isLoadingInitial;
  final bool isRefining;
  final bool isSearchingOnline;
  final bool hasPerformedOnlineSearch;
  final Object? error;

  const _SearchUiState._({
    required this.query,
    required this.results,
    required this.isLoadingInitial,
    required this.isRefining,
    required this.isSearchingOnline,
    required this.hasPerformedOnlineSearch,
    this.error,
  });

  const _SearchUiState.idle()
    : this._(
        query: '',
        results: const <SearchResult>[],
        isLoadingInitial: false,
        isRefining: false,
        isSearchingOnline: false,
        hasPerformedOnlineSearch: false,
      );

  _SearchUiState.loading(
    String query, {
    List<SearchResult> previousResults = const <SearchResult>[],
  }) : this._(
         query: query,
         results: previousResults,
         isLoadingInitial: previousResults.isEmpty,
         isRefining: true,
         isSearchingOnline: false,
         hasPerformedOnlineSearch: false,
       );

  const _SearchUiState.partial({
    required String query,
    required List<SearchResult> results,
  }) : this._(
         query: query,
         results: results,
         isLoadingInitial: false,
         isRefining: true,
         isSearchingOnline: false,
         hasPerformedOnlineSearch: false,
       );

  const _SearchUiState.complete({
    required String query,
    required List<SearchResult> results,
    bool isSearchingOnline = false,
    bool hasPerformedOnlineSearch = false,
    Object? error,
  }) : this._(
         query: query,
         results: results,
         isLoadingInitial: false,
         isRefining: false,
         isSearchingOnline: isSearchingOnline,
         hasPerformedOnlineSearch: hasPerformedOnlineSearch,
         error: error,
       );

  const _SearchUiState.error({required String query, required Object error})
    : this._(
        query: query,
        results: const <SearchResult>[],
        isLoadingInitial: false,
        isRefining: false,
        isSearchingOnline: false,
        hasPerformedOnlineSearch: false,
        error: error,
      );

  _SearchUiState copyWith({
    String? query,
    List<SearchResult>? results,
    bool? isLoadingInitial,
    bool? isRefining,
    bool? isSearchingOnline,
    bool? hasPerformedOnlineSearch,
    Object? error = _copyWithNoChange,
  }) {
    return _SearchUiState._(
      query: query ?? this.query,
      results: results ?? this.results,
      isLoadingInitial: isLoadingInitial ?? this.isLoadingInitial,
      isRefining: isRefining ?? this.isRefining,
      isSearchingOnline: isSearchingOnline ?? this.isSearchingOnline,
      hasPerformedOnlineSearch:
          hasPerformedOnlineSearch ?? this.hasPerformedOnlineSearch,
      error: identical(error, _copyWithNoChange) ? this.error : error,
    );
  }

  static const Object _copyWithNoChange = Object();
}
