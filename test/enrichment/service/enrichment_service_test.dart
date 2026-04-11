import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/shared/external/models/inat_photo.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../service/mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockSpeciesRepository mockSpeciesRepo;
  late MockImageService mockImageService;
  late MockINaturalistService mockINatService;
  late MockINatPhotoCacheRepository mockINatCacheRepo;
  late MockExternalIdRepository mockExternalIdRepo;
  late MockExternalIdCacheRepository mockExternalIdCacheRepo;
  late MockRuntimeCommonNameRepository mockRuntimeCommonNameRepo;
  late EnrichmentService service;

  setUp(() {
    mockSpeciesRepo = MockSpeciesRepository();
    mockImageService = MockImageService();
    mockINatService = MockINaturalistService();
    mockINatCacheRepo = MockINatPhotoCacheRepository();
    mockExternalIdRepo = MockExternalIdRepository();
    mockExternalIdCacheRepo = MockExternalIdCacheRepository();
    mockRuntimeCommonNameRepo = MockRuntimeCommonNameRepository();

    when(
      mockImageService.downloadAndSaveUrlMap(
        any,
        storageDirectory: anyNamed('storageDirectory'),
        onProgress: anyNamed('onProgress'),
      ),
    ).thenAnswer((_) async => <String, String>{});
    when(
      mockExternalIdRepo.getExternalId(any, any),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdCacheRepo.getExternalId(any, any),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdCacheRepo.saveExternalId(any, any, any),
    ).thenAnswer((_) async {});
    when(
      mockRuntimeCommonNameRepo.getCommonNamesForEntities(any),
    ).thenAnswer((_) async => {});
    when(
      mockRuntimeCommonNameRepo.saveSpeciesCommonNamesBatch(any),
    ).thenAnswer((_) async {});
    when(
      mockRuntimeCommonNameRepo.saveTaxonomyCommonNamesBatch(any),
    ).thenAnswer((_) async {});
    when(mockINatCacheRepo.getCachedPhotos(any)).thenAnswer((_) async => null);
    when(mockINatCacheRepo.cachePhotos(any, any)).thenAnswer((_) async {});

    when(mockSpeciesRepo.getSpecies(any)).thenAnswer((inv) async {
      final ids = inv.positionalArguments[0] as Set<String>;
      return ids
          .map(
            (id) => Species(
              id,
              id,
              'mockSource',
              'mockName',
              {},
              Classification('', {}, null, '', {}, '', {}, '', {}, null),
              [],
            ),
          )
          .cast<Species>()
          .toSet();
    });

    service = EnrichmentService(
      mockSpeciesRepo,
      mockImageService,
      mockINatService,
      mockINatCacheRepo,
      mockExternalIdRepo,
      mockExternalIdCacheRepo,
      runtimeCommonNameRepository: mockRuntimeCommonNameRepo,
    );
  });

  group('EnrichmentService - taxonomy iNat IDs', () {
    test(
      'uses ETL-provided taxonomy external IDs before live resolve',
      () async {
        when(mockSpeciesRepo.getSpecies({'sp1'})).thenAnswer(
          (_) async => {
            Species(
              'sp1',
              '1',
              'fishbase',
              'barbus',
              const {},
              Classification(
                'Barbus',
                const {},
                null,
                'Cyprinidae',
                const {},
                'Cypriniformes',
                const {},
                'Actinopterygii',
                const {},
                null,
              ),
              const [],
            ),
          },
        );
        when(
          mockExternalIdRepo.getExternalId('genus:barbus', 'inaturalist'),
        ).thenAnswer((_) async => '86989');
        when(
          mockExternalIdRepo.getExternalId('family:cyprinidae', 'inaturalist'),
        ).thenAnswer((_) async => '51783');
        when(
          mockExternalIdRepo.getExternalId(
            'order:cypriniformes',
            'inaturalist',
          ),
        ).thenAnswer((_) async => '48051');
        when(
          mockExternalIdRepo.getExternalId(
            'class:actinopterygii',
            'inaturalist',
          ),
        ).thenAnswer((_) async => '47178');
        when(
          mockINatService.fetchCommonNames(
            any,
            taxonId: anyNamed('taxonId'),
            rank: anyNamed('rank'),
          ),
        ).thenAnswer(
          (_) async => (
            taxonId: 1,
            commonNames: <String, List<String>>{
              'en': ['Test name'],
            },
          ),
        );

        await service.fetchINatTaxonomyCommonNamesForSpecies({'sp1'});

        verify(
          mockINatService.fetchCommonNames(
            'Barbus',
            taxonId: 86989,
            rank: 'genus',
          ),
        ).called(1);
        verify(
          mockINatService.fetchCommonNames(
            'Cyprinidae',
            taxonId: 51783,
            rank: 'family',
          ),
        ).called(1);
        verify(
          mockINatService.fetchCommonNames(
            'Cypriniformes',
            taxonId: 48051,
            rank: 'order',
          ),
        ).called(1);
        verify(
          mockINatService.fetchCommonNames(
            'Actinopterygii',
            taxonId: 47178,
            rank: 'class',
          ),
        ).called(1);
      },
    );

    test(
      'caches runtime-resolved taxonomy external IDs with taxonomy keys',
      () async {
        when(mockSpeciesRepo.getSpecies({'sp1'})).thenAnswer(
          (_) async => {
            Species(
              'sp1',
              '1',
              'fishbase',
              'barbus',
              const {},
              Classification(
                'Barbus',
                const {},
                null,
                'Cyprinidae',
                const {},
                'Cypriniformes',
                const {},
                'Actinopterygii',
                const {},
                null,
              ),
              const [],
            ),
          },
        );
        when(
          mockINatService.fetchCommonNames(
            any,
            taxonId: anyNamed('taxonId'),
            rank: anyNamed('rank'),
          ),
        ).thenAnswer(
          (invocation) async => (
            taxonId: invocation.namedArguments[#rank] == 'genus'
                ? 86989
                : 51783,
            commonNames: <String, List<String>>{
              'en': ['Test name'],
            },
          ),
        );

        await service.fetchINatTaxonomyCommonNamesForSpecies({'sp1'});

        verify(
          mockExternalIdCacheRepo.saveExternalId(
            'genus:barbus',
            'inaturalist',
            '86989',
          ),
        ).called(1);
      },
    );
  });

  group('EnrichmentService - iNat photo enrichment', () {
    test(
      'prioritizes species without reference images and skips cached entries',
      () async {
        final withoutReferenceImages = Species(
          'sp-no-ref',
          '1',
          'fishbase',
          'speciosa',
          const {},
          Classification(
            'Noimg',
            const {},
            null,
            'Family',
            const {},
            'Order',
            const {},
            'Class',
            const {},
            null,
          ),
          const [],
        );
        final withReferenceImages = Species(
          'sp-with-ref',
          '2',
          'fishbase',
          'speciosa',
          const {},
          Classification(
            'Withimg',
            const {},
            null,
            'Family',
            const {},
            'Order',
            const {},
            'Class',
            const {},
            null,
          ),
          const [
            Picture(
              id: 'ref-1',
              species: 'sp-with-ref',
              url: 'https://example.org/ref.jpg',
              origin: 'reference',
              isUsable: 1,
            ),
          ],
        );
        final alreadyCached = Species(
          'sp-cached',
          '3',
          'fishbase',
          'speciosa',
          const {},
          Classification(
            'Cached',
            const {},
            null,
            'Family',
            const {},
            'Order',
            const {},
            'Class',
            const {},
            null,
          ),
          const [],
        );

        when(
          mockSpeciesRepo.getSpecies({'sp-no-ref', 'sp-with-ref', 'sp-cached'}),
        ).thenAnswer(
          (_) async => {
            withReferenceImages,
            withoutReferenceImages,
            alreadyCached,
          },
        );
        when(
          mockINatCacheRepo.getCachedPhotos('sp-no-ref'),
        ).thenAnswer((_) async => null);
        when(
          mockINatCacheRepo.getCachedPhotos('sp-with-ref'),
        ).thenAnswer((_) async => null);
        when(mockINatCacheRepo.getCachedPhotos('sp-cached')).thenAnswer(
          (_) async => const [
            Picture(
              id: 'inat-1',
              species: 'sp-cached',
              url: 'https://example.org/inat.jpg',
              origin: 'iNaturalist',
              isUsable: 1,
            ),
          ],
        );
        when(
          mockINatService.fetchPhotos(
            any,
            taxonId: anyNamed('taxonId'),
            maxPhotos: anyNamed('maxPhotos'),
          ),
        ).thenAnswer(
          (invocation) async => (
            taxonId: 123,
            photos: [
              INatPhoto(
                url:
                    'https://inaturalist-open-data.s3.amazonaws.com/photos/'
                    '${invocation.positionalArguments.first.hashCode}/square.jpeg',
                licenseCode: 'cc-by',
              ),
            ],
          ),
        );

        final summary = await service.fetchINatPhotosForSpecies(
          {'sp-no-ref', 'sp-with-ref', 'sp-cached'},
          primaryOnly: true,
          prioritizeSpeciesWithoutImages: true,
        );

        verifyInOrder([
          mockINatService.fetchPhotos(
            'Noimg speciosa',
            taxonId: null,
            maxPhotos: 1,
          ),
          mockINatService.fetchPhotos(
            'Withimg speciosa',
            taxonId: null,
            maxPhotos: 1,
          ),
        ]);
        verifyNever(
          mockINatService.fetchPhotos(
            'Cached speciosa',
            taxonId: anyNamed('taxonId'),
            maxPhotos: anyNamed('maxPhotos'),
          ),
        );
        expect(summary.imageSpeciesCount, 2);
        expect(summary.imageCount, 2);
      },
    );

    test('backfills only species with partial cached iNat galleries', () async {
      final partial = Species(
        'sp-partial',
        '1',
        'fishbase',
        'speciosa',
        const {},
        Classification(
          'Partial',
          const {},
          null,
          'Family',
          const {},
          'Order',
          const {},
          'Class',
          const {},
          null,
        ),
        const [],
      );
      final full = Species(
        'sp-full',
        '2',
        'fishbase',
        'speciosa',
        const {},
        Classification(
          'Full',
          const {},
          null,
          'Family',
          const {},
          'Order',
          const {},
          'Class',
          const {},
          null,
        ),
        const [],
      );
      final empty = Species(
        'sp-empty',
        '3',
        'fishbase',
        'speciosa',
        const {},
        Classification(
          'Empty',
          const {},
          null,
          'Family',
          const {},
          'Order',
          const {},
          'Class',
          const {},
          null,
        ),
        const [],
      );

      when(
        mockSpeciesRepo.getSpecies({'sp-partial', 'sp-full', 'sp-empty'}),
      ).thenAnswer((_) async => {partial, full, empty});
      when(mockINatCacheRepo.getCachedPhotos('sp-partial')).thenAnswer(
        (_) async => const [
          Picture(
            id: 'inat-1',
            species: 'sp-partial',
            url: 'https://example.org/inat-1.jpg',
            origin: 'iNaturalist',
            isUsable: 1,
          ),
        ],
      );
      when(mockINatCacheRepo.getCachedPhotos('sp-full')).thenAnswer(
        (_) async => List.generate(
          10,
          (index) => Picture(
            id: 'inat-full-$index',
            species: 'sp-full',
            url: 'https://example.org/full-$index.jpg',
            origin: 'iNaturalist',
            isUsable: 1,
          ),
        ),
      );
      when(
        mockINatCacheRepo.getCachedPhotos('sp-empty'),
      ).thenAnswer((_) async => <Picture>[]);
      when(
        mockINatService.fetchPhotos(
          any,
          taxonId: anyNamed('taxonId'),
          maxPhotos: anyNamed('maxPhotos'),
        ),
      ).thenAnswer(
        (_) async => (
          taxonId: 456,
          photos: [
            const INatPhoto(
              url:
                  'https://inaturalist-open-data.s3.amazonaws.com/photos/1/square.jpeg',
              licenseCode: 'cc-by',
            ),
          ],
        ),
      );

      final summary = await service.backfillINatPhotosForSpecies({
        'sp-partial',
        'sp-full',
        'sp-empty',
      });

      verify(
        mockINatService.fetchPhotos(
          'Partial speciosa',
          taxonId: null,
          maxPhotos: 10,
        ),
      ).called(1);
      verifyNever(
        mockINatService.fetchPhotos(
          'Full speciosa',
          taxonId: anyNamed('taxonId'),
          maxPhotos: anyNamed('maxPhotos'),
        ),
      );
      verifyNever(
        mockINatService.fetchPhotos(
          'Empty speciosa',
          taxonId: anyNamed('taxonId'),
          maxPhotos: anyNamed('maxPhotos'),
        ),
      );
      expect(summary.imageSpeciesCount, 1);
    });
  });
}
