import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/service/species_photo_service.dart';
import 'package:discere/shared/external/models/inat_photo.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../service/mocks.mocks.dart';

void main() {
  late MockINatPhotoCacheRepository mockPhotoCacheRepository;
  late MockINaturalistService mockINatService;
  late MockExternalIdRepository mockExternalIdRepository;
  late MockExternalIdCacheRepository mockExternalIdCacheRepository;
  late SpeciesPhotoService service;

  setUp(() {
    mockPhotoCacheRepository = MockINatPhotoCacheRepository();
    mockINatService = MockINaturalistService();
    mockExternalIdRepository = MockExternalIdRepository();
    mockExternalIdCacheRepository = MockExternalIdCacheRepository();

    when(
      mockPhotoCacheRepository.getCachedPhotos(any),
    ).thenAnswer((_) async => null);
    when(
      mockPhotoCacheRepository.cachePhotos(any, any),
    ).thenAnswer((_) async {});
    when(
      mockExternalIdRepository.getExternalId(any, any),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdCacheRepository.getExternalId(any, any),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdCacheRepository.saveExternalId(any, any, any),
    ).thenAnswer((_) async {});

    service = SpeciesPhotoService(
      mockPhotoCacheRepository,
      iNatService: mockINatService,
      externalIdRepository: mockExternalIdRepository,
      externalIdCacheRepository: mockExternalIdCacheRepository,
    );
  });

  test('passes reference-db taxon id to iNat fallback fetch', () async {
    final species = _species('sp1');
    when(
      mockExternalIdRepository.getExternalId('sp1', 'inaturalist'),
    ).thenAnswer((_) async => '123');
    when(
      mockINatService.fetchPhotos(species.getBinomialName(), taxonId: 123),
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
      ),
    );

    final pictures = await service.getPhotosWithFallback(species);

    expect(pictures, hasLength(1));
    verify(
      mockINatService.fetchPhotos(species.getBinomialName(), taxonId: 123),
    ).called(1);
    verifyNever(
      mockExternalIdCacheRepository.getExternalId('sp1', 'inaturalist'),
    );
  });

  test(
    'falls back to cached runtime taxon id when no reference id exists',
    () async {
      final species = _species('sp1');
      when(
        mockExternalIdCacheRepository.getExternalId('sp1', 'inaturalist'),
      ).thenAnswer((_) async => '456');
      when(
        mockINatService.fetchPhotos(species.getBinomialName(), taxonId: 456),
      ).thenAnswer((_) async => (taxonId: 456, photos: const <INatPhoto>[]));

      await service.getPhotosWithFallback(species);

      verify(
        mockINatService.fetchPhotos(species.getBinomialName(), taxonId: 456),
      ).called(1);
    },
  );
}

Species _species(String id) {
  return Species(
    id,
    id,
    'fishbase',
    'ocellaris',
    const {Language.en: 'Clownfish'},
    Classification(
      'Amphiprion',
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
