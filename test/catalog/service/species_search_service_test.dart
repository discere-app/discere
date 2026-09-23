import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/search_run.dart';
import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/catalog/service/species_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the half of search control that moved out of SearchRepository:
/// which search is still current. The repository only honours the
/// [SearchRun] it is handed, so these are the rules that decide what it
/// sees.

class _RecordingRepository extends Fake implements SearchRepository {
  final List<SearchRun> runs = [];

  @override
  Future<List<SearchResult>> searchQuick(
    String term, {
    required SearchRun run,
  }) async {
    runs.add(run);
    return const [];
  }

  @override
  Future<List<SearchResult>> searchAll(
    String term, {
    required SearchRun run,
  }) async {
    runs.add(run);
    return const [];
  }

  @override
  Future<List<SearchResult>> searchOnline(
    String term, {
    required SearchRun run,
  }) async {
    runs.add(run);
    return const [];
  }
}

void main() {
  late _RecordingRepository repository;
  late SpeciesSearchService service;

  setUp(() {
    repository = _RecordingRepository();
    service = SpeciesSearchService(repository);
  });

  test('a run stays current while it is the newest one', () async {
    await service.searchQuick('octo');

    expect(repository.runs.single.isAbandoned, isFalse);
  });

  test('starting the next search abandons the one before it', () async {
    await service.searchQuick('oct');
    await service.searchQuick('octo');

    expect(repository.runs.first.isAbandoned, isTrue);
    expect(repository.runs.last.isAbandoned, isFalse);
  });

  test('cancelling abandons the run in flight', () async {
    await service.searchAll('octopus');

    service.cancelCurrentSearch();

    expect(repository.runs.single.isAbandoned, isTrue);
  });

  test('escalating from quick to full to online abandons each earlier step', () async {
    await service.searchQuick('octopus');
    await service.searchAll('octopus');
    await service.searchOnline('octopus');

    expect(
      repository.runs.map((run) => run.isAbandoned),
      [true, true, false],
    );
  });

  test('every run carries a newer generation than the one before it', () async {
    await service.searchQuick('a');
    await service.searchQuick('ab');
    await service.searchQuick('abc');

    final generations = repository.runs.map((run) => run.generation).toList();
    expect(generations, orderedEquals([...generations]..sort()));
    expect(generations.toSet(), hasLength(3));
  });

  test('a run with no successor is never abandoned', () {
    expect(SearchRun.single.isAbandoned, isFalse);
  });
}
