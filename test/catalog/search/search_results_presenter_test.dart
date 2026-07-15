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

    test(
      'a result with the same key (id + type + name) in both lists uses '
      'the full-search object at the quick-result position',
      () {
        final quickRow = _result('sp1', name: 'Name');
        final fullRow = _result('sp1', name: 'Name');

        final merged = presenter.mergeResults([quickRow], [fullRow]);

        expect(merged, hasLength(1));
        expect(identical(merged.single, fullRow), isTrue);
      },
    );

    test(
      'the merge key includes the display name, so the same id with a '
      'different name across quick/full search is NOT deduplicated',
      () {
        final quickRow = _result('sp1', name: 'Quick Name');
        final fullRow = _result('sp1', name: 'Full Name');

        final merged = presenter.mergeResults([quickRow], [fullRow]);

        expect(merged, hasLength(2));
      },
    );

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
      final quick = [
        _result('shared-id', type: SearchEntityType.species),
      ];
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

  group('SearchResultsPresenter.shouldShowOnlineSearchAction', () {
    bool call({
      String normalizedQuery = 'shark',
      int minimumQueryLength = 2,
      String stateQuery = 'shark',
      bool isRefining = false,
      bool isSearchingOnline = false,
      bool hasPerformedOnlineSearch = false,
    }) {
      return presenter.shouldShowOnlineSearchAction(
        normalizedQuery: normalizedQuery,
        minimumQueryLength: minimumQueryLength,
        stateQuery: stateQuery,
        isRefining: isRefining,
        isSearchingOnline: isSearchingOnline,
        hasPerformedOnlineSearch: hasPerformedOnlineSearch,
      );
    }

    test('true once local search has settled for the current query', () {
      expect(call(), isTrue);
    });

    test('false while the query is below the minimum length', () {
      expect(call(normalizedQuery: 's', stateQuery: 's'), isFalse);
    });

    test('false while local search state is for a stale query', () {
      expect(call(stateQuery: 'whale'), isFalse);
    });

    test('false while still refining (quick/full search in flight)', () {
      expect(call(isRefining: true), isFalse);
    });

    test('false while an online search is already in flight', () {
      expect(call(isSearchingOnline: true), isFalse);
    });

    test('false once an online search has already been performed', () {
      expect(call(hasPerformedOnlineSearch: true), isFalse);
    });
  });
}
