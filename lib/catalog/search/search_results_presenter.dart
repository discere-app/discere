import 'package:discere/catalog/model/search_result.dart';

/// Pure result-merging, grouping, and display-decision logic for
/// SearchSpeciesDelegate, kept free of BuildContext/Timer/SearchDelegate
/// state so it can be unit tested directly.
class SearchResultsPresenter {
  const SearchResultsPresenter();

  /// Merges [quickResults] and [fullResults] by [searchResultKey]: quick
  /// results keep their original order and position (using the full-search
  /// row instead if the same key reappears there), followed by any
  /// full-search results not already covered.
  List<SearchResult> mergeResults(
    List<SearchResult> quickResults,
    List<SearchResult> fullResults,
  ) {
    final mergedByKey = <String, SearchResult>{};
    for (final result in quickResults) {
      mergedByKey[searchResultKey(result)] = result;
    }
    for (final result in fullResults) {
      mergedByKey[searchResultKey(result)] = result;
    }

    final mergedResults = <SearchResult>[];
    final seenKeys = <String>{};

    for (final result in quickResults) {
      final key = searchResultKey(result);
      final merged = mergedByKey[key];
      if (merged == null || !seenKeys.add(key)) continue;
      mergedResults.add(merged);
    }

    for (final result in fullResults) {
      final key = searchResultKey(result);
      if (!seenKeys.add(key)) continue;
      mergedResults.add(result);
    }

    return mergedResults;
  }

  String searchResultKey(SearchResult result) {
    return '${result.type.name}:${result.id}:${result.name.toLowerCase()}';
  }

  /// Groups [results] by entity type in a fixed display order (species,
  /// genus, family, order, class), omitting empty groups.
  List<({SearchEntityType type, List<SearchResult> results})> groupByType(
    List<SearchResult> results,
  ) {
    final grouped = <SearchEntityType, List<SearchResult>>{};
    for (final result in results) {
      grouped.putIfAbsent(result.type, () => []).add(result);
    }

    const order = [
      SearchEntityType.species,
      SearchEntityType.genus,
      SearchEntityType.family,
      SearchEntityType.order,
      SearchEntityType.classType,
    ];

    return order
        .where(grouped.containsKey)
        .map((type) => (type: type, results: grouped[type]!))
        .toList();
  }

  /// Whether the "search online" action should be offered: only once the
  /// local (reference + runtime) search has settled for the current query
  /// and hasn't already been supplemented with an online search.
  bool shouldShowOnlineSearchAction({
    required String normalizedQuery,
    required int minimumQueryLength,
    required String stateQuery,
    required bool isRefining,
    required bool isSearchingOnline,
    required bool hasPerformedOnlineSearch,
  }) {
    return normalizedQuery.length >= minimumQueryLength &&
        stateQuery == normalizedQuery &&
        !isRefining &&
        !isSearchingOnline &&
        !hasPerformedOnlineSearch;
  }
}
