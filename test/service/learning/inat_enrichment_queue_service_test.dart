import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  late MockEnrichmentService mockEnrichmentService;
  late INatEnrichmentQueueService service;

  setUp(() {
    mockEnrichmentService = MockEnrichmentService();
    service = INatEnrichmentQueueService(mockEnrichmentService);

    when(
      mockEnrichmentService.downloadBaseImagesForDecks(
        any,
        onProgress: anyNamed('onProgress'),
      ),
    ).thenAnswer((invocation) async {
      final onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(int completed, int total)?;
      onProgress?.call(1, 1);
      return ImportEnrichmentSummary.empty;
    });
    when(
      mockEnrichmentService.fetchINatPhotosForDecks(
        any,
        onProgress: anyNamed('onProgress'),
        force: anyNamed('force'),
        primaryOnly: anyNamed('primaryOnly'),
        prioritizeSpeciesWithoutImages: anyNamed(
          'prioritizeSpeciesWithoutImages',
        ),
        maxConcurrent: anyNamed('maxConcurrent'),
        requestSpacing: anyNamed('requestSpacing'),
      ),
    ).thenAnswer((invocation) async {
      final onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(int completed, int total)?;
      onProgress?.call(1, 1);
      return ImportEnrichmentSummary.empty;
    });
    when(
      mockEnrichmentService.fetchINatCommonNamesForDecks(
        any,
        onProgress: anyNamed('onProgress'),
        force: anyNamed('force'),
        maxConcurrent: anyNamed('maxConcurrent'),
        requestSpacing: anyNamed('requestSpacing'),
      ),
    ).thenAnswer((invocation) async {
      final onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(int completed, int total)?;
      onProgress?.call(1, 1);
      return ImportEnrichmentSummary.empty;
    });
    when(
      mockEnrichmentService.backfillINatPhotosForDecks(
        any,
        onProgress: anyNamed('onProgress'),
        targetPhotoCount: anyNamed('targetPhotoCount'),
        maxConcurrent: anyNamed('maxConcurrent'),
        requestSpacing: anyNamed('requestSpacing'),
      ),
    ).thenAnswer((invocation) async {
      final onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(int completed, int total)?;
      onProgress?.call(1, 1);
      return ImportEnrichmentSummary.empty;
    });
  });

  test('runs full background enrichment in staged order', () async {
    await service.scheduleDeckEnrichment(['deck-1']);

    verifyInOrder([
      mockEnrichmentService.downloadBaseImagesForDecks([
        'deck-1',
      ], onProgress: anyNamed('onProgress')),
      mockEnrichmentService.fetchINatPhotosForDecks(
        ['deck-1'],
        onProgress: anyNamed('onProgress'),
        force: false,
        primaryOnly: true,
        prioritizeSpeciesWithoutImages: true,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
      ),
      mockEnrichmentService.fetchINatCommonNamesForDecks(
        ['deck-1'],
        onProgress: anyNamed('onProgress'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
      ),
      mockEnrichmentService.backfillINatPhotosForDecks(
        ['deck-1'],
        onProgress: anyNamed('onProgress'),
        targetPhotoCount: 10,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
      ),
    ]);
    expect(service.status, INatEnrichmentStatus.idle);
    expect(service.deckInfo('deck-1').isActive, isFalse);
    expect(service.deckInfo('deck-1').lastCompletedAt, isNotNull);
  });

  test('can schedule base-image-only enrichment', () async {
    await service.scheduleDeckEnrichment(
      ['deck-1'],
      includeINatPhotos: false,
      includeCommonNames: false,
    );

    verify(
      mockEnrichmentService.downloadBaseImagesForDecks([
        'deck-1',
      ], onProgress: anyNamed('onProgress')),
    ).called(1);
    verifyNever(
      mockEnrichmentService.fetchINatPhotosForDecks(
        any,
        onProgress: anyNamed('onProgress'),
        force: anyNamed('force'),
        primaryOnly: anyNamed('primaryOnly'),
        prioritizeSpeciesWithoutImages: anyNamed(
          'prioritizeSpeciesWithoutImages',
        ),
        maxConcurrent: anyNamed('maxConcurrent'),
        requestSpacing: anyNamed('requestSpacing'),
      ),
    );
    verifyNever(
      mockEnrichmentService.fetchINatCommonNamesForDecks(
        any,
        onProgress: anyNamed('onProgress'),
        force: anyNamed('force'),
        maxConcurrent: anyNamed('maxConcurrent'),
        requestSpacing: anyNamed('requestSpacing'),
      ),
    );
    expect(service.deckInfo('deck-1').lastCompletedAt, isNotNull);
  });
}
