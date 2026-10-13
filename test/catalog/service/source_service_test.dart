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

  group('SourceService.getAllSources with iNaturalist', () {
    const fishbase = Source(
      id: 'fishbase',
      name: 'FishBase',
      category: 'Taxonomy',
      citation: 'FishBase citation',
      url: 'https://www.fishbase.org',
      licenseKey: 'CC BY-NC',
      displayOrder: 10,
    );

    test('adds iNaturalist when the reference DB does not list it', () async {
      when(sourceRepository.findAll()).thenAnswer((_) async => [fishbase]);

      final sources = await service.getAllSources();

      expect(sources.map((s) => s.id), [
        'fishbase',
        'inaturalist',
        'wikipedia',
      ]);
      final iNaturalist = sources.singleWhere((s) => s.id == 'inaturalist');
      expect(iNaturalist.licenseKey, 'CC BY / CC0');
      expect(
        iNaturalist.speciesUrlTemplate,
        'https://www.inaturalist.org/taxa/{external_id}',
      );
    });

    test('keeps the reference DB\'s iNaturalist entry and adds none', () async {
      const fromReferenceDb = Source(
        id: 'inaturalist',
        name: 'iNaturalist',
        category: 'Community Photos',
        citation: 'citation from the reference DB',
        url: 'https://www.inaturalist.org',
        licenseKey: 'CC BY / CC0',
        displayOrder: 30,
      );
      when(
        sourceRepository.findAll(),
      ).thenAnswer((_) async => [fishbase, fromReferenceDb]);

      final sources = await service.getAllSources();

      expect(sources.map((s) => s.id), [
        'fishbase',
        'inaturalist',
        'wikipedia',
      ]);
      expect(
        sources.singleWhere((s) => s.id == 'inaturalist'),
        same(fromReferenceDb),
      );
    });
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
