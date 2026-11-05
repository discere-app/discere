import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/pipeline/model/base_image_download_result.dart';
import 'package:discere/enrichment/pipeline/model/base_image_fallback_reason.dart';
import 'package:discere/enrichment/pipeline/service/base_image_enrichment_service.dart';
import 'package:discere/shared/service/image_download_outcome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockImageService mockImageService;
  late BaseImageEnrichmentService service;

  setUp(() {
    mockImageService = MockImageService();
    service = BaseImageEnrichmentService(mockImageService);
  });

  Species referenceSpecies(List<String> urls) => Species(
    'sp1',
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
      for (final url in urls)
        Picture(
          id: url,
          species: 'sp1',
          url: url,
          origin: 'reference',
          isUsable: 1,
        ),
    ],
  );

  /// Downloads a species with one picture per entry of [outcomes], each URL
  /// ending as its entry says.
  Future<BaseImageDownloadResult> downloadEnding(
    Map<String, ImageDownloadOutcome> outcomes,
  ) {
    when(
      mockImageService.downloadAndSaveUrls(
        outcomes.keys.toSet(),
        storageDirectory: 'reference_images',
        skipIfHostCoolingDown: true,
      ),
    ).thenAnswer((_) async => outcomes);
    return service.downloadReferenceImages(
      referenceSpecies(outcomes.keys.toList()),
    );
  }

  test('one saved image is enough, whatever happened to the others', () async {
    final result = await downloadEnding({
      'https://a.org/1.jpg': const ImageSaved('/local/1.jpg'),
      'https://b.org/2.jpg': const ImageHostUnreachable('b.org'),
    });

    expect(result, isA<BaseImageSaved>());
  });

  test('a host problem outweighs a missing image', () async {
    final result = await downloadEnding({
      'https://a.org/1.jpg': const ImageNotFound('a.org', 404),
      'https://b.org/2.jpg': const ImageHostUnreachable('b.org'),
    });

    expect(
      result,
      isA<BaseImageFailed>()
          .having(
            (r) => r.reason,
            'reason',
            BaseImageFallbackReason.hostUnavailable,
          )
          .having((r) => r.host, 'host', 'b.org'),
    );
  });

  test('refusals alone make the host blocked', () async {
    final result = await downloadEnding({
      'https://a.org/1.jpg': const ImageHostRefused('a.org'),
      'https://a.org/2.jpg': const ImageHostRefused('a.org'),
    });

    expect(
      result,
      isA<BaseImageFailed>()
          .having(
            (r) => r.reason,
            'reason',
            BaseImageFallbackReason.hostBlocked,
          )
          .having((r) => r.host, 'host', 'a.org'),
    );
  });

  test('a refusal beside an unreachable host is no block', () async {
    final result = await downloadEnding({
      'https://a.org/1.jpg': const ImageHostRefused('a.org'),
      'https://b.org/2.jpg': const ImageHostUnreachable('b.org'),
    });

    expect(
      result,
      isA<BaseImageFailed>().having(
        (r) => r.reason,
        'reason',
        BaseImageFallbackReason.hostUnavailable,
      ),
    );
  });

  test('a local failure is retried as other, not taken for a missing '
      'image', () async {
    final result = await downloadEnding({
      'https://a.org/1.jpg': const ImageNotFound('a.org', 404),
      'https://a.org/2.jpg': const ImageLocalFailure(),
    });

    expect(
      result,
      isA<BaseImageFailed>()
          .having((r) => r.reason, 'reason', BaseImageFallbackReason.other)
          .having((r) => r.host, 'host', isNull),
    );
  });

  test('only every image missing makes the species image-missing', () async {
    final result = await downloadEnding({
      'https://a.org/1.jpg': const ImageNotFound('a.org', 404),
      'https://a.org/2.jpg': const ImageNotFound('a.org', 410),
    });

    expect(
      result,
      isA<BaseImageFailed>()
          .having(
            (r) => r.reason,
            'reason',
            BaseImageFallbackReason.imageMissing,
          )
          .having((r) => r.host, 'host', 'a.org'),
    );
  });
}
