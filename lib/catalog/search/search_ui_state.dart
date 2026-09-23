import 'package:discere/catalog/model/search_result.dart';

/// What the search screen shows at one moment.
class SearchUiState {
  final String query;
  final List<SearchResult> results;

  /// Nothing to show yet — the first results for this query are still out.
  final bool isLoadingInitial;

  /// Results are on screen, but a wider search is still running behind them.
  final bool isRefining;

  final bool isSearchingOnline;
  final bool hasPerformedOnlineSearch;
  final Object? error;

  const SearchUiState._({
    required this.query,
    required this.results,
    required this.isLoadingInitial,
    required this.isRefining,
    required this.isSearchingOnline,
    required this.hasPerformedOnlineSearch,
    this.error,
  });

  const SearchUiState.idle()
    : this._(
        query: '',
        results: const <SearchResult>[],
        isLoadingInitial: false,
        isRefining: false,
        isSearchingOnline: false,
        hasPerformedOnlineSearch: false,
      );

  SearchUiState.loading(
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

  const SearchUiState.partial({
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

  const SearchUiState.complete({
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

  const SearchUiState.error({required String query, required Object error})
    : this._(
        query: query,
        results: const <SearchResult>[],
        isLoadingInitial: false,
        isRefining: false,
        isSearchingOnline: false,
        hasPerformedOnlineSearch: false,
        error: error,
      );

  SearchUiState copyWith({
    String? query,
    List<SearchResult>? results,
    bool? isLoadingInitial,
    bool? isRefining,
    bool? isSearchingOnline,
    bool? hasPerformedOnlineSearch,
    Object? error = _copyWithNoChange,
  }) {
    return SearchUiState._(
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
