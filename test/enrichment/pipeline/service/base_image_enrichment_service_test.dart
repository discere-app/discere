import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/pipeline/service/base_image_enrichment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockSpeciesRepository mockSpeciesRepo;
  late MockImageService mockImageService;
  late BaseImageEnrichmentService service;

  setUp(() {
    mockSpeciesRepo = MockSpeciesRepository();
    mockImageService = MockImageService();

    when(
      mockImageService.downloadAndSaveUrlMap(
        any,
        storageDirectory: anyNamed('storageDirectory'),
        maxConcurrent: anyNamed('maxConcurrent'),
        onProgress: anyNamed('onProgress'),
      ),
    ).thenAnswer((_) async => <String, String>{});

    service = BaseImageEnrichmentService(mockSpeciesRepo, mockImageService);
  });

  Species referenceSpecies(String id, String url) => Species(
    id,
    '1',
    'fishbase',
    'speciosa',
    const {},
    Classification(
      'Testus',
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
    [
      Picture(
        id: '$id-pic',
        species: id,
        url: url,
        origin: 'reference',
        isUsable: 1,
      ),
    ],
  );

  test('reports the species in the summary once its reference image is '
      'actually saved locally', () async {
    final species = referenceSpecies('sp1', 'https://example.org/ref.jpg');
    when(
      mockSpeciesRepo.getSpecies({'sp1'}),
    ).thenAnswer((_) async => {species});
    when(
      mockImageService.downloadAndSaveUrlMap(
        {'https://example.org/ref.jpg'},
        storageDirectory: 'reference_images',
        maxConcurrent: anyNamed('maxConcurrent'),
        onProgress: anyNamed('onProgress'),
      ),
    ).thenAnswer(
      (_) async => {'https://example.org/ref.jpg': '/local/ref.jpg'},
    );

    final summary = await service.downloadBaseImagesForSpecies({'sp1'});

    expect(summary.imageSpeciesCount, 1);
    expect(summary.imageCount, 1);
  });

  test('reports no image in the summary when the reference image download '
      'silently fails, so BaseWorker leaves the species pending for retry '
      'instead of completing it without a local file', () async {
    final species = referenceSpecies('sp1', 'https://example.org/ref.jpg');
    when(
      mockSpeciesRepo.getSpecies({'sp1'}),
    ).thenAnswer((_) async => {species});
    // Default stub from setUp already returns an empty map here,
    // simulating a per-URL download failure that ImageService swallows
    // internally instead of throwing.

    final summary = await service.downloadBaseImagesForSpecies({'sp1'});

    expect(summary.imageSpeciesCount, 0);
    expect(summary.imageCount, 0);
  });
}
