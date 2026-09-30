import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_results_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

SearchResult _result(
  String id, {
  String name = 'Name',
  SearchEntityType type = SearchEntityType.species,
}) {
  return SearchResult(id: id, name: name, commonNames: const {}, type: type);
}

void main() {
  const presenter = SearchResultsPresenter();

  group('SearchResultsPresenter.mergeResults', () {
    test('quick results keep their order, followed by new full results', () {
      final quick = [_result('sp1'), _result('sp2')];
      final full = [_result('sp2'), _result('sp3')];

      final merged = presenter.mergeResults(quick, full);

      expect(merged.map((r) => r.id).toList(), ['sp1', 'sp2', 'sp3']);
    });

    test('a result with the same key (id + type + name) in both lists uses '
        'the full-search object at the quick-result position', () {
      final quickRow = _result('sp1', name: 'Name');
      final fullRow = _result('sp1', name: 'Name');

      final merged = presenter.mergeResults([quickRow], [fullRow]);

      expect(merged, hasLength(1));
      expect(identical(merged.single, fullRow), isTrue);
    });

    test('the merge key includes the display name, so the same id with a '
        'different name across quick/full search is NOT deduplicated', () {
      final quickRow = _result('sp1', name: 'Quick Name');
      final fullRow = _result('sp1', name: 'Full Name');

      final merged = presenter.mergeResults([quickRow], [fullRow]);

      expect(merged, hasLength(2));
    });

    test('deduplicates repeated keys within the same list', () {
      final quick = [_result('sp1'), _result('sp1')];

      final merged = presenter.mergeResults(quick, const []);

      expect(merged, hasLength(1));
    });

    test('empty quick results still returns all full results', () {
      final full = [_result('sp1'), _result('sp2')];

      final merged = presenter.mergeResults(const [], full);

      expect(merged.map((r) => r.id).toList(), ['sp1', 'sp2']);
    });

    test('distinguishes results with the same id but different type', () {
      final quick = [_result('shared-id', type: SearchEntityType.species)];
      final full = [_result('shared-id', type: SearchEntityType.genus)];

      final merged = presenter.mergeResults(quick, full);

      expect(merged, hasLength(2));
    });
  });

  group('SearchResultsPresenter.groupByType', () {
    test('groups and orders species, genus, family, order, class', () {
      final results = [
        _result('o1', type: SearchEntityType.order),
        _result('sp1', type: SearchEntityType.species),
        _result('f1', type: SearchEntityType.family),
        _result('sp2', type: SearchEntityType.species),
        _result('g1', type: SearchEntityType.genus),
        _result('c1', type: SearchEntityType.classType),
      ];

      final grouped = presenter.groupByType(results);

      expect(grouped.map((g) => g.type).toList(), [
        SearchEntityType.species,
        SearchEntityType.genus,
        SearchEntityType.family,
        SearchEntityType.order,
        SearchEntityType.classType,
      ]);
      expect(
        grouped
            .firstWhere((g) => g.type == SearchEntityType.species)
            .results
            .map((r) => r.id),
        ['sp1', 'sp2'],
      );
    });

    test('omits entity types with no results', () {
      final results = [_result('sp1', type: SearchEntityType.species)];

      final grouped = presenter.groupByType(results);

      expect(grouped, hasLength(1));
      expect(grouped.single.type, SearchEntityType.species);
    });

    test('returns an empty list for no results', () {
      expect(presenter.groupByType(const []), isEmpty);
    });
  });

  group('SearchResultsPresenter.onlineSearchStage', () {
    OnlineSearchStage call({
      String normalizedQuery = 'shark',
      int minimumQueryLength = 2,
      String stateQuery = 'shark',
      bool isRefining = false,
      bool isSearchingOnline = false,
      bool hasPerformedOnlineSearch = false,
    }) {
      return presenter.onlineSearchStage(
        normalizedQuery: normalizedQuery,
        minimumQueryLength: minimumQueryLength,
        stateQuery: stateQuery,
        isRefining: isRefining,
        isSearchingOnline: isSearchingOnline,
        hasPerformedOnlineSearch: hasPerformedOnlineSearch,
      );
    }

    test('offered once local search has settled for the current query', () {
      expect(call(), OnlineSearchStage.offered);
    });

    test('unavailable while the query is below the minimum length', () {
      expect(
        call(normalizedQuery: 's', stateQuery: 's'),
        OnlineSearchStage.unavailable,
      );
    });

    test('unavailable while local search state is for a stale query', () {
      expect(call(stateQuery: 'whale'), OnlineSearchStage.unavailable);
    });

    test('unavailable while still refining (quick/full search in flight)', () {
      expect(call(isRefining: true), OnlineSearchStage.unavailable);
    });

    test('running while the online round is in flight, even though the '
        'controller flags it as performed at the same time', () {
      expect(
        call(isSearchingOnline: true, hasPerformedOnlineSearch: true),
        OnlineSearchStage.running,
      );
    });

    test('finished once the online round is over', () {
      expect(call(hasPerformedOnlineSearch: true), OnlineSearchStage.finished);
    });

    test('a stale query outranks a running online round, so a stage is '
        'never reported for results the user is no longer looking at', () {
      expect(
        call(stateQuery: 'whale', isSearchingOnline: true),
        OnlineSearchStage.unavailable,
      );
    });
  });

  group('OnlineSearchStage', () {
    test('the action is on screen while offered and while running', () {
      expect(OnlineSearchStage.offered.offersAction, isTrue);
      expect(OnlineSearchStage.running.offersAction, isTrue);
      expect(OnlineSearchStage.finished.offersAction, isFalse);
      expect(OnlineSearchStage.unavailable.offersAction, isFalse);
    });

    test('only the running stage has to refuse a second tap', () {
      expect(OnlineSearchStage.running.isRunning, isTrue);
      expect(OnlineSearchStage.offered.isRunning, isFalse);
      expect(OnlineSearchStage.finished.isRunning, isFalse);
      expect(OnlineSearchStage.unavailable.isRunning, isFalse);
    });
  });
}
