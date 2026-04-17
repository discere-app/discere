import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

void main() {
  late MockEnrichmentService mockEnrichmentService;
  late MockImageService mockImageService;
  late INatEnrichmentQueueService service;

  setUp(() {
    mockEnrichmentService = MockEnrichmentService();
    mockImageService = MockImageService();
    service = INatEnrichmentQueueService(
      mockEnrichmentService,
      resolveSpeciesIds: (_) async => {'sp1'},
      updateCoverPath: (_, __) async {},
      imageService: mockImageService,
    );

    when(
      mockEnrichmentService.downloadBaseImagesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        isCancelled: anyNamed('isCancelled'),
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
        isCancelled: anyNamed('isCancelled'),
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
        isCancelled: anyNamed('isCancelled'),
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
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      final onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(int completed, int total)?;
      onProgress?.call(1, 1);
      return ImportEnrichmentSummary.empty;
    });
  });

  test('runs full background enrichment for a deck', () async {
    await service.scheduleDeckEnrichment(['deck-1']);

    verify(
      mockEnrichmentService.downloadBaseImagesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).called(1);
    verify(
      mockEnrichmentService.fetchINatPhotosForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        force: false,
        primaryOnly: true,
        prioritizeSpeciesWithoutImages: true,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).called(1);
    verify(
      mockEnrichmentService.fetchINatCommonNamesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).called(1);
    verify(
      mockEnrichmentService.backfillINatPhotosForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        targetPhotoCount: 10,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).called(1);
    expect(service.status, INatEnrichmentStatus.idle);
    expect(service.deckInfo('deck-1').isActive, isFalse);
    expect(service.deckInfo('deck-1').lastAttemptedAt, isNotNull);
    expect(service.deckInfo('deck-1').lastCompletedAt, isNotNull);
    expect(service.deckInfo('deck-1').hasFailedAttempt, isFalse);
  });

  test('can schedule base-image-only enrichment', () async {
    await service.scheduleDeckEnrichment(
      ['deck-1'],
      includeINatPhotos: false,
      includeCommonNames: false,
    );

    verify(
      mockEnrichmentService.downloadBaseImagesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        isCancelled: anyNamed('isCancelled'),
      ),
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
        isCancelled: anyNamed('isCancelled'),
      ),
    );
    verifyNever(
      mockEnrichmentService.fetchINatCommonNamesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    );
    expect(service.deckInfo('deck-1').lastAttemptedAt, isNotNull);
    expect(service.deckInfo('deck-1').lastCompletedAt, isNotNull);
  });

  test('marks failed runs as attempted but not completed', () async {
    when(
      mockEnrichmentService.fetchINatCommonNamesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenThrow(Exception('boom'));

    await service.scheduleDeckEnrichment(['deck-1']);

    final info = service.deckInfo('deck-1');
    expect(info.lastAttemptedAt, isNotNull);
    expect(info.lastCompletedAt, isNull);
    expect(info.hasFailedAttempt, isTrue);
  });

  test(
    'ignores non-integer preference keys during timestamp restore',
    () async {
      SharedPreferences.setMockInitialValues({
        'has_seen_welcome_dialog': true,
        'inat_enrichment_completed_at.deck-1': 1,
        'inat_enrichment_attempted_at.deck-1': 2,
      });
      final prefs = await SharedPreferences.getInstance();

      final restoredService = INatEnrichmentQueueService(
        mockEnrichmentService,
        resolveSpeciesIds: (_) async => {'sp1'},
        updateCoverPath: (_, __) async {},
        imageService: mockImageService,
        preferences: prefs,
      );

      final info = restoredService.deckInfo('deck-1');
      expect(info.lastCompletedAt, isNotNull);
      expect(info.lastAttemptedAt, isNotNull);
    },
  );
}
