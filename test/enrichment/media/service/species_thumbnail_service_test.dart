import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/media/service/species_thumbnail_service.dart';
import 'package:discere/external/inaturalist/inat_taxon_id_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

const _speciesId = 'discere:species:1';

final _species = Species(
  _speciesId,
  _speciesId,
  'sealifebase',
  'pusilla',
  const {},
  Classification(
    'Triphora',
    const {},
    null,
    null,
    const {},
    null,
    const {},
    null,
    const {},
    null,
  ),
  const [],
);

Picture _cachedPhoto(String url) => Picture(
  id: 'inat_${_speciesId}_${url.hashCode}',
  species: _speciesId,
  url: url,
  origin: 'iNaturalist',
  isUsable: 1,
);

void main() {
  late MockSpeciesPhotoService speciesPhotoService;
  late MockINatTaxonResolver taxonResolver;
  late MockSpeciesRepository speciesRepository;
  late MockINatPhotoApi iNatPhotos;
  late SpeciesThumbnailService service;

  void givenCache(Map<String, List<Picture>> cached) {
    when(
      speciesPhotoService.getCachedPhotosBySpeciesId({_speciesId}),
    ).thenAnswer((_) async => cached);
  }

  void verifyNoLookupBeyondCache() {
    verifyZeroInteractions(taxonResolver);
    verifyZeroInteractions(speciesRepository);
    verifyZeroInteractions(iNatPhotos);
  }

  void verifyNothingPersisted() {
    verifyNever(
      taxonResolver.persistResolvedTaxonId(
        any,
        previousTaxonId: anyNamed('previousTaxonId'),
        resolvedTaxonId: anyNamed('resolvedTaxonId'),
      ),
    );
  }

  setUp(() {
    speciesPhotoService = MockSpeciesPhotoService();
    taxonResolver = MockINatTaxonResolver();
    speciesRepository = MockSpeciesRepository();
    iNatPhotos = MockINatPhotoApi();
    service = SpeciesThumbnailService(
      speciesPhotoService: speciesPhotoService,
      taxonResolver: taxonResolver,
      speciesRepository: speciesRepository,
      iNatPhotos: iNatPhotos,
    );

    givenCache(const {});
    when(taxonResolver.knownTaxonId(_speciesId)).thenAnswer((_) async => null);
    when(
      speciesRepository.getSpeciesById(_speciesId),
    ).thenAnswer((_) async => _species);
    when(iNatPhotos.fetchThumbnailUrl(any)).thenAnswer(
      (invocation) async =>
          'https://inat/${invocation.positionalArguments.single}/medium.jpg',
    );
  });

  group('from the photo cache', () {
    test('answers with the first cached photo and asks nothing else', () async {
      givenCache({
        _speciesId: [
          _cachedPhoto('https://inat/cached-1/medium.jpg'),
          _cachedPhoto('https://inat/cached-2/medium.jpg'),
        ],
      });

      expect(
        await service.thumbnailUrl(_speciesId),
        'https://inat/cached-1/medium.jpg',
      );
      verifyNoLookupBeyondCache();
    });

    test(
      'an entry without photos settles it: no thumbnail, no request',
      () async {
        givenCache({_speciesId: const []});

        expect(await service.thumbnailUrl(_speciesId), isNull);
        verifyNoLookupBeyondCache();
      },
    );
  });

  test(
    'fetches by the taxon id on record without loading the species',
    () async {
      when(taxonResolver.knownTaxonId(_speciesId)).thenAnswer((_) async => 47);

      expect(
        await service.thumbnailUrl(_speciesId),
        'https://inat/47/medium.jpg',
      );
      verify(iNatPhotos.fetchThumbnailUrl(47)).called(1);
      verifyZeroInteractions(speciesRepository);
      verifyNever(taxonResolver.searchTaxonId(any));
      verifyNothingPersisted();
    },
  );

  group('without an id on record', () {
    test('fetches by the id the search found and keeps that id', () async {
      when(taxonResolver.searchTaxonId(_species)).thenAnswer((_) async => 707);

      expect(
        await service.thumbnailUrl(_speciesId),
        'https://inat/707/medium.jpg',
      );
      verify(iNatPhotos.fetchThumbnailUrl(707)).called(1);
      verify(
        taxonResolver.persistResolvedTaxonId(
          _species,
          previousTaxonId: null,
          resolvedTaxonId: 707,
        ),
      ).called(1);
    });

    test('shows nothing when the search settles there is no fitting taxon '
        '(a homonym of another phylum, a rejected id)', () async {
      when(taxonResolver.searchTaxonId(_species)).thenAnswer(
        (_) => Future.error(const TaxonNotFoundException('Triphora pusilla')),
      );

      expect(await service.thumbnailUrl(_speciesId), isNull);
      verifyNever(iNatPhotos.fetchThumbnailUrl(any));
      verifyNothingPersisted();
    });

    test(
      'shows nothing when the search failed and is worth retrying',
      () async {
        when(
          taxonResolver.searchTaxonId(_species),
        ).thenAnswer((_) async => null);

        expect(await service.thumbnailUrl(_speciesId), isNull);
        verifyNever(iNatPhotos.fetchThumbnailUrl(any));
        verifyNothingPersisted();
      },
    );

    test('shows nothing for a species the catalog does not know', () async {
      when(
        speciesRepository.getSpeciesById(_speciesId),
      ).thenAnswer((_) async => null);

      expect(await service.thumbnailUrl(_speciesId), isNull);
      verifyNever(taxonResolver.searchTaxonId(any));
      verifyNever(iNatPhotos.fetchThumbnailUrl(any));
    });
  });

  test(
    'an unexpected failure ends in no thumbnail rather than an error',
    () async {
      when(
        taxonResolver.knownTaxonId(_speciesId),
      ).thenAnswer((_) => Future.error(StateError('database closed')));

      expect(await service.thumbnailUrl(_speciesId), isNull);
      verifyNever(iNatPhotos.fetchThumbnailUrl(any));
    },
  );
}
