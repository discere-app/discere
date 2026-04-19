import 'dart:convert';
import 'dart:io';
import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/catalog/repository/source_repository.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/catalog/service/local_species_image_service.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/repository/inat_photo_cache_repository.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:discere/catalog/repository/locale_place_mapping_repository.dart';
import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/application/species_media/species_media_service.dart';
import 'package:discere/enrichment/service/species_photo_service.dart';
import 'package:discere/enrichment/service/enrichment_job_ports.dart';
import 'package:discere/learning/service/favorite_service.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/learning/service/import_export_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/service/fsrs_service.dart';
import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/app/background/inat_background_task.dart';
import 'package:discere/enrichment/service/enrichment_background_scheduler.dart';
import 'package:discere/enrichment/service/inat_name_resolution_service.dart';
import 'package:discere/learning/service/remote_deck_service.dart';
import 'package:discere/theme/ocean_theme/ocean_theme.dart';
import 'package:discere/app/main_screen_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'l10n/app_localizations.dart';
import 'shared/util/logger.dart';
import 'shared/util/logging_http_client.dart';

Future<void> main({NotificationService? notificationService}) async {
  HttpOverrides.global = AppHttpOverrides();
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  tz.initializeTimeZones();

  final providers = await setupServices(
    notificationService: notificationService,
  );
  FlutterNativeSplash.remove();
  runApp(MultiProvider(providers: providers, child: const FlashcardApp()));
}

Future<List<SingleChildWidget>> setupServices({
  NotificationService? notificationService,
}) async {
  Logger.debug('main', 'setupServices: starting...');
  final sharedPreferences = await SharedPreferences.getInstance();
  Logger.debug('main', 'setupServices: SharedPreferences ready');

  final localePlaceMappingRepository = LocalePlaceMappingRepository();
  final localeMapping = await localePlaceMappingRepository
      .getForCurrentLocale();

  final flashcardStatRepository = FlashcardStatRepository();
  final speciesRepository = SpeciesRepository(localeMapping: localeMapping);
  final deckRepository = DeckRepository();
  final sourceRepository = SourceRepository();

  final activeNotificationService =
      notificationService ??
      NotificationService(preferences: sharedPreferences);
  await activeNotificationService.initNotification();

  final sharedHttpClient = LoggingHttpClient(http.Client());
  final imageService = ImageService(client: sharedHttpClient);
  final iNatService = INaturalistService(client: sharedHttpClient);
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
  final fsrsService = FsrsService();
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
  );
  // Created before iNatEnrichmentQueueService so its callbacks can be wired in.
  final deckImportService = DeckImportService(
    deckService,
    speciesRepository,
    iNatService: iNatService,
  );
  final backgroundScheduler = WorkmanagerEnrichmentBackgroundScheduler(
    callbackDispatcher: inatEnrichmentBackgroundDispatcher,
  );
  await backgroundScheduler.initialize();
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
    unresolvedNamesObserver: const _LoggingUnresolvedNamesObserver(),
  );
  deckService.onDeckDeleted = iNatEnrichmentQueueService.cancelDeckEnrichment;
  Logger.debug('main', 'setupServices: DecksService ready');

  final flashcardService = FlashcardService(
    fsrsService,
    flashcardStatRepository,
    activeNotificationService,
    speciesMediaService,
  );

  final favoriteService = FavoriteService(sharedPreferences);
  final watchlistService = WatchlistService(sharedPreferences);
  final languageService = LanguageService(sharedPreferences);

  final remoteDeckService = RemoteDeckService(client: sharedHttpClient);
  final importExportService = ImportExportService(deckService);
  final sourceService = SourceService(sourceRepository);
  final userPreferencesService = UserPreferencesService(sharedPreferences);
  Logger.debug('main', 'setupServices: all services initialized');

  return [
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

class AppHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _LoggingHttpClient(
      super.createHttpClient(context)
        ..userAgent =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3',
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

class _LoggingUnresolvedNamesObserver implements UnresolvedNamesObserverPort {
  const _LoggingUnresolvedNamesObserver();

  @override
  void onNamesUnresolved(String deckId, List<String> stillUnresolved) {
    Logger.debug(
      'INatEnrichmentQueue',
      'Deck $deckId: ${stillUnresolved.length} species still unresolved after '
          'iNaturalist lookup: ${stillUnresolved.join(", ")}',
    );
  }
}

class _LoggingHttpClient implements HttpClient {
  static final _log = Logger.forType(_LoggingHttpClient);
  final HttpClient _inner;

  _LoggingHttpClient(this._inner);

  Future<HttpClientRequest> _open(
    String method,
    Uri url,
    Future<HttpClientRequest> Function() openRequest,
  ) async {
    final stopwatch = Stopwatch()..start();
    _log.debug('--> $method $url');

    final request = await openRequest();
    return _LoggingHttpClientRequest(
      request,
      requestMethod: method,
      url: url,
      stopwatch: stopwatch,
    );
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    return _open(method, url, () => _inner.openUrl(method, url));
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) {
    final uri = Uri(
      scheme: _inner.autoUncompress ? 'https' : 'http',
      host: host,
      port: port,
      path: path,
    );
    return _open(method, uri, () => _inner.open(method, host, port, path));
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> get(String host, int port, String path) {
    return open('GET', host, port, path);
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) {
    return open('POST', host, port, path);
  }

  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);

  @override
  Future<HttpClientRequest> put(String host, int port, String path) {
    return open('PUT', host, port, path);
  }

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) {
    return open('DELETE', host, port, path);
  }

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) {
    return open('PATCH', host, port, path);
  }

  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) {
    return open('HEAD', host, port, path);
  }

  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  bool get autoUncompress => _inner.autoUncompress;

  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;

  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  Duration get idleTimeout => _inner.idleTimeout;

  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;

  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  String? get userAgent => _inner.userAgent;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _inner.authenticate = f;

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _inner.authenticateProxy = f;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _inner.badCertificateCallback = callback;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  set keyLog(void Function(String line)? callback) => _inner.keyLog = callback;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LoggingHttpClientRequest implements HttpClientRequest {
  static final _log = Logger.forType(_LoggingHttpClientRequest);
  final HttpClientRequest _inner;
  final String requestMethod;
  final Uri url;
  final Stopwatch stopwatch;

  _LoggingHttpClientRequest(
    this._inner, {
    required this.requestMethod,
    required this.url,
    required this.stopwatch,
  });

  @override
  Future<HttpClientResponse> close() async {
    try {
      final response = await _inner.close();
      stopwatch.stop();
      _log.debug(
        '<-- ${response.statusCode} $requestMethod $url (${stopwatch.elapsedMilliseconds} ms)',
      );
      return response;
    } catch (error) {
      stopwatch.stop();
      _log.debug(
        '<xx $requestMethod $url failed after ${stopwatch.elapsedMilliseconds} ms: $error',
      );
      rethrow;
    }
  }

  @override
  bool get followRedirects => _inner.followRedirects;
  @override
  set followRedirects(bool followRedirects) =>
      _inner.followRedirects = followRedirects;

  @override
  int get maxRedirects => _inner.maxRedirects;
  @override
  set maxRedirects(int maxRedirects) => _inner.maxRedirects = maxRedirects;

  @override
  bool get bufferOutput => _inner.bufferOutput;
  @override
  set bufferOutput(bool bufferOutput) => _inner.bufferOutput = bufferOutput;

  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  set persistentConnection(bool persistentConnection) =>
      _inner.persistentConnection = persistentConnection;

  @override
  String get method => _inner.method;

  @override
  Uri get uri => _inner.uri;

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  void add(List<int> data) => _inner.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _inner.addStream(stream);

  @override
  Future<HttpClientResponse> get done => _inner.done;

  @override
  Future<void> flush() => _inner.flush();

  @override
  void write(Object? object) => _inner.write(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _inner.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _inner.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _inner.writeln(object);

  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding encoding) => _inner.encoding = encoding;

  @override
  int get contentLength => _inner.contentLength;
  @override
  set contentLength(int contentLength) => _inner.contentLength = contentLength;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
