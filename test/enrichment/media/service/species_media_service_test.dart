import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/media/service/local_species_image_service.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/media/service/species_photo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

/// Covers SpeciesMediaService.resolveAllFromCache — the path a review session
/// resolves its due cards through. The point of the tests below is the number
/// of round trips it makes: one species load, one photo-cache read and one
/// path resolution per storage directory, whatever the number of species.
/// Per-species resolution would put the time to the first card at the mercy
/// of how much is due, which is the budget #229 sets.

Species _species(String id, {List<Picture> pictures = const []}) => Species(
  id,
  id,
  'fishbase',
  'Scientific $id',
  const {},
  Classification(
    'Genus',
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
  pictures,
);

Picture _picture(String speciesId, String url, {String origin = 'fishbase'}) =>
    Picture(
      id: 'pic-$speciesId',
      species: speciesId,
      url: url,
      origin: origin,
      isUsable: 1,
    );

void main() {
  late MockSpeciesRepository speciesRepository;
  late MockINatPhotoCacheRepository photoCacheRepository;
  late MockImageService imageService;
  late SpeciesMediaService service;

  setUp(() {
    speciesRepository = MockSpeciesRepository();
    photoCacheRepository = MockINatPhotoCacheRepository();
    imageService = MockImageService();

    when(
      photoCacheRepository.getCachedPhotosForSpecies(any),
    ).thenAnswer((_) async => const {});
    when(
      imageService.resolveSavedUrlMap(
        any,
        storageDirectory: anyNamed('storageDirectory'),
        legacyDirectories: anyNamed('legacyDirectories'),
      ),
    ).thenAnswer(
      (invocation) async => {
        for (final url in invocation.positionalArguments.first as Set<String>)
          url: '/local/${url.split('/').last}',
      },
    );

    service = SpeciesMediaService(
      speciesRepository,
      SpeciesPhotoService(photoCacheRepository),
      LocalSpeciesImageService(imageService),
    );
  });

  /// Stubs [count] species, each with one reference picture of its own.
  Set<String> givenSpecies(int count) {
    final species = {
      for (var i = 0; i < count; i++)
        _species('sp$i', pictures: [_picture('sp$i', 'https://host/sp$i.jpg')]),
    };
    final ids = species.map((entry) => entry.id).toSet();
    when(speciesRepository.getSpecies(ids)).thenAnswer((_) async => species);
    return ids;
  }

  /// How often the collaborators were asked for anything at all.
  int roundTrips() =>
      verify(speciesRepository.getSpecies(any)).callCount +
      verify(photoCacheRepository.getCachedPhotosForSpecies(any)).callCount +
      verify(
        imageService.resolveSavedUrlMap(
          any,
          storageDirectory: anyNamed('storageDirectory'),
          legacyDirectories: anyNamed('legacyDirectories'),
        ),
      ).callCount;

  test('resolves one species through the batched species load', () async {
    await service.resolveAllFromCache(givenSpecies(1));

    verifyNever(speciesRepository.getSpeciesById(any));
    expect(roundTrips(), 4);
  });

  test('resolves 25 species with the same number of round trips', () async {
    await service.resolveAllFromCache(givenSpecies(25));

    verifyNever(speciesRepository.getSpeciesById(any));
    // One species load, one photo-cache read, one path resolution per storage
    // directory — the same four as for a single species.
    expect(roundTrips(), 4);
  });

  test('gives every species its own resolved pictures', () async {
    final cards = await service.resolveAllFromCache(givenSpecies(2));

    expect(
      {
        for (final card in cards)
          card.species.id: card.localPictures.single.localPath,
      },
      {'sp0': '/local/sp0.jpg', 'sp1': '/local/sp1.jpg'},
    );
  });

  test('appends the cached iNat photos of each species', () async {
    final ids = givenSpecies(2);
    when(photoCacheRepository.getCachedPhotosForSpecies(ids)).thenAnswer(
      (_) async => {
        'sp1': [
          _picture('sp1', 'https://inat/extra.jpg', origin: 'iNaturalist'),
        ],
      },
    );

    final cards = await service.resolveAllFromCache(ids);

    expect(
      {
        for (final card in cards) card.species.id: card.localPictures.length,
      },
      {'sp0': 1, 'sp1': 2},
    );
  });

  test('skips both lookups when asked for nothing', () async {
    expect(await service.resolveAllFromCache({}), isEmpty);

    verifyZeroInteractions(speciesRepository);
    verifyZeroInteractions(photoCacheRepository);
  });
}
