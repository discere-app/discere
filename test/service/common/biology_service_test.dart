import 'package:discere/model/biology/classification.dart';
import 'package:discere/model/biology/species.dart';
import 'package:discere/model/biology/species_with_local_images.dart';
import 'package:discere/model/language.dart';
import 'package:discere/service/common/biology_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

Species makeSpecies({
  String id = 'sp1',
  String scientificName = 'carcharias',
  List<String> images = const ['http://example.com/img1.jpg'],
}) {
  return Species(
    id,
    'ext1',
    'fishbase',
    scientificName,
    {Language.de: 'Weißer Hai', Language.en: 'Great white shark'},
    Classification(
      'Carcharodon',
      {Language.de: 'Weiße Haie'},
      null,
      'Lamnidae',
      {Language.de: 'Makrelenhaie', Language.en: 'Mackerel sharks'},
      'Lamniformes',
      {Language.de: 'Makrelenhaiartige', Language.en: 'Mackerel sharks'},
      'Chondrichthyes',
      {Language.de: 'Knorpelfische'},
      null,
    ),
    images,
  );
}

void main() {
  late MockSpeciesRepository mockSpeciesRepo;
  late MockImageService mockImageService;
  late BiologyService service;

  setUp(() {
    mockSpeciesRepo = MockSpeciesRepository();
    mockImageService = MockImageService();
    when(mockImageService.downloadAndSaveImages(any))
        .thenAnswer((_) async => ['/local/img1.jpg']);
    service = BiologyService(mockSpeciesRepo, mockImageService);
  });

  group('BiologyService.getSpeciesById', () {
    test('delegates to SpeciesRepository.getSpeciesById', () async {
      final species = makeSpecies();
      when(mockSpeciesRepo.getSpeciesById('sp1'))
          .thenAnswer((_) async => species);

      final result = await service.getSpeciesById('sp1');

      verify(mockSpeciesRepo.getSpeciesById('sp1')).called(1);
      expect(result, species);
    });

    test('returns null when the repository returns null', () async {
      when(mockSpeciesRepo.getSpeciesById('unknown'))
          .thenAnswer((_) async => null);

      final result = await service.getSpeciesById('unknown');

      expect(result, isNull);
    });
  });

  group('BiologyService.getSpeciesWithLocalImagesById', () {
    test('returns null when the species is not found', () async {
      when(mockSpeciesRepo.getSpeciesById(any)).thenAnswer((_) async => null);

      final result =
          await service.getSpeciesWithLocalImagesById('nonexistent');

      expect(result, isNull);
      verifyNever(mockImageService.downloadAndSaveImages(any));
    });

    test('calls ImageService.downloadAndSaveImages with species image URLs',
        () async {
      final species =
          makeSpecies(images: ['http://example.com/a.jpg', 'http://example.com/b.jpg']);
      when(mockSpeciesRepo.getSpeciesById('sp1'))
          .thenAnswer((_) async => species);

      await service.getSpeciesWithLocalImagesById('sp1');

      verify(mockImageService.downloadAndSaveImages(
        {'http://example.com/a.jpg', 'http://example.com/b.jpg'},
      )).called(1);
    });

    test('returns SpeciesWithLocalImages with correct species data', () async {
      final species = makeSpecies();
      when(mockSpeciesRepo.getSpeciesById('sp1'))
          .thenAnswer((_) async => species);

      final result = await service.getSpeciesWithLocalImagesById('sp1');

      expect(result, isA<SpeciesWithLocalImages>());
      expect(result!.species, species);
    });

    test('returns SpeciesWithLocalImages with local paths from ImageService',
        () async {
      final species = makeSpecies();
      when(mockSpeciesRepo.getSpeciesById('sp1'))
          .thenAnswer((_) async => species);
      when(mockImageService.downloadAndSaveImages(any))
          .thenAnswer((_) async => ['/local/path/img.jpg']);

      final result = await service.getSpeciesWithLocalImagesById('sp1');

      expect(result!.localImages, ['/local/path/img.jpg']);
    });

    test('returns SpeciesWithLocalImages with empty paths when no images exist',
        () async {
      final species = makeSpecies(images: []);
      when(mockSpeciesRepo.getSpeciesById('sp1'))
          .thenAnswer((_) async => species);
      when(mockImageService.downloadAndSaveImages(any))
          .thenAnswer((_) async => []);

      final result = await service.getSpeciesWithLocalImagesById('sp1');

      expect(result!.localImages, isEmpty);
    });
  });
}
