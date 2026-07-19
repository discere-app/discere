import 'dart:convert';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/repository/runtime_common_name_repository.dart';
import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/enrichment/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/external/inaturalist/models/inat_common_name.dart';
import 'package:discere/external/inaturalist/models/inat_photo.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

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
  late TaxonomyCommonNameEnrichmentService taxonomyService;

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
      mockExternalIdRepo.getExternalIdsForProvider(any, any),
    ).thenAnswer((_) async => {});
    when(
      mockExternalIdCacheRepo.getExternalId(any, any),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdCacheRepo.getExternalIdsForProvider(any, any),
    ).thenAnswer((_) async => {});
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
    taxonomyService = TaxonomyCommonNameEnrichmentService(
      mockSpeciesRepo,
      mockINatService,
      mockExternalIdRepo,
      mockExternalIdCacheRepo,
      mockRuntimeCommonNameRepo,
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
        final taxonomySummary = await taxonomyService
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
        final taxonomySummary = await taxonomyService
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
          mockExternalIdCacheRepo.saveExternalId('sp1', ExternalIdProvider.inaturalist, '701'),
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
        final taxonomySummary = await taxonomyService
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
            wikipediaUrl: null,
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
            wikipediaUrl: null,
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
          mockExternalIdCacheRepo.saveExternalId('sp1', ExternalIdProvider.inaturalist, '702'),
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
          allowTier3Fallback: anyNamed('allowTier3Fallback'),
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
          wikipediaUrl: null,
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
          allowTier3Fallback: true,
        ),
      ).called(1);
      verifyNever(
        mockINatService.fetchPhotos(
          'Full speciosa',
          taxonId: anyNamed('taxonId'),
          maxPhotos: anyNamed('maxPhotos'),
          allowTier3Fallback: anyNamed('allowTier3Fallback'),
        ),
      );
      verifyNever(
        mockINatService.fetchPhotos(
          'Empty speciosa',
          taxonId: anyNamed('taxonId'),
          maxPhotos: anyNamed('maxPhotos'),
          allowTier3Fallback: anyNamed('allowTier3Fallback'),
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

  group('EnrichmentService - iNat regression flow', () {
    test(
      'runs photo, species-name and taxonomy-name enrichment through V2 plus legacy common-name endpoint',
      () async {
        final alpha = Species(
          'sp-alpha',
          '1',
          'fishbase',
          'alpha',
          const {},
          Classification(
            'Specius',
            const {},
            null,
            'Sharedidae',
            const {},
            'Sharediformes',
            const {},
            'Actinopterygii',
            const {},
            null,
          ),
          const [],
        );
        final beta = Species(
          'sp-beta',
          '2',
          'fishbase',
          'beta',
          const {},
          Classification(
            'Specius',
            const {},
            null,
            'Sharedidae',
            const {},
            'Sharediformes',
            const {},
            'Actinopterygii',
            const {},
            null,
          ),
          const [],
        );
        final requests = <Uri>[];

        final client = MockClient((request) async {
          requests.add(request.url);

          if (request.url.host == 'api.inaturalist.org' &&
              request.url.path == '/v2/taxa') {
            final query = request.url.queryParameters['q'];
            final rank =
                request.url.queryParametersAll['rank']?.single ??
                request.url.queryParameters['rank'];
            final taxonIdByKey = <String, int>{
              'Specius alpha|species': 1001,
              'Specius beta|species': 1002,
              'Specius|genus': 2001,
              'Sharedidae|family': 2002,
              'Sharediformes|order': 2003,
              'Actinopterygii|class': 2004,
            };
            final id = taxonIdByKey['$query|$rank'];
            return http.Response(
              jsonEncode({
                'results': id == null
                    ? const []
                    : [
                        {
                          'id': id,
                          'name': query,
                          'rank': rank,
                          'matched_term': query,
                        },
                      ],
              }),
              200,
            );
          }

          if (request.url.host == 'api.inaturalist.org' &&
              request.url.path == '/v2/taxa/1001') {
            return http.Response(
              jsonEncode({
                'results': [
                  {'id': 1001, 'name': 'Specius alpha', 'taxon_photos': []},
                ],
              }),
              200,
            );
          }

          if (request.url.host == 'api.inaturalist.org' &&
              request.url.path == '/v2/taxa/1002') {
            return http.Response(
              jsonEncode({
                'results': [
                  {'id': 1002, 'name': 'Specius beta', 'taxon_photos': []},
                ],
              }),
              200,
            );
          }

          if (request.url.host == 'api.inaturalist.org' &&
              request.url.path == '/v2/observations') {
            final taxonId =
                request.url.queryParametersAll['taxon_id']?.single ??
                request.url.queryParameters['taxon_id'];
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'observation_photos': [
                      {
                        'photo': {
                          'url':
                              'https://static.inaturalist.org/photos/$taxonId/square.jpeg',
                          'license_code': 'cc-by',
                        },
                      },
                    ],
                  },
                ],
              }),
              200,
            );
          }

          if (request.url.host == 'www.inaturalist.org' &&
              request.url.path == '/taxon_names.json') {
            final taxonId = request.url.queryParameters['taxon_id'];
            return http.Response(
              jsonEncode([
                {
                  'name': 'Common name $taxonId',
                  'lexicon': 'English',
                  'position': 1,
                },
              ]),
              200,
            );
          }

          return http.Response('', 404);
        });

        final integratedINatService = INaturalistService(client: client);
        final integratedService = EnrichmentService(
          mockSpeciesRepo,
          mockImageService,
          integratedINatService,
          mockINatCacheRepo,
          mockExternalIdRepo,
          mockExternalIdCacheRepo,
          runtimeCommonNameRepository: mockRuntimeCommonNameRepo,
        );
        final integratedTaxonomyService = TaxonomyCommonNameEnrichmentService(
          mockSpeciesRepo,
          integratedINatService,
          mockExternalIdRepo,
          mockExternalIdCacheRepo,
          mockRuntimeCommonNameRepo,
        );

        when(
          mockSpeciesRepo.getSpecies({'sp-alpha', 'sp-beta'}),
        ).thenAnswer((_) async => {alpha, beta});
        when(
          mockSpeciesRepo.getScientificNameCandidates(
            'sp-alpha',
            preferredScientificName: 'Specius alpha',
          ),
        ).thenAnswer((_) async => ['Specius alpha']);
        when(
          mockSpeciesRepo.getScientificNameCandidates(
            'sp-beta',
            preferredScientificName: 'Specius beta',
          ),
        ).thenAnswer((_) async => ['Specius beta']);

        final photoSummary = await integratedService.fetchINatPhotosForSpecies(
          {'sp-alpha', 'sp-beta'},
          primaryOnly: false,
          maxConcurrent: 1,
        );
        final speciesNameSummary = await integratedService
            .fetchSpeciesCommonNamesForSpecies({
              'sp-alpha',
              'sp-beta',
            }, maxConcurrent: 1);
        final workPlan = await integratedTaxonomyService
            .buildTaxonomyWorkPlanForSpecies({'sp-alpha', 'sp-beta'});
        final taxonomySummary = await integratedTaxonomyService
            .fetchINatTaxonomyCommonNamesForEntityKeys(
              {'sp-alpha', 'sp-beta'},
              entityKeys: workPlan.map((item) => item.runtimeEntityKey),
              maxConcurrent: 1,
            );

        expect(photoSummary.imageSpeciesCount, 2);
        expect(photoSummary.imageCount, 2);
        expect(speciesNameSummary.commonNameSpeciesCount, 2);
        expect(taxonomySummary.commonNameSpeciesCount, 4);

        verify(
          mockRuntimeCommonNameRepo.saveSpeciesCommonNamesBatch(
            argThat(hasLength(2)),
          ),
        ).called(1);
        verify(
          mockRuntimeCommonNameRepo.saveTaxonomyCommonNamesBatch(
            argThat(hasLength(4)),
          ),
        ).called(1);

        expect(requests.where((uri) => uri.path == '/v2/taxa'), isNotEmpty);
        expect(
          requests.where((uri) => uri.path == '/v2/taxa/1001'),
          hasLength(1),
        );
        expect(
          requests.where((uri) => uri.path == '/v2/taxa/1002'),
          hasLength(1),
        );
        expect(
          requests.where((uri) => uri.path == '/v2/observations'),
          hasLength(2),
        );
        expect(
          requests.where((uri) => uri.path == '/taxon_names.json'),
          hasLength(6),
        );
        expect(requests.any((uri) => uri.path.startsWith('/v1/')), isFalse);
      },
    );
  });
}
