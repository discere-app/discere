import 'package:discere/catalog/model/source.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

void main() {
  late MockSourceRepository sourceRepository;
  late SourceService service;

  setUp(() {
    sourceRepository = MockSourceRepository();
    service = SourceService(sourceRepository);
  });

  group('SourceService.getAllSources', () {
    test(
      'appends the synthetic Wikipedia source after the curated ones',
      () async {
        final curated = [
          const Source(
            id: 'fishbase',
            name: 'FishBase',
            category: 'Taxonomy',
            citation: 'FishBase citation',
            url: 'https://www.fishbase.org',
            licenseKey: 'CC BY-NC',
            displayOrder: 10,
          ),
        ];
        when(sourceRepository.findAll()).thenAnswer((_) async => curated);

        final sources = await service.getAllSources();

        final wikipedia = sources.firstWhere((s) => s.id == 'wikipedia');
        expect(wikipedia.name, 'Wikipedia');
        expect(wikipedia.licenseKey, 'CC BY-SA 4.0');
        expect(sources, contains(curated.first));
      },
    );
  });

  group('SourceService.getDistinctLicenses', () {
    test(
      'adds the Wikipedia CC BY-SA license if not already present',
      () async {
        when(
          sourceRepository.distinctLicenses(),
        ).thenAnswer((_) async => [(key: 'CC BY-NC', licenseUrl: null)]);

        final licenses = await service.getDistinctLicenses();

        expect(
          licenses.map((l) => l.key),
          containsAll(['CC BY-NC', 'CC BY-SA 4.0']),
        );
      },
    );

    test(
      'does not duplicate the Wikipedia license if already present',
      () async {
        when(sourceRepository.distinctLicenses()).thenAnswer(
          (_) async => [
            (
              key: 'CC BY-SA 4.0',
              licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
            ),
          ],
        );

        final licenses = await service.getDistinctLicenses();

        expect(licenses.where((l) => l.key == 'CC BY-SA 4.0'), hasLength(1));
      },
    );
  });
}
