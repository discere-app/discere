import 'dart:async';

import 'package:discere/enrichment/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/service/enrichment_background_scheduler.dart';
import 'package:discere/enrichment/service/enrichment_foreground_service_keeper.dart';
import 'package:discere/enrichment/service/enrichment_job_ports.dart';
import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/enrichment/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/local_diagnostics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockEnrichmentService mockEnrichmentService;
  late MockTaxonomyCommonNameEnrichmentService mockTaxonomyEnrichmentService;
  late MockImageService mockImageService;
  late Database database;
  late EnrichmentJobRepository jobRepository;
  late EnrichmentWorkRepository workRepository;
  INatEnrichmentQueueService? service;
  late _TestDeckSpeciesSnapshotPort deckSpeciesSnapshotPort;
  late _TestDeckCoverStorePort deckCoverStorePort;
  late INatEnrichmentQueueService Function({
    DeckSpeciesSnapshotPort? deckSpeciesSnapshotOverride,
    ScientificNameResolutionPort? nameResolutionPort,
    DeckSpeciesMutationPort? deckSpeciesMutationPort,
    EnrichmentBackgroundScheduler? backgroundScheduler,
    EnrichmentForegroundServiceKeeper? foregroundServiceKeeper,
    bool autoInitialize,
    bool processJobs,
  })
  createService;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    mockEnrichmentService = MockEnrichmentService();
    mockTaxonomyEnrichmentService = MockTaxonomyCommonNameEnrichmentService();
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
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_species_work.sql',
      ),
    );
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_taxonomy_work.sql',
      ),
    );
    jobRepository = EnrichmentJobRepository(database);
    workRepository = EnrichmentWorkRepository(database);
    deckSpeciesSnapshotPort = _TestDeckSpeciesSnapshotPort();
    deckCoverStorePort = _TestDeckCoverStorePort();
    createService =
        ({
          DeckSpeciesSnapshotPort? deckSpeciesSnapshotOverride,
          ScientificNameResolutionPort? nameResolutionPort,
          DeckSpeciesMutationPort? deckSpeciesMutationPort,
          EnrichmentBackgroundScheduler? backgroundScheduler,
          EnrichmentForegroundServiceKeeper? foregroundServiceKeeper,
          bool autoInitialize = true,
          bool processJobs = true,
        }) {
          return INatEnrichmentQueueService(
            mockEnrichmentService,
            taxonomyEnrichmentService: mockTaxonomyEnrichmentService,
            deckSpeciesSnapshotPort:
                deckSpeciesSnapshotOverride ?? deckSpeciesSnapshotPort,
            deckCoverStore: deckCoverStorePort,
            imageService: mockImageService,
            nameResolutionPort: nameResolutionPort,
            deckSpeciesMutationPort: deckSpeciesMutationPort,
            backgroundScheduler:
                backgroundScheduler ??
                const NoopEnrichmentBackgroundScheduler(),
            foregroundServiceKeeper: foregroundServiceKeeper,
            jobRepository: jobRepository,
            workRepository: workRepository,
            hostCooldownTracker: HostCooldownTracker(),
            diagnostics: LocalDiagnostics(enabled: false),
            autoInitialize: autoInitialize,
            processJobs: processJobs,
          );
        };

    when(
      mockEnrichmentService.downloadBaseImagesForSpecies(
        argThat(isA<Set<String>>()),
        onProgress: anyNamed('onProgress'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      final speciesIds = invocation.positionalArguments.first as Set<String>;
      final onSpeciesCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String speciesId)?;
      final onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(int completed, int total)?;
      final orderedSpeciesIds = speciesIds.toList()..sort();
      for (var index = 0; index < orderedSpeciesIds.length; index++) {
        onSpeciesCompleted?.call(orderedSpeciesIds[index]);
        onProgress?.call(index + 1, orderedSpeciesIds.length);
      }
      return ImportEnrichmentSummary.empty;
    });
    when(
      mockEnrichmentService.fetchINatPhotosForSpecies(
        argThat(isA<Set<String>>()),
        onProgress: anyNamed('onProgress'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        force: false,
        primaryOnly: true,
        prioritizeSpeciesWithoutImages: true,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      final speciesIds = invocation.positionalArguments.first as Set<String>;
      final onSpeciesCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String speciesId)?;
      final onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(int completed, int total)?;
      final orderedSpeciesIds = speciesIds.toList()..sort();
      for (var index = 0; index < orderedSpeciesIds.length; index++) {
        onSpeciesCompleted?.call(orderedSpeciesIds[index]);
        onProgress?.call(index + 1, orderedSpeciesIds.length);
      }
      return ImportEnrichmentSummary.empty;
    });
    when(
      mockTaxonomyEnrichmentService.buildTaxonomyWorkPlanForSpecies(
        argThat(isA<Set<String>>()),
      ),
    ).thenAnswer((invocation) async {
      final speciesIds = invocation.positionalArguments.first as Set<String>;
      final orderedSpeciesIds = speciesIds.toList()..sort();
      return orderedSpeciesIds
          .map(
            (speciesId) => TaxonomyWorkPlanItem(
              workKey: 'taxonomy-work:$speciesId',
              runtimeEntityKey: 'taxonomy:$speciesId',
              rank: 'genus',
              scientificName: speciesId,
              speciesIds: {speciesId},
            ),
          )
          .toList(growable: false);
    });
    when(
      mockEnrichmentService.fetchSpeciesCommonNamesForSpecies(
        argThat(isA<Set<String>>()),
        onProgress: anyNamed('onProgress'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        onDiagnostics: anyNamed('onDiagnostics'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      final speciesIds = invocation.positionalArguments.first as Set<String>;
      final onSpeciesCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String speciesId)?;
      final onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(int completed, int total)?;
      final onDiagnostics =
          invocation.namedArguments[#onDiagnostics]
              as void Function(CommonNameStageDiagnostics diagnostics)?;
      final orderedSpeciesIds = speciesIds.toList()..sort();
      for (var index = 0; index < orderedSpeciesIds.length; index++) {
        onSpeciesCompleted?.call(orderedSpeciesIds[index]);
        onProgress?.call(index + 1, orderedSpeciesIds.length);
      }
      onDiagnostics?.call(const CommonNameStageDiagnostics());
      return ImportEnrichmentSummary.empty;
    });
    when(
      mockTaxonomyEnrichmentService.fetchINatTaxonomyCommonNamesForEntityKeys(
        argThat(isA<Set<String>>()),
        entityKeys: argThat(isA<Iterable<String>>(), named: 'entityKeys'),
        onEntityCompleted: anyNamed('onEntityCompleted'),
        onDiagnostics: anyNamed('onDiagnostics'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      final entityKeys =
          invocation.namedArguments[#entityKeys] as Iterable<String>;
      final onEntityCompleted =
          invocation.namedArguments[#onEntityCompleted]
              as void Function(String entityKey)?;
      final onDiagnostics =
          invocation.namedArguments[#onDiagnostics]
              as void Function(TaxonomyCommonNameDiagnostics diagnostics)?;
      for (final entityKey in entityKeys) {
        onEntityCompleted?.call(entityKey);
      }
      onDiagnostics?.call(const TaxonomyCommonNameDiagnostics());
      return ImportEnrichmentSummary.empty;
    });
    when(
      mockEnrichmentService.backfillINatPhotosForSpecies(
        argThat(isA<Set<String>>()),
        onProgress: anyNamed('onProgress'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        targetPhotoCount: 10,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      final speciesIds = invocation.positionalArguments.first as Set<String>;
      final onSpeciesCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String speciesId)?;
      final onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(int completed, int total)?;
      final orderedSpeciesIds = speciesIds.toList()..sort();
      for (var index = 0; index < orderedSpeciesIds.length; index++) {
        onSpeciesCompleted?.call(orderedSpeciesIds[index]);
        onProgress?.call(index + 1, orderedSpeciesIds.length);
      }
      return ImportEnrichmentSummary.empty;
    });
  });

  tearDown(() async {
    service?.dispose();
    service = null;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await database.close();
  });

  test('runs full background enrichment for a deck', () async {
    service = createService();
    await service!.scheduleDeckEnrichment([
      'deck-1',
    ], waitForForegroundIdle: true);

    verify(
      mockEnrichmentService.downloadBaseImagesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).called(1);
    verify(
      mockEnrichmentService.fetchINatPhotosForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        force: false,
        primaryOnly: true,
        prioritizeSpeciesWithoutImages: true,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).called(1);
    verify(
      mockEnrichmentService.fetchSpeciesCommonNamesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        onDiagnostics: anyNamed('onDiagnostics'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).called(1);
    verify(
      mockTaxonomyEnrichmentService.buildTaxonomyWorkPlanForSpecies({'sp1'}),
    ).called(1);
    verify(
      mockTaxonomyEnrichmentService.fetchINatTaxonomyCommonNamesForEntityKeys(
        {'sp1'},
        entityKeys: ['taxonomy:sp1'],
        onEntityCompleted: anyNamed('onEntityCompleted'),
        onDiagnostics: anyNamed('onDiagnostics'),
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
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
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
    expect(service!.deckInfo('deck-1').includesINatPhotos, isTrue);
    expect(service!.deckInfo('deck-1').includesCommonNames, isTrue);
    expect(service!.deckInfo('deck-1').hasCompletedINatEnrichment, isTrue);
  });

  test(
    'skips listener and notification churn when queue state stays visibly idle',
    () async {
      final keeper = _RecordingForegroundServiceKeeper();
      var listenerCallCount = 0;
      service = createService(
        autoInitialize: false,
        processJobs: false,
        foregroundServiceKeeper: keeper,
      );
      service!.addListener(() {
        listenerCallCount++;
      });

      await service!.initialize();
      await service!.enterInteractivePriorityMode();
      await service!.leaveInteractivePriorityMode();

      expect(listenerCallCount, 0);
      expect(keeper.startCalls, 0);
      expect(keeper.stopCalls, 0);
      expect(keeper.updateCalls, 0);
      expect(service!.status, INatEnrichmentStatus.idle);
    },
  );

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
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).called(1);
    verifyNever(
      mockEnrichmentService.fetchINatPhotosForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        force: false,
        primaryOnly: true,
        prioritizeSpeciesWithoutImages: true,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    );
    verifyNever(
      mockEnrichmentService.fetchSpeciesCommonNamesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        onDiagnostics: anyNamed('onDiagnostics'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    );
    verifyNever(
      mockTaxonomyEnrichmentService.buildTaxonomyWorkPlanForSpecies(
        argThat(isA<Set<String>>()),
      ),
    );
    verifyNever(
      mockTaxonomyEnrichmentService.fetchINatTaxonomyCommonNamesForEntityKeys(
        argThat(isA<Set<String>>()),
        entityKeys: argThat(isA<Iterable<String>>(), named: 'entityKeys'),
        onEntityCompleted: anyNamed('onEntityCompleted'),
        onDiagnostics: anyNamed('onDiagnostics'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    );
    expect(service!.deckInfo('deck-1').lastAttemptedAt, isNotNull);
    expect(service!.deckInfo('deck-1').lastCompletedAt, isNotNull);
    expect(service!.deckInfo('deck-1').includesINatPhotos, isFalse);
    expect(service!.deckInfo('deck-1').includesCommonNames, isFalse);
    expect(service!.deckInfo('deck-1').hasCompletedINatEnrichment, isFalse);
  });

  test(
    'does not start foreground-service keeper while app stays in foreground',
    () async {
      final keeper = _RecordingForegroundServiceKeeper();
      service = createService(foregroundServiceKeeper: keeper);

      await service!.scheduleDeckEnrichment([
        'deck-1',
      ], waitForForegroundIdle: true);

      expect(keeper.startCalls, equals(0));
    },
  );

  test(
    'starts foreground-service keeper on background handoff and stops on resume',
    () async {
      final scheduler = _RecordingBackgroundScheduler();
      final keeper = _RecordingForegroundServiceKeeper();
      final baseStageGate = Completer<void>();
      service = createService(
        backgroundScheduler: scheduler,
        foregroundServiceKeeper: keeper,
      );

      when(
        mockEnrichmentService.downloadBaseImagesForSpecies(
          {'sp1'},
          onProgress: anyNamed('onProgress'),
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
          isCancelled: anyNamed('isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        final onSpeciesCompleted =
            invocation.namedArguments[#onSpeciesCompleted]
                as void Function(String speciesId)?;
        onSpeciesCompleted?.call('sp1');
        final onProgress =
            invocation.namedArguments[#onProgress]
                as void Function(int completed, int total)?;
        onProgress?.call(0, 1);
        await baseStageGate.future;
        onProgress?.call(1, 1);
        return ImportEnrichmentSummary.empty;
      });

      await service!.scheduleDeckEnrichment(['deck-1']);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(keeper.startCalls, greaterThanOrEqualTo(1));
      expect(keeper.stopCalls, equals(0));

      baseStageGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(keeper.stopCalls, greaterThanOrEqualTo(1));
    },
  );

  test(
    'retries remaining species immediately after a temporary failure',
    () async {
      final callSpecies = <Set<String>>[];
      deckSpeciesSnapshotPort = _TestDeckSpeciesSnapshotPort(
        speciesIdsByDeckId: const {
          'deck-1': {'sp1', 'sp2', 'sp3'},
        },
      );

      when(
        mockEnrichmentService.downloadBaseImagesForSpecies(
          {'sp1', 'sp2', 'sp3'},
          onProgress: anyNamed('onProgress'),
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
          isCancelled: anyNamed('isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        callSpecies.add({'sp1', 'sp2', 'sp3'});
        final onSpeciesCompleted =
            invocation.namedArguments[#onSpeciesCompleted]
                as void Function(String speciesId)?;
        onSpeciesCompleted?.call('sp1');
        throw TimeoutException('temporary');
      });
      when(
        mockEnrichmentService.downloadBaseImagesForSpecies(
          {'sp2', 'sp3'},
          onProgress: anyNamed('onProgress'),
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
          isCancelled: anyNamed('isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        callSpecies.add({'sp2', 'sp3'});
        final onSpeciesCompleted =
            invocation.namedArguments[#onSpeciesCompleted]
                as void Function(String speciesId)?;
        onSpeciesCompleted?.call('sp2');
        onSpeciesCompleted?.call('sp3');
        return ImportEnrichmentSummary.empty;
      });

      service = createService();
      await service!.scheduleDeckEnrichment(
        ['deck-1'],
        includeINatPhotos: false,
        includeCommonNames: false,
        waitForForegroundIdle: true,
      );

      expect(
        callSpecies,
        equals([
          {'sp1', 'sp2', 'sp3'},
          {'sp2', 'sp3'},
        ]),
      );

      final job = await jobRepository.loadJob('deck-1');
      expect(job, isNotNull);
      expect(job!.status, EnrichmentJobStatus.completed);
    },
  );

  test('can queue enrichment without processing foreground jobs', () async {
    service = createService(processJobs: false);

    await service!.scheduleDeckEnrichment(
      ['deck-1'],
      includeINatPhotos: false,
      includeCommonNames: false,
      waitForForegroundIdle: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    verifyNever(
      mockEnrichmentService.downloadBaseImagesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    );
    expect(
      service!.status,
      const INatEnrichmentStatus(
        isRunning: false,
        hasPendingWork: true,
        hasActiveWork: true,
        hasActiveHostCooldown: false,
        phase: INatEnrichmentPhase.base,
        completed: 0,
        total: 1,
        activeDeckCount: 1,
        readyDeckCount: 0,
        totalDeckCount: 1,
      ),
    );
    expect(service!.deckInfo('deck-1').status, EnrichmentJobStatus.queued);
    expect(service!.deckInfo('deck-1').hasPendingWork, isTrue);
    expect(service!.deckInfo('deck-1').currentPhase, INatEnrichmentPhase.base);
  });

  test(
    'reports decks as ready after base pass while enrichment continues',
    () async {
      final primaryStarted = Completer<void>();
      final allowPrimaryToFinish = Completer<void>();
      deckSpeciesSnapshotPort = _TestDeckSpeciesSnapshotPort(
        speciesIdsByDeckId: const {
          'deck-1': {'sp1'},
          'deck-2': {'sp2'},
        },
      );

      when(
        mockEnrichmentService.downloadBaseImagesForSpecies(
          {'sp1'},
          onProgress: anyNamed('onProgress'),
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
          isCancelled: anyNamed('isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        final onSpeciesCompleted =
            invocation.namedArguments[#onSpeciesCompleted]
                as void Function(String speciesId)?;
        onSpeciesCompleted?.call('sp1');
        final onProgress =
            invocation.namedArguments[#onProgress]
                as void Function(int completed, int total)?;
        onProgress?.call(1, 1);
        return const ImportEnrichmentSummary(
          imageSpeciesCount: 1,
          imageCount: 1,
          commonNameSpeciesCount: 0,
          commonNameCount: 0,
        );
      });
      when(
        mockEnrichmentService.downloadBaseImagesForSpecies(
          {'sp2'},
          onProgress: anyNamed('onProgress'),
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
          isCancelled: anyNamed('isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        final onSpeciesCompleted =
            invocation.namedArguments[#onSpeciesCompleted]
                as void Function(String speciesId)?;
        onSpeciesCompleted?.call('sp2');
        final onProgress =
            invocation.namedArguments[#onProgress]
                as void Function(int completed, int total)?;
        onProgress?.call(1, 1);
        return const ImportEnrichmentSummary(
          imageSpeciesCount: 1,
          imageCount: 1,
          commonNameSpeciesCount: 0,
          commonNameCount: 0,
        );
      });
      when(
        mockEnrichmentService.fetchINatPhotosForSpecies(
          {'sp1'},
          onProgress: anyNamed('onProgress'),
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
          force: false,
          primaryOnly: true,
          prioritizeSpeciesWithoutImages: true,
          maxConcurrent: 1,
          requestSpacing: const Duration(milliseconds: 1100),
          isCancelled: anyNamed('isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        if (!primaryStarted.isCompleted) {
          primaryStarted.complete();
        }
        final onSpeciesCompleted =
            invocation.namedArguments[#onSpeciesCompleted]
                as void Function(String speciesId)?;
        final onProgress =
            invocation.namedArguments[#onProgress]
                as void Function(int completed, int total)?;
        onProgress?.call(0, 1);
        await allowPrimaryToFinish.future;
        onSpeciesCompleted?.call('sp1');
        onProgress?.call(1, 1);
        return ImportEnrichmentSummary.empty;
      });
      when(
        mockEnrichmentService.fetchINatPhotosForSpecies(
          {'sp2'},
          onProgress: anyNamed('onProgress'),
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
          force: false,
          primaryOnly: true,
          prioritizeSpeciesWithoutImages: true,
          maxConcurrent: 1,
          requestSpacing: const Duration(milliseconds: 1100),
          isCancelled: anyNamed('isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        final onSpeciesCompleted =
            invocation.namedArguments[#onSpeciesCompleted]
                as void Function(String speciesId)?;
        final onProgress =
            invocation.namedArguments[#onProgress]
                as void Function(int completed, int total)?;
        onProgress?.call(0, 1);
        await allowPrimaryToFinish.future;
        onSpeciesCompleted?.call('sp2');
        onProgress?.call(1, 1);
        return ImportEnrichmentSummary.empty;
      });
      when(
        mockEnrichmentService.backfillINatPhotosForSpecies(
          {'sp1'},
          onProgress: anyNamed('onProgress'),
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
          targetPhotoCount: 10,
          maxConcurrent: 1,
          requestSpacing: const Duration(milliseconds: 1100),
          isCancelled: anyNamed('isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        final onSpeciesCompleted =
            invocation.namedArguments[#onSpeciesCompleted]
                as void Function(String speciesId)?;
        onSpeciesCompleted?.call('sp1');
        final onProgress =
            invocation.namedArguments[#onProgress]
                as void Function(int completed, int total)?;
        onProgress?.call(1, 1);
        return ImportEnrichmentSummary.empty;
      });
      when(
        mockEnrichmentService.backfillINatPhotosForSpecies(
          {'sp2'},
          onProgress: anyNamed('onProgress'),
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
          targetPhotoCount: 10,
          maxConcurrent: 1,
          requestSpacing: const Duration(milliseconds: 1100),
          isCancelled: anyNamed('isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        final onSpeciesCompleted =
            invocation.namedArguments[#onSpeciesCompleted]
                as void Function(String speciesId)?;
        onSpeciesCompleted?.call('sp2');
        final onProgress =
            invocation.namedArguments[#onProgress]
                as void Function(int completed, int total)?;
        onProgress?.call(1, 1);
        return ImportEnrichmentSummary.empty;
      });

      service = createService();
      await service!.scheduleDeckEnrichment(['deck-1', 'deck-2']);
      await primaryStarted.future;
      await _waitForCondition(() {
        final status = service!.status;
        return status.hasPendingWork &&
            status.readyDeckCount == 2 &&
            status.totalDeckCount == 2;
      });

      expect(
        service!.status,
        isA<INatEnrichmentStatus>()
            .having((status) => status.hasPendingWork, 'hasPendingWork', isTrue)
            .having((status) => status.readyDeckCount, 'readyDeckCount', 2)
            .having((status) => status.totalDeckCount, 'totalDeckCount', 2),
      );

      allowPrimaryToFinish.complete();
      await _waitForCondition(() => !service!.status.hasPendingWork);
    },
  );

  test(
    'prioritizes cover before name resolution within the quick pass',
    () async {
      final callOrder = <String>[];
      final nameResolutionStarted = Completer<void>();
      final allowNameResolutionToFinish = Completer<void>();

      when(
        mockImageService.downloadAndSaveDeckCover(
          'https://example.com/cover.jpg',
        ),
      ).thenAnswer((_) async {
        callOrder.add('cover');
        return '/tmp/cover.jpg';
      });

      final nameResolutionPort = _BlockingNameResolutionPort(
        onStarted: () {
          callOrder.add('nameResolution');
          if (!nameResolutionStarted.isCompleted) {
            nameResolutionStarted.complete();
          }
        },
        waitForCompletion: allowNameResolutionToFinish.future,
        result: {'Unknown fish': 'sp2'},
      );

      when(
        mockEnrichmentService.downloadBaseImagesForSpecies(
          {'sp2'},
          onProgress: anyNamed('onProgress'),
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
          isCancelled: anyNamed('isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        callOrder.add('base');
        final onSpeciesCompleted =
            invocation.namedArguments[#onSpeciesCompleted]
                as void Function(String speciesId)?;
        onSpeciesCompleted?.call('sp2');
        final onProgress =
            invocation.namedArguments[#onProgress]
                as void Function(int completed, int total)?;
        onProgress?.call(1, 1);
        return ImportEnrichmentSummary.empty;
      });

      service = createService(
        deckSpeciesSnapshotOverride: _EmptyDeckSpeciesSnapshotPort(),
        nameResolutionPort: nameResolutionPort,
        deckSpeciesMutationPort: _RecordingDeckSpeciesMutationPort(),
      );

      await service!.scheduleDeckEnrichment(
        ['deck-1'],
        includeINatPhotos: false,
        includeCommonNames: false,
        coverImageUrlsByDeckId: const {
          'deck-1': 'https://example.com/cover.jpg',
        },
        unresolvedNamesByDeckId: const {
          'deck-1': ['Unknown fish'],
        },
      );

      await nameResolutionStarted.future;
      expect(callOrder, equals(['cover', 'nameResolution']));

      allowNameResolutionToFinish.complete();
      await _waitForCondition(
        () =>
            service!.deckInfo('deck-1').status == EnrichmentJobStatus.completed,
      );
      await _waitForCondition(
        () => service!.status == INatEnrichmentStatus.idle,
      );

      expect(callOrder, equals(['cover', 'nameResolution', 'base']));
    },
  );

  test(
    'prioritizes quick-pass stages across all decks before deep pass',
    () async {
      final callOrder = <String>[];
      deckSpeciesSnapshotPort = _TestDeckSpeciesSnapshotPort(
        speciesIdsByDeckId: const {
          'deck-1': {'sp1'},
          'deck-2': {'sp2'},
          'deck-3': {'sp3'},
        },
      );

      void stubDeck(String speciesId) {
        final speciesSet = {speciesId};
        when(
          mockEnrichmentService.downloadBaseImagesForSpecies(
            speciesSet,
            onProgress: anyNamed('onProgress'),
            onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
            isCancelled: anyNamed('isCancelled'),
          ),
        ).thenAnswer((invocation) async {
          callOrder.add('base:$speciesId');
          final onSpeciesCompleted =
              invocation.namedArguments[#onSpeciesCompleted]
                  as void Function(String speciesId)?;
          onSpeciesCompleted?.call(speciesId);
          final onProgress =
              invocation.namedArguments[#onProgress]
                  as void Function(int completed, int total)?;
          onProgress?.call(1, 1);
          return ImportEnrichmentSummary.empty;
        });
        when(
          mockEnrichmentService.fetchINatPhotosForSpecies(
            speciesSet,
            onProgress: anyNamed('onProgress'),
            onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
            force: false,
            primaryOnly: true,
            prioritizeSpeciesWithoutImages: true,
            maxConcurrent: 1,
            requestSpacing: const Duration(milliseconds: 1100),
            isCancelled: anyNamed('isCancelled'),
          ),
        ).thenAnswer((invocation) async {
          callOrder.add('primary:$speciesId');
          final onSpeciesCompleted =
              invocation.namedArguments[#onSpeciesCompleted]
                  as void Function(String speciesId)?;
          onSpeciesCompleted?.call(speciesId);
          final onProgress =
              invocation.namedArguments[#onProgress]
                  as void Function(int completed, int total)?;
          onProgress?.call(1, 1);
          return ImportEnrichmentSummary.empty;
        });
        when(
          mockEnrichmentService.fetchSpeciesCommonNamesForSpecies(
            speciesSet,
            onProgress: anyNamed('onProgress'),
            onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
            onDiagnostics: anyNamed('onDiagnostics'),
            force: false,
            maxConcurrent: 1,
            requestSpacing: const Duration(milliseconds: 1100),
            isCancelled: anyNamed('isCancelled'),
          ),
        ).thenAnswer((invocation) async {
          callOrder.add('names:$speciesId');
          final onSpeciesCompleted =
              invocation.namedArguments[#onSpeciesCompleted]
                  as void Function(String speciesId)?;
          onSpeciesCompleted?.call(speciesId);
          final onProgress =
              invocation.namedArguments[#onProgress]
                  as void Function(int completed, int total)?;
          onProgress?.call(1, 1);
          final onDiagnostics =
              invocation.namedArguments[#onDiagnostics]
                  as void Function(CommonNameStageDiagnostics diagnostics)?;
          onDiagnostics?.call(const CommonNameStageDiagnostics());
          return ImportEnrichmentSummary.empty;
        });
        when(
          mockTaxonomyEnrichmentService.buildTaxonomyWorkPlanForSpecies(speciesSet),
        ).thenAnswer(
          (_) async => [
            TaxonomyWorkPlanItem(
              workKey: 'taxonomy-work:$speciesId',
              runtimeEntityKey: 'taxonomy:$speciesId',
              rank: 'genus',
              scientificName: speciesId,
              speciesIds: {speciesId},
            ),
          ],
        );
        when(
          mockTaxonomyEnrichmentService.fetchINatTaxonomyCommonNamesForEntityKeys(
            speciesSet,
            entityKeys: ['taxonomy:$speciesId'],
            onEntityCompleted: anyNamed('onEntityCompleted'),
            onDiagnostics: anyNamed('onDiagnostics'),
            force: false,
            maxConcurrent: 1,
            requestSpacing: const Duration(milliseconds: 1100),
            isCancelled: anyNamed('isCancelled'),
          ),
        ).thenAnswer((invocation) async {
          final onEntityCompleted =
              invocation.namedArguments[#onEntityCompleted]
                  as void Function(String entityKey)?;
          onEntityCompleted?.call('taxonomy:$speciesId');
          final onDiagnostics =
              invocation.namedArguments[#onDiagnostics]
                  as void Function(TaxonomyCommonNameDiagnostics diagnostics)?;
          onDiagnostics?.call(const TaxonomyCommonNameDiagnostics());
          return ImportEnrichmentSummary.empty;
        });
        when(
          mockEnrichmentService.backfillINatPhotosForSpecies(
            speciesSet,
            onProgress: anyNamed('onProgress'),
            onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
            targetPhotoCount: 10,
            maxConcurrent: 1,
            requestSpacing: const Duration(milliseconds: 1100),
            isCancelled: anyNamed('isCancelled'),
          ),
        ).thenAnswer((invocation) async {
          callOrder.add('backfill:$speciesId');
          final onSpeciesCompleted =
              invocation.namedArguments[#onSpeciesCompleted]
                  as void Function(String speciesId)?;
          onSpeciesCompleted?.call(speciesId);
          final onProgress =
              invocation.namedArguments[#onProgress]
                  as void Function(int completed, int total)?;
          onProgress?.call(1, 1);
          return ImportEnrichmentSummary.empty;
        });
      }

      stubDeck('sp1');
      stubDeck('sp2');
      stubDeck('sp3');

      service = createService();
      await service!.scheduleDeckEnrichment([
        'deck-1',
        'deck-2',
        'deck-3',
      ], waitForForegroundIdle: true);

      expect(
        callOrder,
        equals([
          'base:sp1',
          'base:sp2',
          'base:sp3',
          'primary:sp1',
          'primary:sp2',
          'primary:sp3',
          'names:sp1',
          'names:sp2',
          'names:sp3',
          'backfill:sp1',
          'backfill:sp2',
          'backfill:sp3',
        ]),
      );
    },
  );

  test('processes large species stages in fair deck batches', () async {
    final deck1Species = {for (var i = 0; i < 30; i++) 'deck1-sp$i'};
    final deck2Species = {for (var i = 0; i < 30; i++) 'deck2-sp$i'};
    final baseBatches = <Set<String>>[];
    deckSpeciesSnapshotPort = _TestDeckSpeciesSnapshotPort(
      speciesIdsByDeckId: {'deck-1': deck1Species, 'deck-2': deck2Species},
    );

    when(
      mockEnrichmentService.downloadBaseImagesForSpecies(
        any,
        onProgress: anyNamed('onProgress'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      final speciesSet = (invocation.positionalArguments.first as Set<String>)
          .toSet();
      baseBatches.add(speciesSet);
      final onSpeciesCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String speciesId)?;
      final onProgress =
          invocation.namedArguments[#onProgress]
              as void Function(int completed, int total)?;
      final sortedSpecies = speciesSet.toList()..sort();
      for (var i = 0; i < sortedSpecies.length; i++) {
        onSpeciesCompleted?.call(sortedSpecies[i]);
        onProgress?.call(i + 1, sortedSpecies.length);
      }
      return ImportEnrichmentSummary.empty;
    });

    service = createService();
    await service!.scheduleDeckEnrichment(
      ['deck-1', 'deck-2'],
      includeINatPhotos: false,
      includeCommonNames: false,
      waitForForegroundIdle: true,
    );

    expect(baseBatches, hasLength(4));
    expect(baseBatches[0], hasLength(25));
    expect(baseBatches[1], hasLength(25));
    expect(baseBatches[2], hasLength(5));
    expect(baseBatches[3], hasLength(5));
    expect(
      baseBatches[0].every((speciesId) => speciesId.startsWith('deck1-')),
      isTrue,
    );
    expect(
      baseBatches[1].every((speciesId) => speciesId.startsWith('deck2-')),
      isTrue,
    );
    expect(
      baseBatches[2].every((speciesId) => speciesId.startsWith('deck1-')),
      isTrue,
    );
    expect(
      baseBatches[3].every((speciesId) => speciesId.startsWith('deck2-')),
      isTrue,
    );
  });

  test(
    'assigns overlapping species to a single owner deck during scheduling',
    () async {
      final baseBatches = <Set<String>>[];
      deckSpeciesSnapshotPort = _TestDeckSpeciesSnapshotPort(
        speciesIdsByDeckId: const {
          'deck-1': {'shared-sp', 'deck1-only'},
          'deck-2': {'shared-sp', 'deck2-only'},
        },
      );

      when(
        mockEnrichmentService.downloadBaseImagesForSpecies(
          argThat(isA<Set<String>>()),
          onProgress: anyNamed('onProgress'),
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
          isCancelled: anyNamed('isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        final speciesSet = (invocation.positionalArguments.first as Set<String>)
            .toSet();
        baseBatches.add(speciesSet);
        final onSpeciesCompleted =
            invocation.namedArguments[#onSpeciesCompleted]
                as void Function(String speciesId)?;
        final onProgress =
            invocation.namedArguments[#onProgress]
                as void Function(int completed, int total)?;
        final orderedSpeciesIds = speciesSet.toList()..sort();
        for (var i = 0; i < orderedSpeciesIds.length; i++) {
          onSpeciesCompleted?.call(orderedSpeciesIds[i]);
          onProgress?.call(i + 1, orderedSpeciesIds.length);
        }
        return ImportEnrichmentSummary.empty;
      });

      service = createService();
      await service!.scheduleDeckEnrichment(
        ['deck-1', 'deck-2'],
        includeINatPhotos: false,
        includeCommonNames: false,
        waitForForegroundIdle: true,
      );

      expect(baseBatches, hasLength(2));
      expect(baseBatches[0], {'shared-sp', 'deck1-only'});
      expect(baseBatches[1], {'deck2-only'});
      expect(
        baseBatches
            .expand((batch) => batch)
            .where((speciesId) => speciesId == 'shared-sp'),
        hasLength(1),
      );
    },
  );

  test('marks failed runs as attempted but not completed', () async {
    service = createService();
    when(
      mockEnrichmentService.fetchSpeciesCommonNamesForSpecies(
        {'sp1'},
        onProgress: anyNamed('onProgress'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        onDiagnostics: anyNamed('onDiagnostics'),
        force: false,
        maxConcurrent: 1,
        requestSpacing: const Duration(milliseconds: 1100),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenThrow(Exception('boom'));

    await service!.scheduleDeckEnrichment([
      'deck-1',
    ], waitForForegroundIdle: true);

    final info = service!.deckInfo('deck-1');
    expect(info.lastAttemptedAt, isNotNull);
    expect(info.lastCompletedAt, isNull);
    expect(info.hasFailedAttempt, isTrue);
  });

  test('reports completed state after successful run', () async {
    service = createService();
    await service!.scheduleDeckEnrichment([
      'deck-1',
    ], waitForForegroundIdle: true);

    expect(service!.deckInfo('deck-1').status, EnrichmentJobStatus.completed);
  });

  test(
    'keeps iNat primary stage pending when no species reaches a terminal outcome',
    () async {
      service = createService();

      when(
        mockEnrichmentService.fetchINatPhotosForSpecies(
          {'sp1'},
          onProgress: anyNamed('onProgress'),
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
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

      await service!.scheduleDeckEnrichment([
        'deck-1',
      ], waitForForegroundIdle: true);

      final info = service!.deckInfo('deck-1');
      expect(info.status, EnrichmentJobStatus.queued);
      expect(info.currentPhase, INatEnrichmentPhase.inat);
      expect(info.hasPendingWork, isTrue);
      expect(info.progressCompleted, 0);
      expect(info.progressTotal, 1);
      expect(info.lastCompletedAt, isNull);
    },
  );

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
    // Deletion (not soft-cancel) is what a deck-delete cancel does now, so
    // the job simply stops existing rather than surfacing a `cancelled`
    // status — deckInfo falls back to the default "hidden" record.
    await _waitForCondition(
      () => service!.deckInfo('deck-1').state == DeckEnrichmentState.hidden,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(deckMutationPort.calls, isEmpty);
    expect(await jobRepository.loadJob('deck-1'), isNull);
  });

  test('cancelling during cover download prevents cover update', () async {
    final coverStarted = Completer<void>();
    final allowCoverToFinish = Completer<void>();
    when(
      mockImageService.downloadAndSaveDeckCover(
        'https://example.com/cover.jpg',
      ),
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
      coverImageUrlsByDeckId: const {'deck-1': 'https://example.com/cover.jpg'},
    );

    await coverStarted.future;
    service!.cancelDeckEnrichment('deck-1');
    allowCoverToFinish.complete();
    await _waitForCondition(
      () => service!.deckInfo('deck-1').state == DeckEnrichmentState.hidden,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(deckCoverStorePort.updatedDeckIds, isEmpty);
    expect(await jobRepository.loadJob('deck-1'), isNull);
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
  final Map<String, Set<String>> speciesIdsByDeckId;

  _TestDeckSpeciesSnapshotPort({
    this.speciesIdsByDeckId = const {
      'deck-1': {'sp1'},
    },
  });

  @override
  Future<Set<String>> loadSpeciesIdsForDecks(Set<String> deckIds) async {
    return deckIds
        .expand((deckId) => speciesIdsByDeckId[deckId] ?? const <String>{})
        .toSet();
  }
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

class _RecordingBackgroundScheduler implements EnrichmentBackgroundScheduler {
  @override
  Future<void> cancelProcessingForDeck(String deckId) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> cancelAllPendingProcessing() async {}
}

class _RecordingForegroundServiceKeeper
    implements EnrichmentForegroundServiceKeeper {
  int startCalls = 0;
  int stopCalls = 0;
  int updateCalls = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> startKeepingAlive() async {
    startCalls++;
  }

  @override
  Future<void> stopKeepingAlive() async {
    stopCalls++;
  }

  @override
  Future<void> updateNotificationContent({
    required String title,
    required String text,
  }) async {
    updateCalls++;
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
