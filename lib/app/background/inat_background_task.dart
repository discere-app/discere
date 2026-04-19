import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/locale_place_mapping_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/service/enrichment_background_scheduler.dart';
import 'package:discere/enrichment/service/enrichment_job_executor.dart';
import 'package:discere/enrichment/service/enrichment_job_ports.dart';
import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/enrichment/service/inat_name_resolution_service.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/shared/util/logging_http_client.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

class BackgroundEnrichmentRuntime {
  static final _log = Logger.forType(BackgroundEnrichmentRuntime);
  final EnrichmentJobRepository _jobRepository;
  final EnrichmentJobExecutor _executor;
  final EnrichmentBackgroundScheduler _scheduler;
  final NotificationService _notificationService;

  const BackgroundEnrichmentRuntime._(
    this._jobRepository,
    this._executor,
    this._scheduler,
    this._notificationService,
  );

  static Future<BackgroundEnrichmentRuntime> create() async {
    WidgetsFlutterBinding.ensureInitialized();
    _log.debug('Create background enrichment runtime');
    final notificationService = NotificationService();
    await notificationService.initNotification();

    final localePlaceMappingRepository = LocalePlaceMappingRepository();
    final localeMapping = await localePlaceMappingRepository
        .getForCurrentLocale();
    final speciesRepository = SpeciesRepository(localeMapping: localeMapping);
    final deckRepository = DeckRepository();
    final flashcardStatRepository = FlashcardStatRepository();
    final sharedHttpClient = LoggingHttpClient(http.Client());
    final imageService = ImageService(client: sharedHttpClient);
    final iNatService = INaturalistService(client: sharedHttpClient);
    final iNatCacheRepository = INatPhotoCacheRepository();
    final externalIdRepository = ExternalIdRepository();
    final externalIdCacheRepository = ExternalIdCacheRepository();
    final enrichmentService = EnrichmentService(
      speciesRepository,
      imageService,
      iNatService,
      iNatCacheRepository,
      externalIdRepository,
      externalIdCacheRepository,
    );
    final nameResolutionService = INatNameResolutionService(
      speciesRepository,
      iNatService,
    );
    final jobRepository = EnrichmentJobRepository();
    final executor = EnrichmentJobExecutor(
      enrichmentService,
      jobRepository,
      deckCoverStore: _BackgroundDeckCoverStore(deckRepository),
      imageService: imageService,
      nameResolutionPort: nameResolutionService,
      deckSpeciesMutationPort: _BackgroundDeckSpeciesMutationPort(
        deckRepository,
        flashcardStatRepository,
      ),
      onStateChanged: () async {
        final jobs = await jobRepository.loadAllJobs();
        final status = deriveEnrichmentStatus(jobs);
        if (status.isRunning) {
          await notificationService.showEnrichmentProgress(status);
        } else {
          await notificationService.cancelEnrichmentProgress();
        }
      },
    );
    final scheduler = WorkmanagerEnrichmentBackgroundScheduler(
      callbackDispatcher: inatEnrichmentBackgroundDispatcher,
    );
    await scheduler.initialize();
    return BackgroundEnrichmentRuntime._(
      jobRepository,
      executor,
      scheduler,
      notificationService,
    );
  }

  Future<bool> run() async {
    _log.debug('Background runtime run start');
    try {
      return await _executor.processUntilIdle(
        owner: 'background-runner',
        runnerKind: EnrichmentRunnerKind.background,
        maxStageRuns: 18,
      );
    } finally {
      final jobs = await _jobRepository.loadAllJobs();
      final status = deriveEnrichmentStatus(jobs);
      if (status.isRunning) {
        await _notificationService.showEnrichmentProgress(status);
      } else {
        await _notificationService.cancelEnrichmentProgress();
      }
    }
  }

  Future<bool> hasPendingWork() => _jobRepository.hasPendingWork();

  Future<void> scheduleNextRun() {
    _log.debug('Background runtime schedules next run');
    return _scheduler.scheduleProcessing();
  }
}

class _BackgroundDeckCoverStore implements DeckCoverStorePort {
  static final _log = Logger.forType(_BackgroundDeckCoverStore);
  final DeckRepository _deckRepository;

  const _BackgroundDeckCoverStore(this._deckRepository);

  @override
  Future<void> updateDeckCoverPath(String deckId, String localPath) async {
    final decks = await _deckRepository.getDecksByIds({deckId});
    if (decks.isEmpty) {
      _log.debug('Skip background cover update for deleted deck deck=$deckId');
      return;
    }

    final deck = decks.first;
    if (deck.coverImagePath == localPath) return;
    deck.coverImagePath = localPath;
    await _deckRepository.insertDeck(deck);
  }
}

class _BackgroundDeckSpeciesMutationPort implements DeckSpeciesMutationPort {
  static final _log = Logger.forType(_BackgroundDeckSpeciesMutationPort);
  final DeckRepository _deckRepository;
  final FlashcardStatRepository _flashcardStatRepository;

  const _BackgroundDeckSpeciesMutationPort(
    this._deckRepository,
    this._flashcardStatRepository,
  );

  @override
  Future<void> addSpeciesToDeck(String deckId, Set<String> speciesIds) async {
    if (speciesIds.isEmpty) return;
    final decks = await _deckRepository.getDecksByIds({deckId});
    if (decks.isEmpty) {
      _log.debug(
        'Skip background species mutation for deleted deck deck=$deckId '
        'count=${speciesIds.length}',
      );
      return;
    }
    final stats = speciesIds
        .map((id) => FlashcardStat(speciesId: id, deckId: deckId))
        .toSet();
    await _flashcardStatRepository.insertOrUpdateFlashcardStats(stats);
  }
}

@pragma('vm:entry-point')
void inatEnrichmentBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    Logger.debug('INatBackgroundTask', 'Execute task=$task');
    final runner = await BackgroundEnrichmentRuntime.create();
    try {
      final processed = await runner.run();
      if (await runner.hasPendingWork()) {
        await runner.scheduleNextRun();
      }
      Logger.debug(
        'INatBackgroundTask',
        'Task complete processed=$processed pending=${await runner.hasPendingWork()}',
      );
      return processed || !(await runner.hasPendingWork());
    } catch (error) {
      Logger.warn('INatBackgroundTask', 'Background enrichment failed: $error');
      return false;
    }
  });
}
