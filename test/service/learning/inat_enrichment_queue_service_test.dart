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
    service = INatEnrichmentQueueService(
      mockEnrichmentService,
      resolveSpeciesIds: (_) async => {'sp1'},
    );

    when(
      mockEnrichmentService.downloadBaseImagesForSpecies(
        {'sp1'},
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
      mockEnrichmentService.fetchINatPhotosForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        force: false,
        primaryOnly: true,
        prioritizeSpeciesWithoutImages: true,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
      ),
    ).thenAnswer((invocation) async {
      final onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(int completed, int total)?;
      onProgress?.call(1, 1);
      return ImportEnrichmentSummary.empty;
    });
    when(
      mockEnrichmentService.fetchINatCommonNamesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
      ),
    ).thenAnswer((invocation) async {
      final onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(int completed, int total)?;
      onProgress?.call(1, 1);
      return ImportEnrichmentSummary.empty;
    });
    when(
      mockEnrichmentService.backfillINatPhotosForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        targetPhotoCount: 10,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
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
      mockEnrichmentService.downloadBaseImagesForSpecies({
        'sp1',
      }, onProgress: anyNamed('onProgress')),
      mockEnrichmentService.fetchINatPhotosForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        force: false,
        primaryOnly: true,
        prioritizeSpeciesWithoutImages: true,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
      ),
      mockEnrichmentService.fetchINatCommonNamesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
      ),
      mockEnrichmentService.backfillINatPhotosForSpecies(
        {'sp1'},
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
      mockEnrichmentService.downloadBaseImagesForSpecies({
        'sp1',
      }, onProgress: anyNamed('onProgress')),
    ).called(1);
    verifyNever(
      mockEnrichmentService.fetchINatPhotosForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        force: false,
        primaryOnly: true,
        prioritizeSpeciesWithoutImages: true,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
      ),
    );
    verifyNever(
      mockEnrichmentService.fetchINatCommonNamesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
      ),
    );
    expect(service.deckInfo('deck-1').lastCompletedAt, isNotNull);
  });
}
