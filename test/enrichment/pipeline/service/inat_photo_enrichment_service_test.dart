import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/pipeline/model/import_enrichment_summary.dart';
import 'package:discere/enrichment/pipeline/service/inat_photo_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/external/inaturalist/models/inat_photo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockSpeciesRepository mockSpeciesRepo;
  late MockImageService mockImageService;
  late MockINaturalistService mockINatService;
  late MockINatPhotoCacheRepository mockINatCacheRepo;
  late MockExternalIdRepository mockExternalIdRepo;
  late MockExternalIdCacheRepository mockExternalIdCacheRepo;
  late INatPhotoEnrichmentService photoService;

  setUp(() {
    mockSpeciesRepo = MockSpeciesRepository();
    mockImageService = MockImageService();
    mockINatService = MockINaturalistService();
    mockINatCacheRepo = MockINatPhotoCacheRepository();
    mockExternalIdRepo = MockExternalIdRepository();
    mockExternalIdCacheRepo = MockExternalIdCacheRepository();

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

    final taxonResolver = INatTaxonResolver(
      mockSpeciesRepo,
      mockExternalIdRepo,
      mockExternalIdCacheRepo,
    );
    photoService = INatPhotoEnrichmentService(
      mockSpeciesRepo,
      mockINatService,
      mockINatCacheRepo,
      mockImageService,
      mockExternalIdCacheRepo,
      taxonResolver,
    );
  });

  group('primary photo fetch', () {
    test('caches an empty sentinel and completes the species when the taxon is '
        'confirmed unresolvable instead of retrying forever', () async {
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
        mockINatService.fetchPhotos(
          'Natator depressa',
          taxonId: anyNamed('taxonId'),
          maxPhotos: anyNamed('maxPhotos'),
        ),
      ).thenThrow(const TaxonNotFoundException('Natator depressa'));

      final completedSpeciesIds = <String>[];
      final summary = await photoService.fetchINatPhotosForSpecies(
        {'sp1'},
        primaryOnly: true,
        onSpeciesCompleted: completedSpeciesIds.add,
      );

      verify(mockINatCacheRepo.cachePhotos('sp1', const [])).called(1);
      expect(completedSpeciesIds, ['sp1']);
      expect(summary.imageSpeciesCount, 0);
      expect(summary.imageCount, 0);
    });

    test('leaves the species pending for retry when iNat photos were found but '
        'the download silently fails, instead of completing without a local '
        'image', () async {
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
        mockINatService.fetchPhotos(
          'Natator depressa',
          taxonId: anyNamed('taxonId'),
          maxPhotos: anyNamed('maxPhotos'),
        ),
      ).thenAnswer(
        (_) async => (
          taxonId: 704,
          photos: const [
            INatPhoto(
              url:
                  'https://inaturalist-open-data.s3.amazonaws.com/photos/1/square.jpeg',
              licenseCode: 'cc-by',
            ),
          ],
          wikipediaUrl: null,
          iucnStatus: null,
        ),
      );
      // Default stub from setUp already returns an empty map here,
      // simulating a per-URL download failure that ImageService swallows
      // internally instead of throwing.

      final completedSpeciesIds = <String>[];
      final summary = await photoService.fetchINatPhotosForSpecies(
        {'sp1'},
        primaryOnly: true,
        onSpeciesCompleted: completedSpeciesIds.add,
      );

      verify(
        mockINatCacheRepo.cachePhotos('sp1', argThat(hasLength(1))),
      ).called(1);
      expect(completedSpeciesIds, isEmpty);
      // Photo metadata was still found, so this summary keeps its existing
      // "found via metadata" meaning even though nothing landed locally.
      expect(summary.imageSpeciesCount, 1);
      expect(summary.imageCount, 1);
    });

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
            iucnStatus: null,
          ),
        );

        final summary = await photoService.fetchINatPhotosForSpecies({
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
          mockExternalIdCacheRepo.saveExternalId(
            'sp1',
            ExternalIdProvider.inaturalist,
            '702',
          ),
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
        final summary = await photoService.fetchINatPhotosForSpecies(
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
  });

  group('backfill photo fetch', () {
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
        mockImageService.downloadAndSaveUrlMap(
          any,
          storageDirectory: 'external_images',
          maxConcurrent: 1,
          onProgress: anyNamed('onProgress'),
        ),
      ).thenAnswer(
        (_) async => {
          'https://inaturalist-open-data.s3.amazonaws.com/photos/1/square.jpeg':
              '/local/inat-1.jpg',
        },
      );
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
          iucnStatus: null,
        ),
      );

      final completedSpeciesIds = <String>[];
      final summary = await photoService.backfillINatPhotosForSpecies({
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
      'leaves a backfill candidate pending for retry when the download '
      'silently fails, instead of completing without a local image',
      () async {
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

        when(
          mockSpeciesRepo.getSpecies({'sp-partial'}),
        ).thenAnswer((_) async => {partial});
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
                url: 'https://example.org/inat-2.jpg',
                licenseCode: 'cc-by',
              ),
            ],
            wikipediaUrl: null,
            iucnStatus: null,
          ),
        );
        // Default stub from setUp already returns an empty map here,
        // simulating a per-URL download failure that ImageService swallows
        // internally instead of throwing.

        final completedSpeciesIds = <String>[];
        final summary = await photoService.backfillINatPhotosForSpecies({
          'sp-partial',
        }, onSpeciesCompleted: completedSpeciesIds.add);

        expect(completedSpeciesIds, isEmpty);
        // Photo metadata was still found, so this summary keeps its existing
        // "found via metadata" meaning even though nothing landed locally.
        expect(summary.imageSpeciesCount, 1);
      },
    );

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
        final summary = await photoService.backfillINatPhotosForSpecies({
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

    test('backfill treats a species with no prior iNat cache entry as a fresh '
        'candidate instead of silently skipping it', () async {
      // A species that already had a usable reference image never goes
      // through primary iNat enrichment, so its iNat photo cache is still
      // null by the time it reaches backfill — this must not be confused
      // with "already checked, nothing found" (an empty list).
      final neverChecked = Species(
        'sp-never-checked',
        '4',
        'fishbase',
        'speciosa',
        const {},
        Classification(
          'Never',
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
        mockSpeciesRepo.getSpecies({'sp-never-checked'}),
      ).thenAnswer((_) async => {neverChecked});
      when(
        mockINatCacheRepo.getCachedPhotos('sp-never-checked'),
      ).thenAnswer((_) async => null);
      when(
        mockINatService.fetchPhotos(
          any,
          taxonId: anyNamed('taxonId'),
          maxPhotos: anyNamed('maxPhotos'),
          allowTier3Fallback: anyNamed('allowTier3Fallback'),
        ),
      ).thenAnswer(
        (_) async => (
          taxonId: 789,
          photos: [
            const INatPhoto(
              url: 'https://example.org/never-checked.jpg',
              licenseCode: 'cc-by',
            ),
          ],
          wikipediaUrl: null,
          iucnStatus: null,
        ),
      );
      when(
        mockImageService.downloadAndSaveUrlMap(
          any,
          storageDirectory: 'external_images',
          maxConcurrent: 1,
          onProgress: anyNamed('onProgress'),
        ),
      ).thenAnswer(
        (_) async => {
          'https://example.org/never-checked.jpg': '/local/never-checked.jpg',
        },
      );

      final completedSpeciesIds = <String>[];
      final summary = await photoService.backfillINatPhotosForSpecies({
        'sp-never-checked',
      }, onSpeciesCompleted: completedSpeciesIds.add);

      verify(
        mockINatService.fetchPhotos(
          'Never speciosa',
          taxonId: null,
          maxPhotos: 10,
          allowTier3Fallback: true,
        ),
      ).called(1);
      expect(completedSpeciesIds, ['sp-never-checked']);
      expect(summary.imageSpeciesCount, 1);
    });
  });
}
