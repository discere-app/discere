import 'package:discere/enrichment/external/models/inat_photo.dart';
import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/catalog/service/species_image_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../service/mocks.mocks.dart';

Species makeSpecies({
  String id = 'sp1',
  List<Picture> pictures = const [
    Picture(
      id: 'img1',
      species: 'sp1',
      origin: 'fishbase',
      url: 'http://example.com/img1.jpg',
      licenseKey: 'unknown',
      isUsable: 1,
    ),
  ],
}) {
  return Species(
    id,
    'ext1',
    'fishbase',
    'carcharias',
    {Language.en: 'Great white shark'},
    Classification(
      'Carcharodon',
      const {},
      null,
      'Lamnidae',
      const {},
      'Lamniformes',
      const {},
      'Chondrichthyes',
      const {},
      null,
    ),
    pictures,
  );
}

void main() {
  late MockImageService mockImageService;
  late MockINatPhotoCacheRepository mockINatCacheRepo;
  late MockINaturalistService mockINatService;
  late MockExternalIdCacheRepository mockExternalIdCacheRepository;
  late SpeciesImageService service;

  setUp(() {
    mockImageService = MockImageService();
    mockINatCacheRepo = MockINatPhotoCacheRepository();
    mockINatService = MockINaturalistService();
    mockExternalIdCacheRepository = MockExternalIdCacheRepository();

    when(
      mockImageService.downloadAndSavePicturesMap(any),
    ).thenAnswer((_) async => {'http://example.com/img1.jpg': '/local/img1.jpg'});
    when(
      mockImageService.resolveSavedPicturesMap(any),
    ).thenAnswer((_) async => {'http://example.com/img1.jpg': '/local/img1.jpg'});
    when(mockINatCacheRepo.getCachedPhotos(any)).thenAnswer((_) async => []);
    when(mockINatCacheRepo.cachePhotos(any, any)).thenAnswer((_) async {});
    when(
      mockExternalIdCacheRepository.saveExternalId(any, any, any),
    ).thenAnswer((_) async {});

    service = SpeciesImageService(
      mockImageService,
      mockINatCacheRepo,
      iNatService: mockINatService,
      externalIdCacheRepository: mockExternalIdCacheRepository,
    );
  });

  test('merges cached iNat photos into the species picture list', () async {
    final species = makeSpecies();
    when(mockINatCacheRepo.getCachedPhotos('sp1')).thenAnswer(
      (_) async => const [
        Picture(
          id: 'inat1',
          species: 'sp1',
          origin: 'iNaturalist',
          url: 'http://example.com/inat.jpg',
          licenseKey: 'CC-BY',
          isUsable: 1,
        ),
      ],
    );

    final pictures = await service.withCachedINatPhotos(species);

    expect(pictures.length, 2);
    expect(pictures.last.origin, 'iNaturalist');
  });

  test('fetches live iNat photos and persists cache metadata', () async {
    final species = makeSpecies(pictures: const []);
    when(mockINatCacheRepo.getCachedPhotos('sp1')).thenAnswer((_) async => null);
    when(
      mockINatService.fetchPhotos(any, taxonId: anyNamed('taxonId')),
    ).thenAnswer(
      (_) async => (
        taxonId: 123,
        photos: const [
          INatPhoto(
            url: 'https://static.inaturalist.org/photos/1/square.jpeg',
            attribution: 'Jane Doe',
            licenseCode: 'cc-by',
          ),
        ],
      ),
    );

    final speciesWithImages = await service.getSpeciesWithLocalImages(
      species,
      downloadMissing: false,
      fetchLiveINatPhotos: true,
    );

    verify(mockINatCacheRepo.cachePhotos('sp1', any)).called(1);
    verify(
      mockExternalIdCacheRepository.saveExternalId(
        'sp1',
        'inaturalist',
        '123',
      ),
    ).called(1);
    expect(speciesWithImages.species.pictures, hasLength(1));
    expect(speciesWithImages.species.pictures.first.origin, 'iNaturalist');
  });
}
