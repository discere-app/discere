import 'dart:async';

import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/service/enrichment_background_scheduler.dart';
import 'package:discere/enrichment/service/enrichment_job_ports.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockEnrichmentService mockEnrichmentService;
  late MockImageService mockImageService;
  late Database database;
  late EnrichmentJobRepository jobRepository;
  INatEnrichmentQueueService? service;
  late _TestDeckSpeciesSnapshotPort deckSpeciesSnapshotPort;
  late _TestDeckCoverStorePort deckCoverStorePort;
  late INatEnrichmentQueueService Function({
    DeckSpeciesSnapshotPort? deckSpeciesSnapshotOverride,
    ScientificNameResolutionPort? nameResolutionPort,
    DeckSpeciesMutationPort? deckSpeciesMutationPort,
  })
  createService;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    mockEnrichmentService = MockEnrichmentService();
    mockImageService = MockImageService();
    database = await openDatabase(inMemoryDatabasePath, version: 1);
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_jobs.sql',
      ),
    );
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_job_stages.sql',
      ),
    );
    jobRepository = EnrichmentJobRepository(database);
    deckSpeciesSnapshotPort = _TestDeckSpeciesSnapshotPort();
    deckCoverStorePort = _TestDeckCoverStorePort();
    createService = ({
      DeckSpeciesSnapshotPort? deckSpeciesSnapshotOverride,
      ScientificNameResolutionPort? nameResolutionPort,
      DeckSpeciesMutationPort? deckSpeciesMutationPort,
    }) {
      return INatEnrichmentQueueService(
        mockEnrichmentService,
        deckSpeciesSnapshotPort:
            deckSpeciesSnapshotOverride ?? deckSpeciesSnapshotPort,
        deckCoverStore: deckCoverStorePort,
        imageService: mockImageService,
        nameResolutionPort: nameResolutionPort,
        deckSpeciesMutationPort: deckSpeciesMutationPort,
        backgroundScheduler: const NoopEnrichmentBackgroundScheduler(),
        jobRepository: jobRepository,
      );
    };

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

  tearDown(() async {
    service = null;
    await database.close();
  });

  test('runs full background enrichment for a deck', () async {
    service = createService();
    await service!.scheduleDeckEnrichment(
      ['deck-1'],
      waitForForegroundIdle: true,
    );

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
    expect(service!.status, INatEnrichmentStatus.idle);
    expect(service!.deckInfo('deck-1').isActive, isFalse);
    expect(service!.deckInfo('deck-1').lastAttemptedAt, isNotNull);
    expect(service!.deckInfo('deck-1').lastCompletedAt, isNotNull);
    expect(service!.deckInfo('deck-1').hasFailedAttempt, isFalse);
  });

  test('can schedule base-image-only enrichment', () async {
    service = createService();
    await service!.scheduleDeckEnrichment(
      ['deck-1'],
      includeINatPhotos: false,
      includeCommonNames: false,
      waitForForegroundIdle: true,
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
    expect(service!.deckInfo('deck-1').lastAttemptedAt, isNotNull);
    expect(service!.deckInfo('deck-1').lastCompletedAt, isNotNull);
  });

  test('marks failed runs as attempted but not completed', () async {
    service = createService();
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

    await service!.scheduleDeckEnrichment(
      ['deck-1'],
      waitForForegroundIdle: true,
    );

    final info = service!.deckInfo('deck-1');
    expect(info.lastAttemptedAt, isNotNull);
    expect(info.lastCompletedAt, isNull);
    expect(info.hasFailedAttempt, isTrue);
  });

  test('reports completed state after successful run', () async {
    service = createService();
    await service!.scheduleDeckEnrichment(
      ['deck-1'],
      waitForForegroundIdle: true,
    );

    expect(service!.deckInfo('deck-1').status, EnrichmentJobStatus.completed);
  });

  test('cancelling during name resolution prevents deck mutation', () async {
    final nameResolutionStarted = Completer<void>();
    final allowNameResolutionToFinish = Completer<void>();
    final deckMutationPort = _RecordingDeckSpeciesMutationPort();
    final nameResolutionPort = _BlockingNameResolutionPort(
      onStarted: () => nameResolutionStarted.complete(),
      waitForCompletion: allowNameResolutionToFinish.future,
      result: {'Unknown fish': 'sp2'},
    );
    service = createService(
      deckSpeciesSnapshotOverride: _EmptyDeckSpeciesSnapshotPort(),
      nameResolutionPort: nameResolutionPort,
      deckSpeciesMutationPort: deckMutationPort,
    );

    await service!.scheduleDeckEnrichment(
      ['deck-1'],
      includeINatPhotos: false,
      includeCommonNames: false,
      unresolvedNamesByDeckId: const {
        'deck-1': ['Unknown fish'],
      },
    );

    await nameResolutionStarted.future;
    service!.cancelDeckEnrichment('deck-1');
    allowNameResolutionToFinish.complete();
    await _waitForCondition(
      () => service!.deckInfo('deck-1').status == EnrichmentJobStatus.cancelled,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(deckMutationPort.calls, isEmpty);
    expect(service!.deckInfo('deck-1').status, EnrichmentJobStatus.cancelled);
  });

  test('cancelling during cover download prevents cover update', () async {
    final coverStarted = Completer<void>();
    final allowCoverToFinish = Completer<void>();
    when(
      mockImageService.downloadAndSaveDeckCover('https://example.com/cover.jpg'),
    ).thenAnswer((_) async {
      coverStarted.complete();
      await allowCoverToFinish.future;
      return '/tmp/cover.jpg';
    });
    service = createService(
      deckSpeciesSnapshotOverride: _EmptyDeckSpeciesSnapshotPort(),
    );

    await service!.scheduleDeckEnrichment(
      ['deck-1'],
      includeINatPhotos: false,
      includeCommonNames: false,
      coverImageUrlsByDeckId: const {
        'deck-1': 'https://example.com/cover.jpg',
      },
    );

    await coverStarted.future;
    service!.cancelDeckEnrichment('deck-1');
    allowCoverToFinish.complete();
    await _waitForCondition(
      () => service!.deckInfo('deck-1').status == EnrichmentJobStatus.cancelled,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(deckCoverStorePort.updatedDeckIds, isEmpty);
    expect(service!.deckInfo('deck-1').status, EnrichmentJobStatus.cancelled);
  });
}

Future<void> _waitForCondition(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!predicate()) {
    if (stopwatch.elapsed > timeout) {
      throw StateError('Timed out waiting for test condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _TestDeckSpeciesSnapshotPort implements DeckSpeciesSnapshotPort {
  @override
  Future<Set<String>> loadSpeciesIdsForDecks(Set<String> deckIds) async => {
    'sp1',
  };
}

class _EmptyDeckSpeciesSnapshotPort implements DeckSpeciesSnapshotPort {
  @override
  Future<Set<String>> loadSpeciesIdsForDecks(Set<String> deckIds) async => {};
}

class _TestDeckCoverStorePort implements DeckCoverStorePort {
  final List<String> updatedDeckIds = <String>[];

  @override
  Future<void> updateDeckCoverPath(String deckId, String localPath) async {
    updatedDeckIds.add(deckId);
  }
}

class _RecordingDeckSpeciesMutationPort implements DeckSpeciesMutationPort {
  final List<({String deckId, Set<String> speciesIds})> calls = [];

  @override
  Future<void> addSpeciesToDeck(String deckId, Set<String> speciesIds) async {
    calls.add((deckId: deckId, speciesIds: speciesIds));
  }
}

class _BlockingNameResolutionPort implements ScientificNameResolutionPort {
  final void Function() onStarted;
  final Future<void> waitForCompletion;
  final Map<String, String> result;

  _BlockingNameResolutionPort({
    required this.onStarted,
    required this.waitForCompletion,
    required this.result,
  });

  @override
  Future<Map<String, String>> resolveNames(List<String> names) async {
    onStarted();
    await waitForCompletion;
    return result;
  }
}
