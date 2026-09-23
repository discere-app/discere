import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/species_search_controller.dart';
import 'package:discere/catalog/service/species_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the escalation the search screen performs — quick search, then the
/// wider full search, then the offer to go online — and which answers still
/// count once the user has typed on.
///
/// Reachable only through a widget test while this lived inside
/// `SearchSpeciesDelegate`; the debounces are injected as zero here so the
/// tests wait on the work itself rather than on a clock.

SearchResult _result(String id, String name) => SearchResult(
  id: id,
  name: name,
  commonNames: const {},
  type: SearchEntityType.species,
);

class _StubSearchService extends Fake implements SpeciesSearchService {
  _StubSearchService({this.quick = const [], this.full = const []});

  List<SearchResult> quick;
  List<SearchResult> full;
  Object? quickError;
  Object? fullError;

  final List<String> quickCalls = [];
  final List<String> fullCalls = [];
  int cancelCalls = 0;

  @override
  Future<List<SearchResult>> searchQuick(String term) async {
    quickCalls.add(term);
    if (quickError != null) throw quickError!;
    return quick;
  }

  @override
  Future<List<SearchResult>> searchAll(String term) async {
    fullCalls.add(term);
    if (fullError != null) throw fullError!;
    return full;
  }

  @override
  void cancelCurrentSearch() => cancelCalls++;
}

SpeciesSearchController _controller(
  _StubSearchService service, {
  Future<List<SearchResult>> Function(String term)? searchOnline,
}) => SpeciesSearchController(
  searchService: service,
  searchOnline: searchOnline ?? (_) async => const [],
  quickSearchDebounce: Duration.zero,
  fullSearchDebounce: Duration.zero,
);

/// Lets the zero-duration debounce timers and their awaits run.
Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a query below the minimum length searches nothing', () async {
    final service = _StubSearchService();
    final controller = _controller(service);

    controller.search('a');
    await _settle();

    expect(service.quickCalls, isEmpty);
    expect(controller.state.query, isEmpty);
  });

  test('a quick result is shown before the full search finishes', () async {
    final service = _StubSearchService(quick: [_result('1', 'Octopus')]);
    final controller = _controller(service);

    controller.search('octo');
    await _settle();

    expect(service.quickCalls, ['octo']);
    expect(controller.state.results, hasLength(1));
  });

  test('the full search escalates on its own and widens the results', () async {
    final service = _StubSearchService(
      quick: [_result('1', 'Octopus')],
      full: [_result('1', 'Octopus'), _result('2', 'Octopus vulgaris')],
    );
    final controller = _controller(service);

    controller.search('octo');
    await _settle();

    expect(service.fullCalls, ['octo']);
    expect(controller.state.results, hasLength(2));
    expect(controller.state.isRefining, isFalse);
  });

  test('repeating the same query does not search again', () async {
    final service = _StubSearchService(quick: [_result('1', 'Octopus')]);
    final controller = _controller(service);

    controller.search('octo');
    await _settle();
    controller.search('octo');
    await _settle();

    expect(service.quickCalls, ['octo']);
  });

  test('typing on abandons the previous query', () async {
    final service = _StubSearchService(quick: [_result('1', 'Octopus')]);
    final controller = _controller(service);

    controller.search('oct');
    controller.search('octo');
    await _settle();

    expect(controller.state.query, 'octo');
    expect(service.cancelCalls, greaterThan(0));
  });

  test('results stay on screen while the next query is still loading', () async {
    final service = _StubSearchService(
      quick: [_result('1', 'Octopus')],
      full: [_result('1', 'Octopus')],
    );
    final controller = _controller(service);

    controller.search('octo');
    await _settle();
    controller.search('octopu');

    expect(controller.state.results, hasLength(1));
    expect(controller.state.isLoadingInitial, isFalse);
  });

  test('a failed quick search surfaces as an error', () async {
    final service = _StubSearchService()..quickError = StateError('no db');
    final controller = _controller(service);

    controller.search('octo');
    await _settle();

    expect(controller.state.error, isA<StateError>());
  });

  test('a failed full search keeps the quick results', () async {
    final service = _StubSearchService(quick: [_result('1', 'Octopus')])
      ..fullError = StateError('no db');
    final controller = _controller(service);

    controller.search('octo');
    await _settle();

    expect(controller.state.results, hasLength(1));
    expect(controller.state.error, isA<StateError>());
  });

  test('the online search merges into what is already there', () async {
    final service = _StubSearchService(
      quick: [_result('1', 'Octopus')],
      full: [_result('1', 'Octopus')],
    );
    final controller = _controller(
      service,
      searchOnline: (_) async => [_result('9', 'Octopus cyanea')],
    );

    controller.search('octo');
    await _settle();
    await controller.searchOnline('octo');

    expect(controller.state.results, hasLength(2));
    expect(controller.state.isSearchingOnline, isFalse);
    expect(controller.state.hasPerformedOnlineSearch, isTrue);
  });

  test('the online search is not offered twice for the same query', () async {
    final service = _StubSearchService(
      quick: [_result('1', 'Octopus')],
      full: [_result('1', 'Octopus')],
    );
    final controller = _controller(service);

    controller.search('octo');
    await _settle();
    expect(controller.shouldOfferOnlineSearch('octo'), isTrue);

    await controller.searchOnline('octo');

    expect(controller.shouldOfferOnlineSearch('octo'), isFalse);
  });

  test('resetting drops the results and cancels pending work', () async {
    final service = _StubSearchService(quick: [_result('1', 'Octopus')]);
    final controller = _controller(service);

    controller.search('octo');
    await _settle();
    controller.reset();

    expect(controller.state.results, isEmpty);
    expect(controller.state.query, isEmpty);
  });

  test('nothing is emitted after disposal', () async {
    final service = _StubSearchService(quick: [_result('1', 'Octopus')]);
    final controller = _controller(service);

    controller.search('octo');
    controller.dispose();
    await _settle();

    expect(controller.state.results, isEmpty);
  });
}
