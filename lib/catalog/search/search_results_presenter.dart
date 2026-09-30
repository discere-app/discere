import 'package:discere/catalog/model/search_result.dart';

/// Where the online search stands for the query currently on screen.
///
/// The two flags behind it — a round is in flight, a round has happened —
/// are both set at once when the search starts, so neither on its own says
/// which of these stages holds.
enum OnlineSearchStage {
  /// The local search has not settled on this query yet, so there is
  /// nothing to widen.
  unavailable,

  /// The local search came up short and the online search has not run.
  offered,

  /// An online round is in flight.
  running,

  /// The online search has run; whatever it found is already merged in.
  finished;

  /// Whether the online-search action belongs on screen at all.
  bool get offersAction =>
      this == OnlineSearchStage.offered || this == OnlineSearchStage.running;

  /// Whether that action has to refuse a second tap while it is on screen.
  bool get isRunning => this == OnlineSearchStage.running;
}

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

  /// Where the online search stands for [normalizedQuery]. Widening the
  /// search is only on the table once the local (reference + runtime)
  /// search has settled on the query the user is actually looking at.
  OnlineSearchStage onlineSearchStage({
    required String normalizedQuery,
    required int minimumQueryLength,
    required String stateQuery,
    required bool isRefining,
    required bool isSearchingOnline,
    required bool hasPerformedOnlineSearch,
  }) {
    final hasLocalSearchSettled =
        normalizedQuery.length >= minimumQueryLength &&
        stateQuery == normalizedQuery &&
        !isRefining;
    if (!hasLocalSearchSettled) return OnlineSearchStage.unavailable;
    if (isSearchingOnline) return OnlineSearchStage.running;
    return hasPerformedOnlineSearch
        ? OnlineSearchStage.finished
        : OnlineSearchStage.offered;
  }
}
