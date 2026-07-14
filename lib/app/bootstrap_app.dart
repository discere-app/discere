import 'dart:async';
import 'package:discere/app/background/inat_background_task.dart';
import 'package:discere/app/main_screen_page.dart';
import 'package:discere/shared/service/navigation_tab_service.dart';
import 'package:discere/application/species_media/species_media_service.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/locale_place_mapping_repository.dart';
import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/catalog/repository/source_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/service/local_species_image_service.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/enrichment/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/service/enrichment_background_scheduler.dart';
import 'package:discere/enrichment/service/enrichment_foreground_service_keeper.dart';
import 'package:discere/enrichment/service/enrichment_job_ports.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/enrichment/service/inat_name_resolution_service.dart';
import 'package:discere/enrichment/service/species_photo_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/repository/daily_count_repository.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/deck_serialization_worker.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/service/fsrs_service.dart';
import 'package:discere/learning/service/import_export_service.dart';
import 'package:discere/learning/service/remote_deck_service.dart';
import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/enrichment_completion_diagnostics_persistence.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/log_diagnostics_persistence.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/shared/util/logging_http_client.dart';
import 'package:discere/theme/ocean_theme/ocean_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BootstrapApp extends StatefulWidget {
  final NotificationService? notificationService;
  final bool processEnrichmentJobs;

  const BootstrapApp({
    super.key,
    this.notificationService,
    this.processEnrichmentJobs = true,
  });

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  late Future<_BootstrapResult> _bootstrapFuture;
  bool _startedDeferred = false;

  static const _bootstrapTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _setupCriticalServices(
      notificationService: widget.notificationService,
      processEnrichmentJobs: widget.processEnrichmentJobs,
      onStatusChanged: _updateSplashStatus,
    ).timeout(
      _bootstrapTimeout,
      onTimeout: () => throw TimeoutException(
        'Bootstrap did not complete within ${_bootstrapTimeout.inSeconds}s. '
        'A background isolate may still hold a database lock.',
        _bootstrapTimeout,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  void _updateSplashStatus(String status) {
    if (!mounted) return;
    setState(() {
      _status = status;
    });
  }

  String _status = 'Preparing app…';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapResult>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _BootstrapShell(status: _status);
        }
        if (snapshot.hasError) {
          return _BootstrapErrorShell(
            error: snapshot.error,
            onRetry: () {
              setState(() {
                _status = 'Retrying…';
                _startedDeferred = false;
                _bootstrapFuture = _setupCriticalServices(
                  notificationService: widget.notificationService,
                  processEnrichmentJobs: widget.processEnrichmentJobs,
                  onStatusChanged: _updateSplashStatus,
                ).timeout(
                  _bootstrapTimeout,
                  onTimeout: () => throw TimeoutException(
                    'Bootstrap did not complete within '
                    '${_bootstrapTimeout.inSeconds}s. A background isolate '
                    'may still hold a database lock.',
                    _bootstrapTimeout,
                  ),
                );
              });
            },
          );
        }

        final result = snapshot.data!;
        if (!_startedDeferred) {
          _startedDeferred = true;
          unawaited(result.startDeferred());
        }
        return MultiProvider(
          providers: result.providers,
          child: const FlashcardApp(),
        );
      },
    );
  }
}

Future<_BootstrapResult> _setupCriticalServices({
  NotificationService? notificationService,
  bool processEnrichmentJobs = true,
  void Function(String status)? onStatusChanged,
}) async {
  Logger.debug('bootstrap', 'critical setup: starting');

  // Cancel any background-isolate enrichment task before touching the user
  // database. A stale background isolate may still hold a writer lock that
  // would otherwise hang every subsequent user-DB access during startup.
  final backgroundScheduler = WorkmanagerEnrichmentBackgroundScheduler(
    callbackDispatcher: inatEnrichmentBackgroundDispatcher,
  );
  await backgroundScheduler.cancelAllPendingProcessing();

  final foregroundServiceKeeper = FlutterForegroundTaskEnrichmentKeeper();
  final networkAvailability = ConnectivityNetworkAvailability();

  onStatusChanged?.call('Loading preferences…');
  final sharedPreferences = await SharedPreferences.getInstance();
  final logDiagnosticsPersistence = LogDiagnosticsPersistence(
    sharedPreferences,
  );
  await logDiagnosticsPersistence.initialize(defaultEnabled: false);
  final enrichmentCompletionDiagnostics =
      EnrichmentCompletionDiagnosticsPersistence(sharedPreferences);
  await enrichmentCompletionDiagnostics.initialize(defaultEnabled: false);

  onStatusChanged?.call('Preparing reference database…');
  await DatabaseHelper.prepareReferenceDb();

  onStatusChanged?.call('Loading locale mapping…');
  final localePlaceMappingRepository = LocalePlaceMappingRepository();
  final localeMapping = await localePlaceMappingRepository
      .getForCurrentLocale();

  onStatusChanged?.call('Building services…');
  final flashcardStatRepository = FlashcardStatRepository();
  final speciesRepository = SpeciesRepository(localeMapping: localeMapping);
  final deckRepository = DeckRepository();
  final sourceRepository = SourceRepository();

  final activeNotificationService =
      notificationService ??
      NotificationService(preferences: sharedPreferences);

  final sharedHttpClient = LoggingHttpClient(http.Client());
  final imageService = ImageService(client: sharedHttpClient);
  final iNatService = INaturalistService(client: sharedHttpClient);
  final serializationWorker = const DeckSerializationWorker();
  final iNatCacheRepository = INatPhotoCacheRepository();
  final externalIdRepository = ExternalIdRepository();
  final externalIdCacheRepository = ExternalIdCacheRepository();
  final searchRepository = SearchRepository(
    iNatService: iNatService,
    localeMapping: localeMapping,
  );
  final speciesPhotoService = SpeciesPhotoService(
    iNatCacheRepository,
    iNatService: iNatService,
    externalIdRepository: externalIdRepository,
    externalIdCacheRepository: externalIdCacheRepository,
  );
  final localSpeciesImageService = LocalSpeciesImageService(imageService);
  final speciesMediaService = SpeciesMediaService(
    speciesRepository,
    speciesPhotoService,
    localSpeciesImageService,
  );
  final userPreferencesService = UserPreferencesService(sharedPreferences);
  final fsrsService = FsrsService();
  final deckConfigRepository = DeckConfigRepository();
  final dailyCountRepository = DailyCountRepository();
  final enrichmentService = EnrichmentService(
    speciesRepository,
    imageService,
    iNatService,
    iNatCacheRepository,
    externalIdRepository,
    externalIdCacheRepository,
  );
  final deckService = DecksService(
    deckRepository,
    flashcardStatRepository,
    speciesRepository,
    imageService,
    deckConfigRepository: deckConfigRepository,
  );
  final deckImportService = DeckImportService(
    deckService,
    speciesRepository,
    iNatService: iNatService,
    serializationWorker: serializationWorker,
  );
  final nameResolutionService = INatNameResolutionService(
    speciesRepository,
    iNatService,
  );
  final iNatEnrichmentQueueService = INatEnrichmentQueueService(
    enrichmentService,
    deckSpeciesSnapshotPort: _DeckSpeciesSnapshotAdapter(deckService),
    deckCoverStore: _DeckCoverStoreAdapter(deckService),
    imageService: imageService,
    nameResolutionPort: nameResolutionService,
    deckSpeciesMutationPort: _DeckSpeciesMutationAdapter(deckService),
    notificationService: activeNotificationService,
    backgroundScheduler: backgroundScheduler,
    foregroundServiceKeeper: foregroundServiceKeeper,
    networkAvailability: networkAvailability,
    unresolvedNamesObserver: const _BootstrapLoggingUnresolvedNamesObserver(),
    autoInitialize: false,
    processJobs: processEnrichmentJobs,
  );
  deckService.onDeckDeleted = iNatEnrichmentQueueService.cancelDeckEnrichment;
  deckService.onDeckCreated = (deckId) {
    deckConfigRepository.save(
      DeckConfig(
        deckId: deckId,
        desiredRetention: userPreferencesService.defaultDesiredRetention,
      ),
    );
  };

  final flashcardService = FlashcardService(
    fsrsService,
    flashcardStatRepository,
    activeNotificationService,
    speciesMediaService,
    deckConfigRepository: deckConfigRepository,
    dailyCountRepository: dailyCountRepository,
    userPreferencesService: userPreferencesService,
  );

  final favoriteService = FavoriteService(sharedPreferences);
  final watchlistService = WatchlistService(sharedPreferences);
  final languageService = LanguageService(sharedPreferences);

  final remoteDeckService = RemoteDeckService(
    client: sharedHttpClient,
    serializationWorker: serializationWorker,
  );
  final importExportService = ImportExportService(
    deckService,
    serializationWorker: serializationWorker,
  );
  final sourceService = SourceService(sourceRepository);

  final navigationTabService = NavigationTabService();

  final providers = <SingleChildWidget>[
    ChangeNotifierProvider<NavigationTabService>.value(
      value: navigationTabService,
    ),
    Provider<INaturalistService>.value(value: iNatService),
    Provider<ImageService>.value(value: imageService),
    Provider<EnrichmentService>.value(value: enrichmentService),
    Provider<FlashcardService>.value(value: flashcardService),
    Provider<SpeciesMediaService>.value(value: speciesMediaService),
    Provider<NotificationService>.value(value: activeNotificationService),
    Provider<SearchRepository>.value(value: searchRepository),
    Provider<LocalePlaceMappingRepository>.value(
      value: localePlaceMappingRepository,
    ),
    ChangeNotifierProvider<DecksService>.value(value: deckService),
    ChangeNotifierProvider<INatEnrichmentQueueService>.value(
      value: iNatEnrichmentQueueService,
    ),
    Provider<ImportExportService>.value(value: importExportService),
    Provider<DeckImportService>.value(value: deckImportService),
    Provider<RemoteDeckService>.value(value: remoteDeckService),
    ChangeNotifierProvider<FavoriteService>.value(value: favoriteService),
    ChangeNotifierProvider<WatchlistService>.value(value: watchlistService),
    ChangeNotifierProvider<LanguageService>.value(value: languageService),
    Provider<SourceService>.value(value: sourceService),
    ChangeNotifierProvider<UserPreferencesService>.value(
      value: userPreferencesService,
    ),
  ];

  return _BootstrapResult(
    providers: providers,
    startDeferred: () async {
      Logger.debug('bootstrap', 'deferred setup: starting');
      await activeNotificationService.initNotification();
      await iNatEnrichmentQueueService.initialize();
      Logger.debug('bootstrap', 'deferred setup: done');
    },
  );
}

class FlashcardApp extends StatelessWidget {
  const FlashcardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageService>(
      builder: (context, languageService, child) {
        return MaterialApp(
          locale: languageService.getLanguage().toLocale(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: oceanTheme,
          home: const MainScreenPage(),
        );
      },
    );
  }
}

class _BootstrapResult {
  final List<SingleChildWidget> providers;
  final Future<void> Function() startDeferred;

  const _BootstrapResult({
    required this.providers,
    required this.startDeferred,
  });
}

class _BootstrapShell extends StatelessWidget {
  final String status;

  const _BootstrapShell({required this.status});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: oceanTheme,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BootstrapErrorShell extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _BootstrapErrorShell({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: oceanTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final loc = AppLocalizations.of(context)!;
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.bootstrapErrorTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text('$error', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: onRetry, child: Text(loc.commonRetry)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DeckSpeciesSnapshotAdapter implements DeckSpeciesSnapshotPort {
  final DecksService _deckService;

  const _DeckSpeciesSnapshotAdapter(this._deckService);

  @override
  Future<Set<String>> loadSpeciesIdsForDecks(Set<String> deckIds) {
    return _deckService.getSpeciesIdsByDeckIds(deckIds);
  }
}

class _DeckCoverStoreAdapter implements DeckCoverStorePort {
  final DecksService _deckService;

  const _DeckCoverStoreAdapter(this._deckService);

  @override
  Future<void> updateDeckCoverPath(String deckId, String localPath) {
    return _deckService.updateDeckCoverPath(deckId, localPath);
  }
}

class _DeckSpeciesMutationAdapter implements DeckSpeciesMutationPort {
  final DecksService _deckService;

  const _DeckSpeciesMutationAdapter(this._deckService);

  @override
  Future<void> addSpeciesToDeck(String deckId, Set<String> speciesIds) {
    return _deckService.addSpeciesToDeck(deckId, speciesIds);
  }
}

class _BootstrapLoggingUnresolvedNamesObserver
    implements UnresolvedNamesObserverPort {
  const _BootstrapLoggingUnresolvedNamesObserver();

  @override
  void onNamesUnresolved(String deckId, List<String> unresolvedNames) {
    Logger.debug(
      'bootstrap',
      'Persisted ${unresolvedNames.length} unresolved names for deck=$deckId',
    );
  }
}
