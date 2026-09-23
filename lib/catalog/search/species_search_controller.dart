import 'dart:async';

import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_results_presenter.dart';
import 'package:discere/catalog/search/search_ui_state.dart';
import 'package:discere/catalog/service/species_search_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';

/// Drives one search session: debouncing, the escalation from quick to full
/// to online, and which of those answers still belongs to what the user last
/// typed.
///
/// Separate from `SearchSpeciesDelegate` because none of it is widget work.
/// A `SearchDelegate` is a builder; this is an async state machine, and as
/// long as it lived inside one, the most interesting question in the search
/// path — when does a quick search escalate — was reachable only through a
/// widget test.
///
/// Three lookups, each shown as soon as it lands rather than waiting for the
/// next: the quick search answers while the user is still typing, the full
/// search widens it, and the online search is offered afterwards when the
/// local ones came up short.
class SpeciesSearchController extends ChangeNotifier {
  static final _log = Logger.forType(SpeciesSearchController);

  /// Below this, a query is too short to be worth a database round trip.
  static const int minimumQueryLength = 2;

  final SpeciesSearchService _searchService;
  final Future<List<SearchResult>> Function(String term) _searchOnline;
  final SearchResultsPresenter _resultsPresenter;
  final Duration _quickSearchDebounce;
  final Duration _fullSearchDebounce;

  Timer? _quickSearchDebounceTimer;
  Timer? _fullSearchDebounceTimer;
  String? _activeSearchQuery;
  int _generation = 0;
  SearchUiState _state = const SearchUiState.idle();
  bool _disposed = false;

  SpeciesSearchController({
    required SpeciesSearchService searchService,
    required Future<List<SearchResult>> Function(String term) searchOnline,
    SearchResultsPresenter resultsPresenter = const SearchResultsPresenter(),
    Duration quickSearchDebounce = const Duration(milliseconds: 180),
    Duration fullSearchDebounce = const Duration(milliseconds: 320),
  }) : _searchService = searchService,
       _searchOnline = searchOnline,
       _resultsPresenter = resultsPresenter,
       _quickSearchDebounce = quickSearchDebounce,
       _fullSearchDebounce = fullSearchDebounce;

  SearchUiState get state => _state;

  /// Whether the online-search action belongs on screen for [normalizedQuery].
  bool shouldOfferOnlineSearch(String normalizedQuery) =>
      _resultsPresenter.shouldShowOnlineSearchAction(
        normalizedQuery: normalizedQuery,
        minimumQueryLength: minimumQueryLength,
        stateQuery: _state.query,
        isRefining: _state.isRefining,
        isSearchingOnline: _state.isSearchingOnline,
        hasPerformedOnlineSearch: _state.hasPerformedOnlineSearch,
      );

  /// Called for whatever the user has typed so far. Repeating the same query
  /// does nothing, so this is safe to call from a build.
  ///
  /// [forceFullSearchNow] skips both debounces — the user pressed enter, so
  /// there is nothing left to wait for.
  void search(String normalizedQuery, {bool forceFullSearchNow = false}) {
    if (normalizedQuery.length < minimumQueryLength) {
      reset();
      return;
    }

    if (_activeSearchQuery == normalizedQuery) {
      if (forceFullSearchNow && _state.isRefining) {
        _runFullSearch(
          normalizedQuery,
          generation: _generation,
          quickResults: _state.results,
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

  /// Leaves the device for iNaturalist, merging whatever it finds into the
  /// results already on screen.
  Future<void> searchOnline(String normalizedQuery) async {
    final generation = _generation;
    if (!_isActiveSearch(normalizedQuery, generation)) return;

    _emit(
      _state.copyWith(
        isSearchingOnline: true,
        hasPerformedOnlineSearch: true,
        error: null,
      ),
    );

    try {
      final stopwatch = Stopwatch()..start();
      _log.debug('Search UI: running online search for "$normalizedQuery"');
      final onlineResults = await _searchOnline(normalizedQuery);
      _log.debug(
        'Search UI: online search finished for "$normalizedQuery" '
        'in ${stopwatch.elapsedMilliseconds}ms '
        '(${onlineResults.length} results)',
      );
      if (!_isActiveSearch(normalizedQuery, generation)) return;

      _emit(
        _state.copyWith(
          results: _resultsPresenter.mergeResults(_state.results, onlineResults),
          isSearchingOnline: false,
          hasPerformedOnlineSearch: true,
        ),
      );
    } catch (error) {
      if (!_isActiveSearch(normalizedQuery, generation)) return;
      _emit(
        _state.copyWith(
          isSearchingOnline: false,
          hasPerformedOnlineSearch: true,
          error: error,
        ),
      );
    }
  }

  /// Back to nothing searched: pending work is dropped and the results go.
  void reset() {
    _cancelPending();
    _activeSearchQuery = null;
    _emit(const SearchUiState.idle());
  }

  void _startProgressiveSearch(
    String normalizedQuery, {
    required bool forceFullSearchNow,
  }) {
    _cancelPending();
    // Keeping the previous results visible is what makes this progressive
    // rather than a flash of empty screen on every keystroke.
    final previousResults = _state.query.isNotEmpty
        ? _state.results
        : const <SearchResult>[];
    _activeSearchQuery = normalizedQuery;
    final generation = ++_generation;
    _emit(
      SearchUiState.loading(normalizedQuery, previousResults: previousResults),
    );

    _quickSearchDebounceTimer = Timer(
      forceFullSearchNow ? Duration.zero : _quickSearchDebounce,
      () async {
        try {
          final stopwatch = Stopwatch()..start();
          _log.debug('Search UI: running quick search for "$normalizedQuery"');
          final quickResults = await _searchService.searchQuick(normalizedQuery);
          _log.debug(
            'Search UI: quick search finished for "$normalizedQuery" '
            'in ${stopwatch.elapsedMilliseconds}ms '
            '(${quickResults.length} results)',
          );
          if (!_isActiveSearch(normalizedQuery, generation)) return;

          _emit(
            SearchUiState.partial(
              query: normalizedQuery,
              results: quickResults,
            ),
          );

          _runFullSearch(
            normalizedQuery,
            generation: generation,
            quickResults: quickResults,
            delay: forceFullSearchNow ? Duration.zero : _fullSearchDebounce,
          );
        } catch (error) {
          if (!_isActiveSearch(normalizedQuery, generation)) return;
          _emit(SearchUiState.error(query: normalizedQuery, error: error));
        }
      },
    );
  }

  void _runFullSearch(
    String normalizedQuery, {
    required int generation,
    required List<SearchResult> quickResults,
    required Duration delay,
  }) {
    _fullSearchDebounceTimer?.cancel();
    _fullSearchDebounceTimer = Timer(delay, () async {
      try {
        final stopwatch = Stopwatch()..start();
        _log.debug('Search UI: running full search for "$normalizedQuery"');
        final fullResults = await _searchService.searchAll(normalizedQuery);
        _log.debug(
          'Search UI: full search finished for "$normalizedQuery" '
          'in ${stopwatch.elapsedMilliseconds}ms '
          '(${fullResults.length} results)',
        );
        if (!_isActiveSearch(normalizedQuery, generation)) return;

        _emit(
          SearchUiState.complete(
            query: normalizedQuery,
            results: _resultsPresenter.mergeResults(quickResults, fullResults),
          ),
        );
      } catch (error) {
        if (!_isActiveSearch(normalizedQuery, generation)) return;
        // The quick results stay: a failed widening is no reason to take
        // away what the user can already see.
        _emit(
          SearchUiState.complete(
            query: normalizedQuery,
            results: _state.results,
            error: error,
          ),
        );
      }
    });
  }

  /// Whether an answer that just arrived still belongs to what is on screen.
  /// Both halves matter: the query catches a different search, the
  /// generation catches the same query searched again.
  bool _isActiveSearch(String normalizedQuery, int generation) =>
      !_disposed &&
      _activeSearchQuery == normalizedQuery &&
      _generation == generation;

  void _cancelPending() {
    _quickSearchDebounceTimer?.cancel();
    _fullSearchDebounceTimer?.cancel();
    _searchService.cancelCurrentSearch();
  }

  void _emit(SearchUiState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelPending();
    super.dispose();
  }
}
