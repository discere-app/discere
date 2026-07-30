import 'dart:async';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/pipeline/model/import_enrichment_summary.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/enrichment_background_scheduler.dart';
import 'package:discere/enrichment/queue/service/enrichment_foreground_service_keeper.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../mocks.mocks.dart';

/// Builds a minimal [Species] fixture. [withReferencePicture] controls
/// whether `BaseWorker` finds a downloadable reference image for it — with
/// none, `BaseWorker` skips the download call entirely and falls back to
/// iNaturalist immediately (see `BaseWorker._hasReferencePicture`).
Species _species(String id, {bool withReferencePicture = true}) {
  return Species(
    id,
    id,
    'mockSource',
    'mockName',
    const {},
    Classification(
      '',
      const {},
      null,
      '',
      const {},
      '',
      const {},
      '',
      const {},
      null,
    ),
    withReferencePicture
        ? [
            Picture(
              id: '$id-pic',
              species: id,
              origin: 'fishbase',
              isUsable: 1,
              url: 'https://example.com/$id.jpg',
            ),
          ]
        : const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBaseImageEnrichmentService mockBaseImageEnrichmentService;
  late MockINatPhotoEnrichmentService mockPhotoEnrichmentService;
  late MockSpeciesCommonNameEnrichmentService mockCommonNameEnrichmentService;
  late MockTaxonomyCommonNameEnrichmentService mockTaxonomyEnrichmentService;
  late MockImageService mockImageService;
  late MockSpeciesRepository mockSpeciesRepository;
  late MockINatPhotoCacheRepository mockPhotoCacheRepository;
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
    mockBaseImageEnrichmentService = MockBaseImageEnrichmentService();
    mockPhotoEnrichmentService = MockINatPhotoEnrichmentService();
    mockCommonNameEnrichmentService = MockSpeciesCommonNameEnrichmentService();
    mockTaxonomyEnrichmentService = MockTaxonomyCommonNameEnrichmentService();
    mockImageService = MockImageService();
    mockSpeciesRepository = MockSpeciesRepository();
    mockPhotoCacheRepository = MockINatPhotoCacheRepository();
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
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_species_capability_state.sql',
      ),
    );
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_species_deck_membership.sql',
      ),
    );
    await database.execute(
      await rootBundle.loadString(
        'assets/sql/user_db/tables/create_enrichment_unresolved_names.sql',
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
            baseImageEnrichmentService: mockBaseImageEnrichmentService,
            photoEnrichmentService: mockPhotoEnrichmentService,
            commonNameEnrichmentService: mockCommonNameEnrichmentService,
            taxonomyEnrichmentService: mockTaxonomyEnrichmentService,
            speciesRepository: mockSpeciesRepository,
            photoCacheRepository: mockPhotoCacheRepository,
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

    // Default: every requested species has a downloadable reference picture,
    // so BaseWorker's download call is the one under a test's control unless
    // overridden per-test.
    when(mockSpeciesRepository.getSpecies(any)).thenAnswer((invocation) async {
      final ids = invocation.positionalArguments.first as Set<String>;
      return ids.map((id) => _species(id)).toSet();
    });
    // BaseWorker reads the *returned summary*'s imageCount (not a callback)
    // to decide success — default to "found an image" for every species so
    // scheduling a deck reaches a learnable state without per-test wiring.
    when(
      mockBaseImageEnrichmentService.downloadBaseImagesForSpecies(
        argThat(isA<Set<String>>()),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      final speciesIds = invocation.positionalArguments.first as Set<String>;
      return ImportEnrichmentSummary(
        imageSpeciesCount: speciesIds.length,
        imageCount: speciesIds.length,
        commonNameSpeciesCount: 0,
        commonNameCount: 0,
      );
    });
    // Default: iNat photo cache has something cached, so a primary/backfill
    // fetch (when one is actually attempted) resolves 'done' rather than
    // 'noResult'.
    when(mockPhotoCacheRepository.getCachedPhotos(any)).thenAnswer(
      (_) async => const [
        Picture(
          id: 'cached-1',
          species: 'x',
          origin: 'iNaturalist',
          isUsable: 1,
        ),
      ],
    );
    when(
      mockPhotoEnrichmentService.fetchINatPhotosForSpecies(
        argThat(isA<Set<String>>()),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        primaryOnly: anyNamed('primaryOnly'),
      ),
    ).thenAnswer((invocation) async {
      final speciesIds = invocation.positionalArguments.first as Set<String>;
      final onSpeciesCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String speciesId)?;
      for (final speciesId in speciesIds) {
        onSpeciesCompleted?.call(speciesId);
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
      mockCommonNameEnrichmentService.fetchSpeciesCommonNamesForSpecies(
        argThat(isA<Set<String>>()),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
      ),
    ).thenAnswer((invocation) async {
      final speciesIds = invocation.positionalArguments.first as Set<String>;
      final onSpeciesCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String speciesId)?;
      for (final speciesId in speciesIds) {
        onSpeciesCompleted?.call(speciesId);
      }
      return ImportEnrichmentSummary.empty;
    });
    when(
      mockTaxonomyEnrichmentService.fetchINatTaxonomyCommonNamesForEntityKeys(
        argThat(isA<Set<String>>()),
        entityKeys: argThat(isA<Iterable<String>>(), named: 'entityKeys'),
        onEntityCompleted: anyNamed('onEntityCompleted'),
        onDiagnostics: anyNamed('onDiagnostics'),
        force: anyNamed('force'),
        maxConcurrent: anyNamed('maxConcurrent'),
        requestSpacing: anyNamed('requestSpacing'),
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
      mockPhotoEnrichmentService.backfillINatPhotosForSpecies(
        argThat(isA<Set<String>>()),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        targetPhotoCount: anyNamed('targetPhotoCount'),
      ),
    ).thenAnswer((invocation) async {
      final speciesIds = invocation.positionalArguments.first as Set<String>;
      final onSpeciesCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String speciesId)?;
      for (final speciesId in speciesIds) {
        onSpeciesCompleted?.call(speciesId);
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

  test('a species with a reference picture is fully enriched without ever '
      'touching iNaturalist for its primary photo', () async {
    service = createService();
    await service!.scheduleDeckEnrichment([
      'deck-1',
    ], waitForForegroundIdle: true);

    verify(
      mockBaseImageEnrichmentService.downloadBaseImagesForSpecies(
        {'sp1'},
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).called(1);
    // Base already found an image — inatPrimary is never seeded, saving
    // iNat's rate-limited request budget for species that actually need it.
    verifyNever(
      mockPhotoEnrichmentService.fetchINatPhotosForSpecies(
        argThat(contains('sp1')),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        primaryOnly: anyNamed('primaryOnly'),
      ),
    );
    verify(
      mockCommonNameEnrichmentService.fetchSpeciesCommonNamesForSpecies({
        'sp1',
      }, onSpeciesCompleted: anyNamed('onSpeciesCompleted')),
    ).called(1);
    verify(
      mockTaxonomyEnrichmentService.buildTaxonomyWorkPlanForSpecies({'sp1'}),
    ).called(1);
    verify(
      mockPhotoEnrichmentService.backfillINatPhotosForSpecies(
        {'sp1'},
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        targetPhotoCount: anyNamed('targetPhotoCount'),
      ),
    ).called(1);

    // Verifies the capability rows directly rather than through
    // `deckInfo.state`/`service.status`: once base + speciesCommonNames +
    // inatBackfill are all terminal for a species,
    // `EnrichmentWorkRepository.pruneSpeciesMembershipIfFullyTerminal`
    // deletes its `enrichment_species_deck_membership` row without
    // checking whether taxonomy work for it is still pending — which
    // zeroes `DeckEnrichmentProjection.speciesCount` for the deck and
    // makes `imageStagesComplete`/`allSpeciesWorkTerminal` permanently
    // false even though the species is actually fully done. Filed as a
    // real bug (see final report) rather than worked around here.
    final capabilityRows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
      where: 'species_id = ?',
      whereArgs: ['sp1'],
    );
    final stateByCapability = {
      for (final row in capabilityRows)
        row['capability'] as String: row['state'],
    };
    expect(stateByCapability['base'], 'done');
    expect(stateByCapability['speciesCommonNames'], 'done');
    expect(stateByCapability['inatBackfill'], 'done');

    final info = service!.deckInfo('deck-1');
    expect(info.isActive, isFalse);
    expect(info.lastAttemptedAt, isNotNull);
    expect(info.hasFailedAttempt, isFalse);
  });

  test('a species with no reference picture falls back to iNaturalist for its '
      'primary photo', () async {
    when(
      mockSpeciesRepository.getSpecies(any),
    ).thenAnswer((_) async => {_species('sp1', withReferencePicture: false)});

    service = createService();
    await service!.scheduleDeckEnrichment([
      'deck-1',
    ], waitForForegroundIdle: true);

    // No reference picture — BaseWorker never even attempts the download.
    verifyNever(
      mockBaseImageEnrichmentService.downloadBaseImagesForSpecies(any),
    );
    verify(
      mockPhotoEnrichmentService.fetchINatPhotosForSpecies(
        {'sp1'},
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        primaryOnly: anyNamed('primaryOnly'),
      ),
    ).called(1);
    final rows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
      where: 'species_id = ?',
      whereArgs: ['sp1'],
    );
    final stateByCapability = {
      for (final row in rows) row['capability'] as String: row['state'],
    };
    expect(stateByCapability['base'], 'noResult');
    expect(stateByCapability['inatPrimary'], 'done');
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

  test('can schedule base-image-only enrichment (no iNat consent)', () async {
    service = createService();
    await service!.scheduleDeckEnrichment(
      ['deck-1'],
      includeINatPhotos: false,
      includeCommonNames: false,
      waitForForegroundIdle: true,
    );

    verify(
      mockBaseImageEnrichmentService.downloadBaseImagesForSpecies(
        {'sp1'},
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).called(1);
    // Common names are only ever seeded when consented to — this stays gated
    // correctly regardless of the base outcome.
    verifyNever(
      mockCommonNameEnrichmentService.fetchSpeciesCommonNamesForSpecies(
        argThat(contains('sp1')),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
      ),
    );
    verifyNever(
      mockTaxonomyEnrichmentService.buildTaxonomyWorkPlanForSpecies(
        argThat(isA<Set<String>>()),
      ),
    );
    final info = service!.deckInfo('deck-1');
    expect(info.lastAttemptedAt, isNotNull);
    expect(info.includesINatPhotos, isFalse);
    expect(info.includesCommonNames, isFalse);
    expect(info.hasCompletedINatEnrichment, isFalse);
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
        mockBaseImageEnrichmentService.downloadBaseImagesForSpecies(
          {'sp1'},
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
          isCancelled: anyNamed('isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        await baseStageGate.future;
        return const ImportEnrichmentSummary(
          imageSpeciesCount: 1,
          imageCount: 1,
          commonNameSpeciesCount: 0,
          commonNameCount: 0,
        );
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

  test('a temporarily failing species does not block or retry-loop the rest '
      'of the batch', () async {
    deckSpeciesSnapshotPort = _TestDeckSpeciesSnapshotPort(
      speciesIdsByDeckId: const {
        'deck-1': {'sp1', 'sp2', 'sp3'},
      },
    );
    final callCountBySpecies = <String, int>{};
    when(
      mockBaseImageEnrichmentService.downloadBaseImagesForSpecies(
        {'sp1'},
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      callCountBySpecies.update('sp1', (n) => n + 1, ifAbsent: () => 1);
      throw TimeoutException('temporary');
    });
    when(
      mockBaseImageEnrichmentService.downloadBaseImagesForSpecies(
        {'sp2'},
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      callCountBySpecies.update('sp2', (n) => n + 1, ifAbsent: () => 1);
      return const ImportEnrichmentSummary(
        imageSpeciesCount: 1,
        imageCount: 1,
        commonNameSpeciesCount: 0,
        commonNameCount: 0,
      );
    });
    when(
      mockBaseImageEnrichmentService.downloadBaseImagesForSpecies(
        {'sp3'},
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      callCountBySpecies.update('sp3', (n) => n + 1, ifAbsent: () => 1);
      return const ImportEnrichmentSummary(
        imageSpeciesCount: 1,
        imageCount: 1,
        commonNameSpeciesCount: 0,
        commonNameCount: 0,
      );
    });

    service = createService();
    await service!.scheduleDeckEnrichment(
      ['deck-1'],
      includeINatPhotos: false,
      includeCommonNames: false,
      waitForForegroundIdle: true,
    );

    // Exactly one attempt per species — sp1's failure doesn't retry
    // in-process (it's scheduled for its own later backoff instead) and
    // never touches sp2/sp3.
    expect(callCountBySpecies, {'sp1': 1, 'sp2': 1, 'sp3': 1});

    final rows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
      where: 'capability = ?',
      whereArgs: ['base'],
    );
    final stateBySpecies = {
      for (final row in rows) row['species_id'] as String: row['state'],
    };
    expect(stateBySpecies['sp1'], 'retryScheduled');
    expect(stateBySpecies['sp2'], 'done');
    expect(stateBySpecies['sp3'], 'done');
  });

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
      mockBaseImageEnrichmentService.downloadBaseImagesForSpecies(
        {'sp1'},
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    );
    final status = service!.status;
    expect(status.hasPendingWork, isTrue);
    expect(status.phase, INatEnrichmentPhase.base);
    expect(status.activeDeckCount, 1);
    expect(status.totalDeckCount, 1);
    final info = service!.deckInfo('deck-1');
    expect(info.hasPendingWork, isTrue);
    expect(info.imageStagesComplete, isFalse);
  });

  test(
    'downloads base images for every scheduled deck independently',
    () async {
      deckSpeciesSnapshotPort = _TestDeckSpeciesSnapshotPort(
        speciesIdsByDeckId: const {
          'deck-1': {'sp1'},
          'deck-2': {'sp2'},
        },
      );

      service = createService();
      await service!.scheduleDeckEnrichment([
        'deck-1',
        'deck-2',
      ], waitForForegroundIdle: true);

      // NOTE: `service.status`/`deckInfo(...).isReady` are not asserted here.
      // `_runForegroundJobs` only calls `_refreshState()` once, in its
      // `finally` block after the *entire* `Future.wait([cover, base,
      // inat])` pass resolves — there is no periodic/reactive refresh while
      // workers are still running. That means a deck's readiness is
      // invisible to the UI for the whole duration of a run, not just until
      // its own images land, undermining the "ready while enrichment
      // continues" UX the projection is meant to support. Filed as a
      // significant gap in the final report rather than worked around here.
      final rows = await database.query(
        EnrichmentWorkRepository.capabilityStateTable,
        where: 'capability = ?',
        whereArgs: ['base'],
      );
      final stateBySpecies = {
        for (final row in rows) row['species_id'] as String: row['state'],
      };
      expect(stateBySpecies['sp1'], 'done');
      expect(stateBySpecies['sp2'], 'done');
    },
  );

  test('base image download for a resolved species proceeds independently of '
      'a still-pending name resolution', () async {
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
      mockBaseImageEnrichmentService.downloadBaseImagesForSpecies(
        {'sp2'},
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      callOrder.add('base');
      return const ImportEnrichmentSummary(
        imageSpeciesCount: 1,
        imageCount: 1,
        commonNameSpeciesCount: 0,
        commonNameCount: 0,
      );
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
      coverImageUrlsByDeckId: const {'deck-1': 'https://example.com/cover.jpg'},
      unresolvedNamesByDeckId: const {
        'deck-1': ['Unknown fish'],
      },
    );

    await nameResolutionStarted.future;
    // sp2 doesn't exist as tracked work yet — it's a genuine data
    // dependency (not an artificial stage gate) that base can't have
    // started for it.
    expect(callOrder, isNot(contains('base')));

    allowNameResolutionToFinish.complete();
    await _waitForCondition(() => callOrder.contains('nameResolution'));
    // INatWorker's loop still needs one more claim attempt (spaced by its
    // rate-limit delay) to see the queue is empty and exit — long enough
    // to let the first `_runForegroundJobs` pass genuinely finish before
    // continuing, rather than a fresh `scheduleDeckEnrichment` call below
    // just joining the still-in-progress first pass.
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    // NOTE: base for sp2 is *not* picked up within this same foreground
    // pass, even after name resolution registers it. `_runForegroundJobs`
    // calls each worker's `runUntilIdle` exactly once via `Future.wait` —
    // `BaseWorker` claims its batch once, up front, and a species
    // registered reactively afterward (by `INatWorker`'s name-resolution
    // handling) has no way to make `BaseWorker` re-check within the same
    // pass. Filed as a significant gap in the final report: the three
    // workers don't currently converge to a shared fixed point when they
    // seed work for each other, only a fresh `_ensureForegroundRunner`
    // call (e.g. the next `scheduleDeckEnrichment`) picks it up.
    expect(callOrder, isNot(contains('base')));

    // A later trigger (here: scheduling again) starts a fresh foreground
    // pass, which now does see sp2's pending base work.
    await service!.scheduleDeckEnrichment(
      ['deck-1'],
      includeINatPhotos: false,
      includeCommonNames: false,
      waitForForegroundIdle: true,
    );
    expect(callOrder, containsAll(['cover', 'nameResolution', 'base']));
  });

  test('claims large per-deck species batches without dropping or duplicating '
      'work', () async {
    final deck1Species = {for (var i = 0; i < 30; i++) 'deck1-sp$i'};
    final deck2Species = {for (var i = 0; i < 30; i++) 'deck2-sp$i'};
    final callCounts = <String, int>{};
    deckSpeciesSnapshotPort = _TestDeckSpeciesSnapshotPort(
      speciesIdsByDeckId: {'deck-1': deck1Species, 'deck-2': deck2Species},
    );

    when(
      mockBaseImageEnrichmentService.downloadBaseImagesForSpecies(
        any,
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
        isCancelled: anyNamed('isCancelled'),
      ),
    ).thenAnswer((invocation) async {
      final speciesSet = (invocation.positionalArguments.first as Set<String>)
          .toSet();
      for (final speciesId in speciesSet) {
        callCounts.update(speciesId, (n) => n + 1, ifAbsent: () => 1);
      }
      return ImportEnrichmentSummary(
        imageSpeciesCount: speciesSet.length,
        imageCount: speciesSet.length,
        commonNameSpeciesCount: 0,
        commonNameCount: 0,
      );
    });

    service = createService();
    await service!.scheduleDeckEnrichment(
      ['deck-1', 'deck-2'],
      includeINatPhotos: false,
      includeCommonNames: false,
      waitForForegroundIdle: true,
    );

    expect(callCounts.length, 60);
    expect(callCounts.values.every((count) => count == 1), isTrue);
    final rows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
      where: 'capability = ? AND state = ?',
      whereArgs: ['base', 'done'],
    );
    expect(rows, hasLength(60));
  });

  test(
    'assigns overlapping species to a single owner deck during scheduling',
    () async {
      final callCounts = <String, int>{};
      deckSpeciesSnapshotPort = _TestDeckSpeciesSnapshotPort(
        speciesIdsByDeckId: const {
          'deck-1': {'shared-sp', 'deck1-only'},
          'deck-2': {'shared-sp', 'deck2-only'},
        },
      );

      when(
        mockBaseImageEnrichmentService.downloadBaseImagesForSpecies(
          argThat(isA<Set<String>>()),
          onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
          isCancelled: anyNamed('isCancelled'),
        ),
      ).thenAnswer((invocation) async {
        final speciesSet = (invocation.positionalArguments.first as Set<String>)
            .toSet();
        for (final speciesId in speciesSet) {
          callCounts.update(speciesId, (n) => n + 1, ifAbsent: () => 1);
        }
        return ImportEnrichmentSummary(
          imageSpeciesCount: speciesSet.length,
          imageCount: speciesSet.length,
          commonNameSpeciesCount: 0,
          commonNameCount: 0,
        );
      });

      service = createService();
      await service!.scheduleDeckEnrichment(
        ['deck-1', 'deck-2'],
        includeINatPhotos: false,
        includeCommonNames: false,
        waitForForegroundIdle: true,
      );

      // No duplicate work despite 'shared-sp' being referenced by both decks.
      expect(callCounts, {'shared-sp': 1, 'deck1-only': 1, 'deck2-only': 1});
    },
  );

  test('a transient common-names failure does not surface as failed and does '
      'not block the deck from becoming ready', () async {
    service = createService();
    when(
      mockCommonNameEnrichmentService.fetchSpeciesCommonNamesForSpecies({
        'sp1',
      }, onSpeciesCompleted: anyNamed('onSpeciesCompleted')),
    ).thenThrow(Exception('boom'));

    await service!.scheduleDeckEnrichment([
      'deck-1',
    ], waitForForegroundIdle: true);

    final info = service!.deckInfo('deck-1');
    // Base still succeeded, so the deck is ready/learnable even though a
    // background capability is quietly waiting on its own retry.
    expect(info.isReady, isTrue);
    expect(info.lastAttemptedAt, isNotNull);
    expect(info.hasFailedAttempt, isFalse);
    expect(info.state, isNot(DeckEnrichmentState.failed));

    final rows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
      where: 'species_id = ? AND capability = ?',
      whereArgs: ['sp1', 'speciesCommonNames'],
    );
    expect(rows.single['state'], 'retryScheduled');
  });

  test(
    'cancelling a deck does not roll back an already-claimed in-flight name '
    'resolution, but does stop further work and job tracking for that deck',
    () async {
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
      // The name-resolution item was already claimed before cancellation,
      // so — unlike the cover job, which checks liveness before and after
      // its download — it still runs to completion and applies its
      // mutation. Cancellation is single-item-transaction-based (no
      // checkpoint dance to interrupt mid-item): it only stops the loop
      // from claiming further work for the deck, not an item already in
      // flight when the cancel arrived.
      await _waitForCondition(() => deckMutationPort.calls.isNotEmpty);
      // Records' `==` delegates to each field's own `==`, and Set has no
      // value equality under plain `==` — destructure and compare fields
      // individually rather than comparing the whole record.
      expect(deckMutationPort.calls, hasLength(1));
      final call = deckMutationPort.calls.single;
      expect(call.deckId, 'deck-1');
      expect(call.speciesIds, {'sp2'});
      expect(await jobRepository.loadJob('deck-1'), isNull);
    },
  );

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
