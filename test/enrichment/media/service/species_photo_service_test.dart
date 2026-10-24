import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/media/service/species_photo_service.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/external/inaturalist/inat_ancestry_requirement.dart';
import 'package:discere/external/inaturalist/inat_taxon_id_resolver.dart';
import 'package:discere/external/inaturalist/models/inat_photo.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

void main() {
  late MockINatPhotoCacheRepository mockPhotoCacheRepository;
  late MockINatPhotoApi mockINatService;
  late MockExternalIdRepository mockExternalIdRepository;
  late MockExternalIdCacheRepository mockExternalIdCacheRepository;
  late MockExternalIdRejectionRepository mockRejections;
  late MockINatAllowedAncestorRepository mockAllowedAncestors;
  late MockINatTaxonIdResolver mockTaxonIds;
  late SpeciesPhotoService service;

  setUp(() {
    mockPhotoCacheRepository = MockINatPhotoCacheRepository();
    mockINatService = MockINatPhotoApi();
    mockExternalIdRepository = MockExternalIdRepository();
    mockExternalIdCacheRepository = MockExternalIdCacheRepository();
    mockRejections = MockExternalIdRejectionRepository();
    mockAllowedAncestors = MockINatAllowedAncestorRepository();
    mockTaxonIds = MockINatTaxonIdResolver();

    when(
      mockPhotoCacheRepository.getCachedPhotos(any),
    ).thenAnswer((_) async => null);
    when(
      mockPhotoCacheRepository.cachePhotos(any, any),
    ).thenAnswer((_) async {});
    when(
      mockExternalIdRepository.getExternalIdsForProvider(any, any),
    ).thenAnswer((_) async => {});
    when(
      mockExternalIdCacheRepository.getExternalIdsForProvider(any, any),
    ).thenAnswer((_) async => {});
    when(mockRejections.isRejected(any, any)).thenAnswer((_) async => false);
    when(
      mockAllowedAncestors.requirementForSpecies(any),
    ).thenAnswer((_) async => null);
    when(
      mockTaxonIds.resolve(any, ancestry: anyNamed('ancestry')),
    ).thenThrow(const TaxonNotFoundException('unknown'));
    when(
      mockExternalIdCacheRepository.getExternalId(any, any),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdCacheRepository.saveExternalId(any, any, any),
    ).thenAnswer((_) async {});

    service = SpeciesPhotoService(
      mockPhotoCacheRepository,
      iNatPhotos: mockINatService,
      taxonResolver: INatTaxonResolver(
        MockSpeciesRepository(),
        mockExternalIdRepository,
        mockExternalIdCacheRepository,
        mockRejections,
        mockAllowedAncestors,
        mockTaxonIds,
      ),
      externalIdCacheRepository: mockExternalIdCacheRepository,
    );
  });

  test('passes reference-db taxon id to iNat fallback fetch', () async {
    final species = _species('sp1');
    when(
      mockExternalIdRepository.getExternalIdsForProvider({
        'sp1',
      }, ExternalIdProvider.inaturalist),
    ).thenAnswer((_) async => {'sp1': 123});
    when(
      mockINatService.fetchPhotos(
        species.getBinomialName(),
        taxonId: 123,
        allowTier3Fallback: true,
      ),
    ).thenAnswer(
      (_) async => (
        taxonId: 123,
        photos: const [
          INatPhoto(
            url: 'https://static.inaturalist.org/photos/1/square.jpeg',
            attribution: 'Author',
            licenseCode: 'cc-by',
          ),
        ],
        wikipediaUrl: null,
        iucnStatus: null,
      ),
    );

    final pictures = await service.getPhotosWithFallback(species);

    expect(pictures, hasLength(1));
    verify(
      mockINatService.fetchPhotos(
        species.getBinomialName(),
        taxonId: 123,
        allowTier3Fallback: true,
      ),
    ).called(1);
    verifyNever(
      mockExternalIdCacheRepository.getExternalIdsForProvider(any, any),
    );
  });

  test(
    'falls back to cached runtime taxon id when no reference id exists',
    () async {
      final species = _species('sp1');
      when(
        mockExternalIdCacheRepository.getExternalIdsForProvider({
          'sp1',
        }, ExternalIdProvider.inaturalist),
      ).thenAnswer((_) async => {'sp1': 456});
      when(
        mockINatService.fetchPhotos(
          species.getBinomialName(),
          taxonId: 456,
          allowTier3Fallback: true,
        ),
      ).thenAnswer(
        (_) async => (
          taxonId: 456,
          photos: const <INatPhoto>[],
          wikipediaUrl: null,
          iucnStatus: null,
        ),
      );

      await service.getPhotosWithFallback(species);

      verify(
        mockINatService.fetchPhotos(
          species.getBinomialName(),
          taxonId: 456,
          allowTier3Fallback: true,
        ),
      ).called(1);
    },
  );

  test('persists the wikipedia URL alongside the resolved taxon id', () async {
    final species = _species('sp1');
    when(
      mockExternalIdRepository.getExternalIdsForProvider({
        'sp1',
      }, ExternalIdProvider.inaturalist),
    ).thenAnswer((_) async => {'sp1': 123});
    when(
      mockINatService.fetchPhotos(
        species.getBinomialName(),
        taxonId: 123,
        allowTier3Fallback: true,
      ),
    ).thenAnswer(
      (_) async => (
        taxonId: 123,
        photos: const <INatPhoto>[],
        wikipediaUrl: 'https://en.wikipedia.org/wiki/Example',
        iucnStatus: null,
      ),
    );

    await service.getPhotosWithFallback(species);

    verify(
      mockExternalIdCacheRepository.saveExternalId(
        'sp1',
        ExternalIdProvider.wikipedia,
        'https://en.wikipedia.org/wiki/Example',
      ),
    ).called(1);
  });

  test('does not persist a wikipedia URL when iNat has none on file', () async {
    final species = _species('sp1');
    when(
      mockExternalIdRepository.getExternalIdsForProvider({
        'sp1',
      }, ExternalIdProvider.inaturalist),
    ).thenAnswer((_) async => {'sp1': 123});
    when(
      mockINatService.fetchPhotos(
        species.getBinomialName(),
        taxonId: 123,
        allowTier3Fallback: true,
      ),
    ).thenAnswer(
      (_) async => (
        taxonId: 123,
        photos: const <INatPhoto>[],
        wikipediaUrl: null,
        iucnStatus: null,
      ),
    );

    await service.getPhotosWithFallback(species);

    verifyNever(
      mockExternalIdCacheRepository.saveExternalId(
        'sp1',
        ExternalIdProvider.wikipedia,
        any,
      ),
    );
  });

  test('persists the IUCN status alongside the resolved taxon id', () async {
    final species = _species('sp1');
    when(
      mockExternalIdRepository.getExternalIdsForProvider({
        'sp1',
      }, ExternalIdProvider.inaturalist),
    ).thenAnswer((_) async => {'sp1': 123});
    when(
      mockINatService.fetchPhotos(
        species.getBinomialName(),
        taxonId: 123,
        allowTier3Fallback: true,
      ),
    ).thenAnswer(
      (_) async => (
        taxonId: 123,
        photos: const <INatPhoto>[],
        wikipediaUrl: null,
        iucnStatus: 'vu',
      ),
    );

    await service.getPhotosWithFallback(species);

    verify(
      mockExternalIdCacheRepository.saveExternalId(
        'sp1',
        ExternalIdProvider.iucnStatus,
        'vu',
      ),
    ).called(1);
  });

  test('does not search iNat by a lone epithet', () async {
    final species = _species('sp1', genus: null);

    final pictures = await service.getPhotosWithFallback(species);

    expect(pictures, isEmpty);
    verifyNever(
      mockINatService.fetchPhotos(
        any,
        taxonId: anyNamed('taxonId'),
        maxPhotos: anyNamed('maxPhotos'),
        allowTier3Fallback: anyNamed('allowTier3Fallback'),
      ),
    );
  });

  test('fetches by the id a name search finds under the allowed phyla', () async {
    final species = _species('sp1');
    const fishes = INatAncestryRequirement([
      {2},
    ]);
    when(
      mockAllowedAncestors.requirementForSpecies(any),
    ).thenAnswer((_) async => fishes);
    when(
      mockTaxonIds.resolve('Amphiprion ocellaris', ancestry: fishes),
    ).thenAnswer((_) async => 789);
    when(
      mockINatService.fetchPhotos(
        species.getBinomialName(),
        taxonId: 789,
        allowTier3Fallback: true,
      ),
    ).thenAnswer(
      (_) async => (
        taxonId: 789,
        photos: const <INatPhoto>[],
        wikipediaUrl: null,
        iucnStatus: null,
      ),
    );

    await service.getPhotosWithFallback(species);

    verify(
      mockINatService.fetchPhotos(
        species.getBinomialName(),
        taxonId: 789,
        allowTier3Fallback: true,
      ),
    ).called(1);
  });

  test('does not search for a species the ETL rejected', () async {
    final species = _species('sp1');
    when(
      mockRejections.isRejected('sp1', ExternalIdProvider.inaturalist),
    ).thenAnswer((_) async => true);

    final pictures = await service.getPhotosWithFallback(species);

    expect(pictures, isEmpty);
    verifyNever(mockTaxonIds.resolve(any, ancestry: anyNamed('ancestry')));
    verifyNever(
      mockINatService.fetchPhotos(
        any,
        taxonId: anyNamed('taxonId'),
        maxPhotos: anyNamed('maxPhotos'),
        allowTier3Fallback: anyNamed('allowTier3Fallback'),
      ),
    );
    verifyNever(mockPhotoCacheRepository.cachePhotos(any, any));
  });

  test('does not persist an IUCN status when iNat has none on file', () async {
    final species = _species('sp1');
    when(
      mockExternalIdRepository.getExternalIdsForProvider({
        'sp1',
      }, ExternalIdProvider.inaturalist),
    ).thenAnswer((_) async => {'sp1': 123});
    when(
      mockINatService.fetchPhotos(
        species.getBinomialName(),
        taxonId: 123,
        allowTier3Fallback: true,
      ),
    ).thenAnswer(
      (_) async => (
        taxonId: 123,
        photos: const <INatPhoto>[],
        wikipediaUrl: null,
        iucnStatus: null,
      ),
    );

    await service.getPhotosWithFallback(species);

    verifyNever(
      mockExternalIdCacheRepository.saveExternalId(
        'sp1',
        ExternalIdProvider.iucnStatus,
        any,
      ),
    );
  });
}

Species _species(String id, {String? genus = 'Amphiprion'}) {
  return Species(
    id,
    id,
    'fishbase',
    'ocellaris',
    const {
      Language.en: ['Clownfish'],
    },
    Classification(
      genus,
      const {},
      null,
      'Pomacentridae',
      const {},
      'Perciformes',
      const {},
      'Actinopterygii',
      const {},
      null,
    ),
    const [],
  );
}
