import 'package:discere/app/diagnostics/diagnostics_page_data.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';
import 'diagnostics_page_data_fixture.dart';

void main() {
  late MockSourceRepository repository;
  late SourceService service;

  setUp(() {
    repository = MockSourceRepository();
    service = SourceService(repository);
  });

  group('loadReferenceDbSources', () {
    test('keeps the reference database sources that name a release, in '
        'their order, and none of the synthetic ones', () async {
      when(repository.findAll()).thenAnswer(
        (_) async => [
          referenceDbSource('fishbase', 'FishBase', version: 'v26.07'),
          referenceDbSource('sealifebase', 'SeaLifeBase', version: 'v26.04'),
          referenceDbSource('worms', 'WoRMS', version: ''),
          referenceDbSource('gbif', 'GBIF'),
        ],
      );

      final sources = await DiagnosticsPageData.loadReferenceDbSources(service);

      expect(sources.map((source) => source.id), ['fishbase', 'sealifebase']);
    });

    test('answers none when the database cannot be read', () async {
      when(repository.findAll()).thenThrow(StateError('no reference db'));

      expect(
        await DiagnosticsPageData.loadReferenceDbSources(service),
        isEmpty,
      );
    });
  });
}
