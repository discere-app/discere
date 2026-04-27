import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/shared/external/models/inat_common_name.dart';
import 'package:discere/shared/external/models/inat_photo.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/repository/runtime_common_name_repository.dart';
import 'package:discere/shared/model/language.dart';
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
        maxConcurrent: anyNamed('maxConcurrent'),
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
      mockRuntimeCommonNameRepo.getEntitiesWithStoredOutcome(any),
    ).thenAnswer((_) async => {});
    when(
      mockRuntimeCommonNameRepo.markNoCommonNames(
        entityKey: anyNamed('entityKey'),
        entityType: anyNamed('entityType'),
      ),
    ).thenAnswer((_) async {});
    when(
      mockRuntimeCommonNameRepo.saveSpeciesCommonNamesBatch(any),
    ).thenAnswer((_) async {});
    when(
      mockRuntimeCommonNameRepo.saveTaxonomyCommonNamesBatch(any),
    ).thenAnswer((_) async {});
    when(mockINatCacheRepo.getCachedPhotos(any)).thenAnswer((_) async => null);
    when(mockINatCacheRepo.cachePhotos(any, any)).thenAnswer((_) async {});
    when(
      mockSpeciesRepo.getScientificNameCandidates(
        any,
        preferredScientificName: anyNamed('preferredScientificName'),
      ),
    ).thenAnswer((invocation) async {
      final preferredScientificName =
          invocation.namedArguments[#preferredScientificName] as String?;
      if (preferredScientificName == null) return <String>[];
      return [preferredScientificName];
    });

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
            commonNames: <String, List<INatCommonName>>{
              'en': [INatCommonName(languageCode: 'en', name: 'Test name')],
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
            commonNames: <String, List<INatCommonName>>{
              'en': [INatCommonName(languageCode: 'en', name: 'Test name')],
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

  group('EnrichmentService - iNat common names', () {
    test(
      'persists species and taxonomy common names and returns combined summary',
      () async {
        final species = Species(
          'sp1',
          '1',
          'fishbase',
          'barbus',
          const {
            Language.de: ['Barbe'],
          },
          Classification(
            'Barbus',
            const {
              Language.en: ['Barbels'],
            },
            null,
            'Cyprinidae',
            const {
              Language.en: ['Minnows'],
            },
            'Cypriniformes',
            const {
              Language.en: ['Carps'],
            },
            'Actinopterygii',
            const {
              Language.en: ['Ray-finned fishes'],
            },
            null,
          ),
          const [],
        );

        when(
          mockSpeciesRepo.getSpecies({'sp1'}),
        ).thenAnswer((_) async => {species});
        when(
          mockINatService.fetchCommonNames(
            any,
            taxonId: anyNamed('taxonId'),
            rank: anyNamed('rank'),
          ),
        ).thenAnswer((invocation) async {
          final scientificName = invocation.positionalArguments.first as String;
          final rank = invocation.namedArguments[#rank] as String?;
          var taxonId = 999;

          if (rank == null) {
            return (
              taxonId: 101,
              commonNames: <String, List<INatCommonName>>{
                'en': [
                  INatCommonName(languageCode: 'en', name: 'Common barbel'),
                ],
              },
            );
          }

          if (rank == 'genus') {
            taxonId = 201;
          } else if (rank == 'family') {
            taxonId = 202;
          } else if (rank == 'order') {
            taxonId = 203;
          } else if (rank == 'class') {
            taxonId = 204;
          }

          return (
            taxonId: taxonId,
            commonNames: <String, List<INatCommonName>>{
              'en': [
                INatCommonName(
                  languageCode: 'en',
                  name: '$scientificName common',
                ),
              ],
            },
          );
        });

        final speciesSummary = await service.fetchSpeciesCommonNamesForSpecies({
          'sp1',
        });
        final taxonomySummary = await service
            .fetchINatTaxonomyCommonNamesForSpecies({'sp1'});
        final summary = speciesSummary + taxonomySummary;

        verify(
          mockRuntimeCommonNameRepo.saveSpeciesCommonNamesBatch(
            argThat(
              predicate(
                (dynamic records) =>
                    records
                        is Map<Species, Map<String, List<INatCommonName>>> &&
                    records.length == 1 &&
                    records.keys.single.id == 'sp1' &&
                    records.values.single['en']?.single.name == 'Common barbel',
              ),
            ),
          ),
        ).called(1);

        final taxonomyRecords =
            verify(
                  mockRuntimeCommonNameRepo.saveTaxonomyCommonNamesBatch(
                    captureAny,
                  ),
                ).captured.single
                as Iterable<RuntimeTaxonomyCommonNameRecord>;
        expect(taxonomyRecords.map((record) => record.entityKey).toSet(), {
          'genus:barbus',
          'family:cyprinidae',
          'order:cypriniformes',
          'class:actinopterygii',
        });
        expect(
          taxonomyRecords
              .where((record) => record.entityKey == 'genus:barbus')
              .single
              .referenceCommonNames,
          const {
            Language.en: ['Barbels'],
          },
        );

        expect(summary.commonNameSpeciesCount, 5);
        expect(summary.commonNameCount, 5);
      },
    );

    test(
      'falls back to alternate scientific names when species common-name lookup fails',
      () async {
        final species = Species(
          'sp1',
          '1',
          'sealifebase',
          'depressa',
          const {},
          Classification(
            'Natator',
            const {},
            null,
            'Cheloniidae',
            const {},
            'Testudines',
            const {},
            'Reptilia',
            const {},
            null,
          ),
          const [],
        );

        when(
          mockSpeciesRepo.getSpecies({'sp1'}),
        ).thenAnswer((_) async => {species});
        when(
          mockSpeciesRepo.getScientificNameCandidates(
            'sp1',
            preferredScientificName: 'Natator depressa',
          ),
        ).thenAnswer((_) async => ['Natator depressa', 'Natator depressus']);
        when(
          mockINatService.fetchCommonNames(
            'Natator depressa',
            taxonId: anyNamed('taxonId'),
            rank: anyNamed('rank'),
          ),
        ).thenAnswer((_) async => null);
        when(
          mockINatService.fetchCommonNames(
            'Natator depressus',
            taxonId: anyNamed('taxonId'),
            rank: anyNamed('rank'),
          ),
        ).thenAnswer(
          (_) async => (
            taxonId: 701,
            commonNames: <String, List<INatCommonName>>{
              'en': [
                INatCommonName(languageCode: 'en', name: 'Flatback sea turtle'),
              ],
            },
          ),
        );
        when(
          mockINatService.fetchCommonNames(
            any,
            taxonId: anyNamed('taxonId'),
            rank: 'genus',
          ),
        ).thenAnswer((_) async => null);
        when(
          mockINatService.fetchCommonNames(
            any,
            taxonId: anyNamed('taxonId'),
            rank: 'family',
          ),
        ).thenAnswer((_) async => null);
        when(
          mockINatService.fetchCommonNames(
            any,
            taxonId: anyNamed('taxonId'),
            rank: 'order',
          ),
        ).thenAnswer((_) async => null);
        when(
          mockINatService.fetchCommonNames(
            any,
            taxonId: anyNamed('taxonId'),
            rank: 'class',
          ),
        ).thenAnswer((_) async => null);

        final speciesSummary = await service.fetchSpeciesCommonNamesForSpecies({
          'sp1',
        });
        final taxonomySummary = await service
            .fetchINatTaxonomyCommonNamesForSpecies({'sp1'});
        final summary = speciesSummary + taxonomySummary;

        verifyInOrder([
          mockINatService.fetchCommonNames(
            'Natator depressa',
            taxonId: null,
            rank: null,
          ),
          mockINatService.fetchCommonNames(
            'Natator depressus',
            taxonId: null,
            rank: null,
          ),
        ]);
        verify(
          mockExternalIdCacheRepo.saveExternalId('sp1', 'inaturalist', '701'),
        ).called(1);
        expect(summary.commonNameSpeciesCount, greaterThanOrEqualTo(1));
      },
    );

    test(
      'stores an explicit no-result marker when iNat resolves but has no common names',
      () async {
        final species = Species(
          'sp1',
          '1',
          'sealifebase',
          'depressa',
          const {},
          Classification(
            'Natator',
            const {},
            null,
            'Cheloniidae',
            const {},
            'Testudines',
            const {},
            'Reptilia',
            const {},
            null,
          ),
          const [],
        );

        when(
          mockSpeciesRepo.getSpecies({'sp1'}),
        ).thenAnswer((_) async => {species});
        when(
          mockINatService.fetchCommonNames(
            'Natator depressa',
            taxonId: anyNamed('taxonId'),
            rank: anyNamed('rank'),
          ),
        ).thenAnswer(
          (_) async =>
              (taxonId: 703, commonNames: <String, List<INatCommonName>>{}),
        );
        when(
          mockINatService.fetchCommonNames(
            any,
            taxonId: anyNamed('taxonId'),
            rank: 'genus',
          ),
        ).thenAnswer((_) async => null);
        when(
          mockINatService.fetchCommonNames(
            any,
            taxonId: anyNamed('taxonId'),
            rank: 'family',
          ),
        ).thenAnswer((_) async => null);
        when(
          mockINatService.fetchCommonNames(
            any,
            taxonId: anyNamed('taxonId'),
            rank: 'order',
          ),
        ).thenAnswer((_) async => null);
        when(
          mockINatService.fetchCommonNames(
            any,
            taxonId: anyNamed('taxonId'),
            rank: 'class',
          ),
        ).thenAnswer((_) async => null);

        final speciesSummary = await service.fetchSpeciesCommonNamesForSpecies({
          'sp1',
        });
        final taxonomySummary = await service
            .fetchINatTaxonomyCommonNamesForSpecies({'sp1'});
        final summary = speciesSummary + taxonomySummary;

        verify(
          mockRuntimeCommonNameRepo.markNoCommonNames(
            entityKey: 'species:sp1',
            entityType: 'species',
          ),
        ).called(1);
        expect(summary.commonNameSpeciesCount, 0);
        expect(summary.commonNameCount, 0);
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
        verify(
          mockImageService.downloadAndSaveUrlMap(
            any,
            storageDirectory: 'external_images',
            maxConcurrent: 1,
            onProgress: anyNamed('onProgress'),
          ),
        ).called(2);
        expect(summary.imageSpeciesCount, 2);
        expect(summary.imageCount, 2);
      },
    );

    test(
      'falls back to alternate scientific names when species photo lookup fails',
      () async {
        final species = Species(
          'sp1',
          '1',
          'sealifebase',
          'depressa',
          const {},
          Classification(
            'Natator',
            const {},
            null,
            'Cheloniidae',
            const {},
            'Testudines',
            const {},
            'Reptilia',
            const {},
            null,
          ),
          const [],
        );

        when(
          mockSpeciesRepo.getSpecies({'sp1'}),
        ).thenAnswer((_) async => {species});
        when(
          mockSpeciesRepo.getScientificNameCandidates(
            'sp1',
            preferredScientificName: 'Natator depressa',
          ),
        ).thenAnswer((_) async => ['Natator depressa', 'Natator depressus']);
        when(
          mockINatService.fetchPhotos(
            'Natator depressa',
            taxonId: anyNamed('taxonId'),
            maxPhotos: anyNamed('maxPhotos'),
          ),
        ).thenAnswer((_) async => null);
        when(
          mockINatService.fetchPhotos(
            'Natator depressus',
            taxonId: anyNamed('taxonId'),
            maxPhotos: anyNamed('maxPhotos'),
          ),
        ).thenAnswer(
          (_) async => (
            taxonId: 702,
            photos: const [
              INatPhoto(
                url:
                    'https://inaturalist-open-data.s3.amazonaws.com/photos/1/square.jpeg',
                licenseCode: 'cc-by',
              ),
            ],
          ),
        );

        final summary = await service.fetchINatPhotosForSpecies({
          'sp1',
        }, primaryOnly: true);

        verifyInOrder([
          mockINatService.fetchPhotos(
            'Natator depressa',
            taxonId: null,
            maxPhotos: 1,
          ),
          mockINatService.fetchPhotos(
            'Natator depressus',
            taxonId: null,
            maxPhotos: 1,
          ),
        ]);
        verify(
          mockExternalIdCacheRepo.saveExternalId('sp1', 'inaturalist', '702'),
        ).called(1);
        expect(summary.imageSpeciesCount, 1);
      },
    );

    test(
      'completes primary photo skip-only batches without refetching cached entries',
      () async {
        final cached = Species(
          'sp-cached',
          '1',
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
        final empty = Species(
          'sp-empty',
          '2',
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
          mockSpeciesRepo.getSpecies({'sp-cached', 'sp-empty'}),
        ).thenAnswer((_) async => {cached, empty});
        when(mockINatCacheRepo.getCachedPhotos('sp-cached')).thenAnswer(
          (_) async => const [
            Picture(
              id: 'inat-1',
              species: 'sp-cached',
              url: 'https://example.org/inat-1.jpg',
              origin: 'iNaturalist',
              isUsable: 1,
            ),
          ],
        );
        when(
          mockINatCacheRepo.getCachedPhotos('sp-empty'),
        ).thenAnswer((_) async => <Picture>[]);

        final completedSpeciesIds = <String>[];
        final summary = await service.fetchINatPhotosForSpecies(
          {'sp-cached', 'sp-empty'},
          primaryOnly: true,
          onSpeciesCompleted: completedSpeciesIds.add,
        );

        verifyNever(
          mockINatService.fetchPhotos(
            any,
            taxonId: anyNamed('taxonId'),
            maxPhotos: anyNamed('maxPhotos'),
          ),
        );
        expect(summary.imageSpeciesCount, 0);
        expect(summary.imageCount, 0);
        expect(summary.commonNameSpeciesCount, 0);
        expect(summary.commonNameCount, 0);
        expect(completedSpeciesIds.toSet(), equals({'sp-cached', 'sp-empty'}));
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

      final completedSpeciesIds = <String>[];
      final summary = await service.backfillINatPhotosForSpecies({
        'sp-partial',
        'sp-full',
        'sp-empty',
      }, onSpeciesCompleted: completedSpeciesIds.add);

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
      verify(
        mockImageService.downloadAndSaveUrlMap(
          any,
          storageDirectory: 'external_images',
          maxConcurrent: 1,
          onProgress: anyNamed('onProgress'),
        ),
      ).called(1);
      expect(summary.imageSpeciesCount, 1);
      expect(
        completedSpeciesIds.toSet(),
        equals({'sp-partial', 'sp-full', 'sp-empty'}),
      );
    });

    test(
      'backfill completes terminal skip-only batches without refetching',
      () async {
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
          mockSpeciesRepo.getSpecies({'sp-full', 'sp-empty'}),
        ).thenAnswer((_) async => {full, empty});
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

        final completedSpeciesIds = <String>[];
        final summary = await service.backfillINatPhotosForSpecies({
          'sp-full',
          'sp-empty',
        }, onSpeciesCompleted: completedSpeciesIds.add);

        verifyNever(
          mockINatService.fetchPhotos(
            any,
            taxonId: anyNamed('taxonId'),
            maxPhotos: anyNamed('maxPhotos'),
          ),
        );
        expect(summary, ImportEnrichmentSummary.empty);
        expect(completedSpeciesIds.toSet(), equals({'sp-full', 'sp-empty'}));
      },
    );
  });
}
