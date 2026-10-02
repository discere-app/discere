import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/media/service/local_species_image_service.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/media/service/species_photo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

/// Covers the two bulk entry points of SpeciesMediaService —
/// resolveAllFromCache (a review session's due cards, and a list's first
/// render) and resolveAllWithDownload (the same set with missing images
/// fetched). The point of the tests below is the number of round trips they
/// make: one species load, one photo-cache read and one path resolution per
/// storage directory, whatever the number of species. Per-species resolution
/// would put the time to the first card, and the time to a rendered
/// watchlist, at the mercy of how many entries there are, which is the budget
/// #229 sets.
///
/// Both share one implementation, so both return the same species in the same
/// order and differ only in whether missing images get downloaded. A caller
/// can therefore render the cached pass and adopt the downloaded one later
/// without the list resorting under the user.
///
/// resolveSpeciesFromCache is the cached pass for a caller that already holds
/// its species — a deck's edit page lists what it loaded for the draft. It
/// shares everything with the passes above except the species load, which it
/// must not repeat.
///
/// findSpeciesWithoutLocalImage, the photo-gap check's cheap first phase, never
/// enters that species load at all: deciding whether a picture exists on disk
/// does not need taxonomy, common names or traits.

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

  group('resolveAllFromCache', () {
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
        {for (final card in cards) card.species.id: card.localPictures.length},
        {'sp0': 1, 'sp1': 2},
      );
    });

    test('skips both lookups when asked for nothing', () async {
      expect(await service.resolveAllFromCache({}), isEmpty);

      verifyZeroInteractions(speciesRepository);
      verifyZeroInteractions(photoCacheRepository);
    });
  });

  group('resolveAllWithDownload', () {
    setUp(() {
      when(
        imageService.downloadAndSaveUrlMap(
          any,
          storageDirectory: anyNamed('storageDirectory'),
          maxConcurrent: anyNamed('maxConcurrent'),
          skipIfHostCoolingDown: anyNamed('skipIfHostCoolingDown'),
          onProgress: anyNamed('onProgress'),
        ),
      ).thenAnswer(
        (invocation) async => {
          for (final url in invocation.positionalArguments.first as Set<String>)
            url: '/local/${url.split('/').last}',
        },
      );
    });

    /// How often the two databases were asked for anything at all.
    int databaseRoundTrips() =>
        verify(speciesRepository.getSpecies(any)).callCount +
        verify(photoCacheRepository.getCachedPhotosForSpecies(any)).callCount;

    test('resolves one species through the batched species load', () async {
      await service.resolveAllWithDownload(givenSpecies(1));

      verifyNever(speciesRepository.getSpeciesById(any));
      expect(databaseRoundTrips(), 2);
    });

    test('resolves 25 species with the same database round trips', () async {
      await service.resolveAllWithDownload(givenSpecies(25));

      verifyNever(speciesRepository.getSpeciesById(any));
      // One species load, one photo-cache read — the same two as for a single
      // species, instead of six queries per species.
      expect(databaseRoundTrips(), 2);
    });

    test('downloads every external picture in one serial pass', () async {
      final species = {
        for (final id in ['sp0', 'sp1'])
          _species(
            id,
            pictures: [
              _picture(id, 'https://inat/$id.jpg', origin: 'iNaturalist'),
            ],
          ),
      };
      final ids = species.map((entry) => entry.id).toSet();
      when(speciesRepository.getSpecies(ids)).thenAnswer((_) async => species);

      await service.resolveAllWithDownload(ids);

      // One download call for the whole set, serial — the iNaturalist rate
      // limit the storage split exists for. Nothing waits on this call, so
      // serialising it costs no screen time.
      final urlSets = verify(
        imageService.downloadAndSaveUrlMap(
          captureAny,
          storageDirectory: 'external_images',
          maxConcurrent: 1,
        ),
      ).captured;
      expect(urlSets, [
        {'https://inat/sp0.jpg', 'https://inat/sp1.jpg'},
      ]);
    });

    test('skips both lookups when asked for nothing', () async {
      expect(await service.resolveAllWithDownload({}), isEmpty);

      verifyZeroInteractions(speciesRepository);
      verifyZeroInteractions(photoCacheRepository);
    });
  });

  group('resolveSpeciesFromCache', () {
    /// [count] species as a caller holds them after its own species load: one
    /// reference picture each, in the order sp0, sp1, ...
    List<Species> loadedSpecies(int count) => [
      for (var i = 0; i < count; i++)
        _species('sp$i', pictures: [_picture('sp$i', 'https://host/sp$i.jpg')]),
    ];

    test('never loads the species it was handed', () async {
      await service.resolveSpeciesFromCache(loadedSpecies(3));

      verifyZeroInteractions(speciesRepository);
    });

    test('resolves 25 species with one photo-cache read', () async {
      await service.resolveSpeciesFromCache(loadedSpecies(25));

      // One cache read and one path resolution per storage directory, whatever
      // the size of the list.
      verify(photoCacheRepository.getCachedPhotosForSpecies(any)).called(1);
      verify(
        imageService.resolveSavedUrlMap(
          any,
          storageDirectory: anyNamed('storageDirectory'),
          legacyDirectories: anyNamed('legacyDirectories'),
        ),
      ).called(2);
    });

    test('answers in the order the species were handed over', () async {
      final species = loadedSpecies(3).reversed.toList();

      final resolved = await service.resolveSpeciesFromCache(species);

      expect(resolved.map((entry) => entry.species.id), ['sp2', 'sp1', 'sp0']);
      expect(resolved.map((entry) => entry.localPictures.single.localPath), [
        '/local/sp2.jpg',
        '/local/sp1.jpg',
        '/local/sp0.jpg',
      ]);
    });

    test(
      'gives a species without a reference picture its cached iNat photo',
      () async {
        // What a list that only looks at Species.pictures cannot show: the
        // species carries no picture of its own, the cache holds one.
        when(
          photoCacheRepository.getCachedPhotosForSpecies({'sp0'}),
        ).thenAnswer(
          (_) async => {
            'sp0': [
              _picture('sp0', 'https://inat/sp0.jpg', origin: 'iNaturalist'),
            ],
          },
        );

        final resolved = await service.resolveSpeciesFromCache([
          _species('sp0'),
        ]);

        final entry = resolved.single;
        expect(entry.localPictures.single.localPath, '/local/sp0.jpg');
        expect(entry.species.pictures.single.url, 'https://inat/sp0.jpg');
      },
    );

    test('downloads nothing', () async {
      await service.resolveSpeciesFromCache(loadedSpecies(2));

      verifyNever(
        imageService.downloadAndSaveUrlMap(
          any,
          storageDirectory: anyNamed('storageDirectory'),
          maxConcurrent: anyNamed('maxConcurrent'),
          skipIfHostCoolingDown: anyNamed('skipIfHostCoolingDown'),
          onProgress: anyNamed('onProgress'),
        ),
      );
    });

    test('asks nothing when given no species', () async {
      expect(await service.resolveSpeciesFromCache(const []), isEmpty);

      verifyZeroInteractions(speciesRepository);
      verifyZeroInteractions(photoCacheRepository);
      verifyZeroInteractions(imageService);
    });
  });

  group('findSpeciesWithoutLocalImage', () {
    /// Stubs [count] species with one reference picture each, and lets only
    /// the pictures in [storedLocally] resolve to a file on disk.
    Set<String> givenPictures(int count, {required Set<String> storedLocally}) {
      final ids = {for (var i = 0; i < count; i++) 'sp$i'};
      when(speciesRepository.getPicturesBySpeciesId(ids)).thenAnswer(
        (_) async => {
          for (final id in ids)
            id: [_picture(id, 'https://host/$id.jpg')],
        },
      );
      when(
        imageService.resolveSavedUrlMap(
          any,
          storageDirectory: anyNamed('storageDirectory'),
          legacyDirectories: anyNamed('legacyDirectories'),
        ),
      ).thenAnswer(
        (invocation) async => {
          for (final url in invocation.positionalArguments.first as Set<String>)
            if (storedLocally.any((id) => url.endsWith('/$id.jpg')))
              url: '/local/${url.split('/').last}',
        },
      );
      return ids;
    }

    test('reports nothing when every species has a stored picture', () async {
      final ids = givenPictures(3, storedLocally: {'sp0', 'sp1', 'sp2'});

      expect(await service.findSpeciesWithoutLocalImage(ids), isEmpty);
    });

    test('reports every species when none has a stored picture', () async {
      final ids = givenPictures(3, storedLocally: const {});

      expect(await service.findSpeciesWithoutLocalImage(ids), ids);
    });

    test('reports only the species without a stored picture', () async {
      final ids = givenPictures(3, storedLocally: {'sp1'});

      expect(await service.findSpeciesWithoutLocalImage(ids), {'sp0', 'sp2'});
    });

    test('reports a species that has no candidate picture at all', () async {
      when(
        speciesRepository.getPicturesBySpeciesId({'sp0'}),
      ).thenAnswer((_) async => const {'sp0': []});

      expect(await service.findSpeciesWithoutLocalImage({'sp0'}), {'sp0'});
    });

    test('counts a cached iNat photo as a stored picture', () async {
      when(
        speciesRepository.getPicturesBySpeciesId({'sp0'}),
      ).thenAnswer((_) async => const {'sp0': []});
      when(photoCacheRepository.getCachedPhotosForSpecies({'sp0'})).thenAnswer(
        (_) async => {
          'sp0': [_picture('sp0', 'https://inat/sp0.jpg', origin: 'iNaturalist')],
        },
      );

      expect(await service.findSpeciesWithoutLocalImage({'sp0'}), isEmpty);
    });

    test('never loads the full species, however many are checked', () async {
      for (final count in [1, 200]) {
        await service.findSpeciesWithoutLocalImage(
          givenPictures(count, storedLocally: const {}),
        );
      }

      // The point of the cheap phase: no taxonomy joins, no common names, no
      // traits — just the candidate URLs and one path resolution per storage
      // directory, whatever the deck's size.
      verifyNever(speciesRepository.getSpecies(any));
      verifyNever(speciesRepository.getSpeciesById(any));
      expect(
        verify(speciesRepository.getPicturesBySpeciesId(any)).callCount +
            verify(
              photoCacheRepository.getCachedPhotosForSpecies(any),
            ).callCount +
            verify(
              imageService.resolveSavedUrlMap(
                any,
                storageDirectory: anyNamed('storageDirectory'),
                legacyDirectories: anyNamed('legacyDirectories'),
              ),
            ).callCount,
        // Two checks x (one picture query, one cache read, two path
        // resolutions).
        8,
      );
    });

    test('asks nothing when given no species', () async {
      expect(await service.findSpeciesWithoutLocalImage({}), isEmpty);

      verifyZeroInteractions(speciesRepository);
      verifyZeroInteractions(photoCacheRepository);
      verifyZeroInteractions(imageService);
    });
  });

  test('both passes return the same species in the same order', () async {
    // What a two-phase list load rests on: the cached pass and the downloaded
    // pass agree on the list, so adopting the second one only fills in images
    // instead of resorting the list the user is already looking at. The species
    // load answers in taxonomic order, which is not the order asked for.
    final requested = {'sp2', 'sp0', 'sp1'};
    when(speciesRepository.getSpecies(requested)).thenAnswer(
      (_) async => {
        for (final id in ['sp0', 'sp1', 'sp2'])
          _species(id, pictures: [_picture(id, 'https://host/$id.jpg')]),
      },
    );
    when(
      imageService.resolveSavedUrlMap(
        any,
        storageDirectory: anyNamed('storageDirectory'),
        legacyDirectories: anyNamed('legacyDirectories'),
      ),
    ).thenAnswer((_) async => const {});
    when(
      imageService.downloadAndSaveUrlMap(
        any,
        storageDirectory: anyNamed('storageDirectory'),
        maxConcurrent: anyNamed('maxConcurrent'),
        skipIfHostCoolingDown: anyNamed('skipIfHostCoolingDown'),
        onProgress: anyNamed('onProgress'),
      ),
    ).thenAnswer(
      (invocation) async => {
        for (final url in invocation.positionalArguments.first as Set<String>)
          url: '/local/${url.split('/').last}',
      },
    );

    final cached = await service.resolveAllFromCache(requested);
    final downloaded = await service.resolveAllWithDownload(requested);

    expect(cached.map((card) => card.species.id), ['sp2', 'sp0', 'sp1']);
    expect(
      downloaded.map((card) => card.species.id),
      cached.map((card) => card.species.id),
    );
    // Same list, only the images differ.
    expect(cached.every((card) => card.localPictures.isEmpty), isTrue);
    expect(downloaded.every((card) => card.localPictures.isNotEmpty), isTrue);
  });
}
