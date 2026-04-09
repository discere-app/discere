import 'package:discere/service/learning/decks_service.dart';
import 'package:discere/service/learning/inat_enrichment_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  late MockDecksService mockDecksService;
  late INatEnrichmentQueueService service;

  setUp(() {
    mockDecksService = MockDecksService();
    service = INatEnrichmentQueueService(mockDecksService);

    when(
      mockDecksService.downloadBaseImagesForDecks(
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
      mockDecksService.fetchINatPhotosForDecks(
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
      mockDecksService.fetchINatCommonNamesForDecks(
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
      mockDecksService.backfillINatPhotosForDecks(
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
      mockDecksService.downloadBaseImagesForDecks([
        'deck-1',
      ], onProgress: anyNamed('onProgress')),
      mockDecksService.fetchINatPhotosForDecks(
        ['deck-1'],
        onProgress: anyNamed('onProgress'),
        force: false,
        primaryOnly: true,
        prioritizeSpeciesWithoutImages: true,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
      ),
      mockDecksService.fetchINatCommonNamesForDecks(
        ['deck-1'],
        onProgress: anyNamed('onProgress'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
      ),
      mockDecksService.backfillINatPhotosForDecks(
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
      mockDecksService.downloadBaseImagesForDecks([
        'deck-1',
      ], onProgress: anyNamed('onProgress')),
    ).called(1);
    verifyNever(
      mockDecksService.fetchINatPhotosForDecks(
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
      mockDecksService.fetchINatCommonNamesForDecks(
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
