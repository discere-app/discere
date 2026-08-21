import 'dart:async';

import 'package:discere/app/bootstrap/bootstrap_error_shell.dart';
import 'package:discere/app/bootstrap/bootstrap_shell.dart';
import 'package:discere/app/bootstrap/reference_db_download_confirm_shell.dart';
import 'package:discere/app/bootstrap/reference_db_download_declined_shell.dart';
import 'package:discere/app/bootstrap/reference_db_download_error_shell.dart';
import 'package:discere/app/bootstrap/reference_db_download_shell.dart';
import 'package:discere/app/main_screen_page.dart';
import 'package:discere/app/wiring/catalog_wiring.dart';
import 'package:discere/app/wiring/enrichment_wiring.dart';
import 'package:discere/app/wiring/learning_wiring.dart';
import 'package:discere/catalog/repository/locale_place_mapping_repository.dart';
import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/catalog/service/species_inat_metadata_service.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/diagnostics/service/diagnostics_log_file.dart';
import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/diagnostics/service/log_diagnostics_persistence.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/queue/service/enrichment_background_scheduler.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/external/wikipedia/wikipedia_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/learning/service/deck_serialization_worker.dart';
import 'package:discere/learning/service/deck_source_id_backfill_service.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/service/import_export_service.dart';
import 'package:discere/learning/service/remote_deck_service.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/navigation_tab_service.dart';
import 'package:discere/shared/service/network_availability.dart';
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
  static const _bootstrapTimeout = Duration(seconds: 12);

  // Own instance, separate from the one built in _setupCriticalServices() —
  // this one only needs the one-shot isOnWifi() check, runs before that
  // service wiring exists, and is never initialize()d (no stream consumer).
  final _networkAvailability = ConnectivityNetworkAvailability();

  // Constructed here (rather than in _setupCriticalServices(), which runs
  // after _ensureReferenceDb()) so the same keepalive instance covers both
  // the reference-DB download and, later, background enrichment — either can
  // outlast the app being backgrounded. See
  // https://github.com/discere-app/discere/issues/101.
  final _foregroundServiceKeeper = FlutterForegroundTaskKeeper();

  // Plain client, not the LoggingHttpClient built further down in
  // _setupCriticalServices() — the reference-DB check/download runs before
  // that (and before diagnostics/host-cooldown are even wired up).
  late final _referenceDbProvisioner = ReferenceDatabaseProvisioner(
    client: http.Client(),
    networkAvailability: _networkAvailability,
    foregroundServiceKeeper: _foregroundServiceKeeper,
  );

  late Future<_BootstrapResult> _bootstrapFuture;
  double? _downloadProgress;
  int? _downloadSizeBytes;
  ReferenceDbUpdateInfo? _pendingDownloadConfirmation;
  bool _pendingDownloadConfirmationOnWifi = false;
  Completer<bool>? _downloadConfirmationCompleter;
  bool _startedDeferred = false;

  String _status = 'Preparing app…';

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _bootstrap();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  Future<_BootstrapResult> _bootstrap() async {
    try {
      await _ensureReferenceDb();
    } on _ReferenceDbDownloadDeferred {
      rethrow;
    } catch (e) {
      // Wrapped so build() can show a download-specific retry screen
      // instead of the generic bootstrap error shell.
      throw _ReferenceDbUnavailable(e);
    }
    return _setupCriticalServices(
      notificationService: widget.notificationService,
      processEnrichmentJobs: widget.processEnrichmentJobs,
      referenceDbProvisioner: _referenceDbProvisioner,
      foregroundServiceKeeper: _foregroundServiceKeeper,
      onStatusChanged: _updateSplashStatus,
    ).timeout(
      _bootstrapTimeout,
      onTimeout: () => throw TimeoutException(
        'Bootstrap did not complete within ${_bootstrapTimeout.inSeconds}s. '
        'A background isolate may still hold a database lock.',
        _bootstrapTimeout,
      ),
    );
  }

  /// Fast path (usable local copy already present): never blocks on
  /// network — the existing copy is used immediately and refreshed silently
  /// in the background for next launch. Slow path (first launch, app data
  /// cleared, or the cached copy's schema is too old for this app build):
  /// blocks with visible progress, since there is nothing usable to fall
  /// back to yet. This is why it runs outside `_bootstrapTimeout`, which
  /// assumes only local disk/IPC work, not a multi-hundred-MB download.
  ///
  /// The user is always asked to confirm before this multi-hundred-MB
  /// download starts — on Wi-Fi just to be informed of the size, off Wi-Fi
  /// also to consent to spending mobile data. Declining throws
  /// [_ReferenceDbDownloadDeferred] rather than proceeding.
  Future<void> _ensureReferenceDb() async {
    final hasUsableLocalCopy = await _referenceDbProvisioner
        .hasUsableLocalCopy();
    if (hasUsableLocalCopy) {
      unawaited(_referenceDbProvisioner.ensureUpToDateInBackground());
      return;
    }

    final updateInfo = await _referenceDbProvisioner.checkForUpdate();
    final onWifi = await _networkAvailability.isOnWifi();
    setState(() {
      _pendingDownloadConfirmation = updateInfo;
      _pendingDownloadConfirmationOnWifi = onWifi;
    });
    _downloadConfirmationCompleter = Completer<bool>();
    final proceed = await _downloadConfirmationCompleter!.future;
    if (mounted) setState(() => _pendingDownloadConfirmation = null);
    if (!proceed) {
      throw const _ReferenceDbDownloadDeferred();
    }

    setState(() {
      _downloadProgress = 0;
      _downloadSizeBytes = updateInfo.compressedSizeBytes;
    });
    await _referenceDbProvisioner.downloadAndInstall(
      updateInfo,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() => _downloadProgress = progress);
      },
    );
  }

  void _confirmDownload(bool proceed) {
    _downloadConfirmationCompleter?.complete(proceed);
  }

  void _retry() {
    setState(() {
      _downloadProgress = null;
      _downloadSizeBytes = null;
      _pendingDownloadConfirmation = null;
      _downloadConfirmationCompleter = null;
      _status = 'Retrying…';
      _startedDeferred = false;
      _bootstrapFuture = _bootstrap();
    });
  }

  void _updateSplashStatus(String status) {
    // Logged unconditionally (not gated on `mounted`) so a phase that starts
    // but never reports the next one — e.g. an openDatabase() call stuck on
    // a stale lock — is visible in logs even if the splash widget itself is
    // no longer attached to observe the UI update.
    Logger.debug('bootstrap', 'Phase: $status');
    if (!mounted) return;
    setState(() {
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapResult>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          final pendingConfirmation = _pendingDownloadConfirmation;
          if (pendingConfirmation != null) {
            return ReferenceDbDownloadConfirmShell(
              sizeBytes: pendingConfirmation.compressedSizeBytes,
              onWifi: _pendingDownloadConfirmationOnWifi,
              onDownloadNow: () => _confirmDownload(true),
              onNotNow: () => _confirmDownload(false),
            );
          }
          if (_downloadProgress != null) {
            return ReferenceDbDownloadShell(
              progress: _downloadProgress!,
              sizeBytes: _downloadSizeBytes,
            );
          }
          return BootstrapShell(status: _status);
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          if (error is _ReferenceDbDownloadDeferred) {
            return ReferenceDbDownloadDeclinedShell(onRetry: _retry);
          }
          if (error is _ReferenceDbUnavailable) {
            return ReferenceDbDownloadErrorShell(
              error: error.cause,
              onRetry: _retry,
            );
          }
          return BootstrapErrorShell(error: error, onRetry: _retry);
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

class _ReferenceDbUnavailable implements Exception {
  final Object cause;

  const _ReferenceDbUnavailable(this.cause);

  @override
  String toString() => cause.toString();
}

/// Thrown when the user declines to download the reference database over
/// cellular — a deliberate choice to wait for Wi-Fi, not a failure.
class _ReferenceDbDownloadDeferred implements Exception {
  const _ReferenceDbDownloadDeferred();
}

Future<_BootstrapResult> _setupCriticalServices({
  required ReferenceDatabaseProvisioner referenceDbProvisioner,
  required ForegroundServiceKeeper foregroundServiceKeeper,
  NotificationService? notificationService,
  bool processEnrichmentJobs = true,
  void Function(String status)? onStatusChanged,
}) async {
  Logger.debug('bootstrap', 'critical setup: starting');

  final backgroundScheduler = const NoopEnrichmentBackgroundScheduler();

  final networkAvailability = ConnectivityNetworkAvailability();
  // Single shared instances: LocalDiagnostics buffers/queues writes
  // internally and HostCooldownTracker tracks per-host cooldown state, so
  // every consumer needs the same instance rather than one of its own.
  final localDiagnostics = LocalDiagnostics();
  final diagnosticsLogFile = DiagnosticsLogFile();
  final hostCooldownTracker = HostCooldownTracker();

  onStatusChanged?.call('Loading preferences…');
  final referenceDbReady = DatabaseHelper.prepareReferenceDb();
  final sharedPreferences = await SharedPreferences.getInstance();
  final logDiagnosticsPersistence = LogDiagnosticsPersistence(
    sharedPreferences,
    logFile: diagnosticsLogFile,
  );
  await logDiagnosticsPersistence.initialize(defaultEnabled: false);

  onStatusChanged?.call('Preparing reference database…');
  await referenceDbReady;

  onStatusChanged?.call('Loading locale mapping…');
  final localePlaceMappingRepository = LocalePlaceMappingRepository();
  final localeMapping = await localePlaceMappingRepository
      .getForCurrentLocale();

  onStatusChanged?.call('Building services…');
  final activeNotificationService =
      notificationService ??
      NotificationService(preferences: sharedPreferences);
  final sharedHttpClient = LoggingHttpClient(
    http.Client(),
    diagnostics: localDiagnostics,
    hostCooldownTracker: hostCooldownTracker,
  );
  final imageService = ImageService(
    client: sharedHttpClient,
    hostCooldownTracker: hostCooldownTracker,
  );
  final iNatService = INaturalistService(client: sharedHttpClient);
  final wikipediaService = WikipediaService(client: sharedHttpClient);
  final serializationWorker = const DeckSerializationWorker();

  final catalog = buildCatalogServices(
    localeMapping: localeMapping,
    iNatService: iNatService,
    imageService: imageService,
    wikipediaService: wikipediaService,
    sharedPreferences: sharedPreferences,
  );

  final learning = buildLearningDeckServices(
    speciesRepository: catalog.speciesRepository,
    imageService: imageService,
    iNatService: iNatService,
    sharedHttpClient: sharedHttpClient,
    serializationWorker: serializationWorker,
    sharedPreferences: sharedPreferences,
  );

  final enrichment = buildEnrichmentServices(
    speciesRepository: catalog.speciesRepository,
    imageService: imageService,
    iNatService: iNatService,
    externalIdRepository: catalog.externalIdRepository,
    externalIdCacheRepository: catalog.externalIdCacheRepository,
    localSpeciesImageService: catalog.localSpeciesImageService,
    deckService: learning.deckService,
    backgroundScheduler: backgroundScheduler,
    foregroundServiceKeeper: foregroundServiceKeeper,
    networkAvailability: networkAvailability,
    hostCooldownTracker: hostCooldownTracker,
    processEnrichmentJobs: processEnrichmentJobs,
  );

  final userPreferencesService = UserPreferencesService(sharedPreferences);
  learning.deckService.onDeckDeleted =
      enrichment.iNatEnrichmentQueueService.cancelDeckEnrichment;
  learning.deckService.onDeckCreated = (deckId) {
    learning.deckConfigRepository.save(
      DeckConfig(
        deckId: deckId,
        desiredRetention: userPreferencesService.defaultDesiredRetention,
      ),
    );
  };

  final flashcardService = FlashcardService(
    learning.fsrsService,
    learning.flashcardStatRepository,
    activeNotificationService,
    enrichment.speciesMediaService,
    learning.speciesPhotoGapAckRepository,
    deckConfigRepository: learning.deckConfigRepository,
    userPreferencesService: userPreferencesService,
  );

  final languageService = LanguageService(sharedPreferences);
  final navigationTabService = NavigationTabService();

  final providers = <SingleChildWidget>[
    ChangeNotifierProvider<NavigationTabService>.value(
      value: navigationTabService,
    ),
    Provider<INaturalistService>.value(value: iNatService),
    Provider<ImageService>.value(value: imageService),
    Provider<WikipediaService>.value(value: wikipediaService),
    Provider<LocalDiagnostics>.value(value: localDiagnostics),
    Provider<DiagnosticsLogFile>.value(value: diagnosticsLogFile),
    Provider<FlashcardService>.value(value: flashcardService),
    Provider<SpeciesMediaService>.value(value: enrichment.speciesMediaService),
    Provider<NotificationService>.value(value: activeNotificationService),
    Provider<SearchRepository>.value(value: catalog.searchRepository),
    Provider<TaxonomyRepository>.value(value: catalog.taxonomyRepository),
    Provider<LocalePlaceMappingRepository>.value(
      value: localePlaceMappingRepository,
    ),
    ChangeNotifierProvider<DecksService>.value(value: learning.deckService),
    ChangeNotifierProvider<INatEnrichmentQueueService>.value(
      value: enrichment.iNatEnrichmentQueueService,
    ),
    ChangeNotifierProvider<ReferenceDatabaseProvisioner>.value(
      value: referenceDbProvisioner,
    ),
    Provider<ImportExportService>.value(value: learning.importExportService),
    Provider<DeckImportService>.value(value: learning.deckImportService),
    Provider<RemoteDeckService>.value(value: learning.remoteDeckService),
    ChangeNotifierProvider<DeckUpdateService>.value(
      value: learning.deckUpdateService,
    ),
    ChangeNotifierProvider<FavoriteService>.value(
      value: learning.favoriteService,
    ),
    ChangeNotifierProvider<WatchlistService>.value(
      value: catalog.watchlistService,
    ),
    ChangeNotifierProvider<LanguageService>.value(value: languageService),
    Provider<SourceService>.value(value: catalog.sourceService),
    Provider<SpeciesInatMetadataService>.value(
      value: catalog.speciesInatMetadataService,
    ),
    ChangeNotifierProvider<UserPreferencesService>.value(
      value: userPreferencesService,
    ),
  ];

  return _BootstrapResult(
    providers: providers,
    startDeferred: () async {
      Logger.debug('bootstrap', 'deferred setup: starting');
      await activeNotificationService.initNotification();
      await enrichment.iNatEnrichmentQueueService.initialize();
      // DeckSourceIdBackfillService is @Deprecated as a marker for when to
      // delete it (and this call) — see its class doc for the removal plan.
      await DeckSourceIdBackfillService(
        learning.deckRepository,
        learning.remoteDeckService,
      ).runIfNeeded();
      unawaited(learning.deckUpdateService.checkForUpdates());
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
