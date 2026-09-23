import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/search_run.dart';
import 'package:discere/catalog/repository/search_repository.dart';

/// The catalog's search entry point for everything above it.
///
/// Three lookups of increasing cost, which callers escalate through rather
/// than choosing between: [searchQuick] hits only the species FTS index and
/// is what runs while the user is still typing, [searchAll] adds the
/// taxonomy levels and the common-name indexes, and [searchOnline] leaves
/// the device for iNaturalist once neither found anything.
///
/// Exists so no page has to hold a [SearchRepository]: a widget that depends
/// on this can be given a fake, one that depends on the repository needs a
/// database.
class SpeciesSearchService {
  final SearchRepository _repository;

  /// Counts the searches this service has started. Which one is current is
  /// a question about the user's typing, not about the database, so it is
  /// tracked here and handed down as a [SearchRun] rather than kept in the
  /// repository.
  int _generation = 0;

  SpeciesSearchService(this._repository);

  Future<List<SearchResult>> searchQuick(String term) =>
      _repository.searchQuick(term, run: _beginRun());

  Future<List<SearchResult>> searchAll(String term) =>
      _repository.searchAll(term, run: _beginRun());

  Future<List<SearchResult>> searchOnline(String term) =>
      _repository.searchOnline(term, run: _beginRun());

  /// Abandons whatever local search is in flight. The repository serializes
  /// its queries, so a superseded term would otherwise still occupy the
  /// queue while the user keeps typing.
  void cancelCurrentSearch() => _generation++;

  /// Starts a run that stays current until [cancelCurrentSearch] or the next
  /// search supersedes it.
  SearchRun _beginRun() {
    final mine = ++_generation;
    return SearchRun(
      generation: mine,
      isAbandoned: () => _generation != mine,
    );
  }
}
