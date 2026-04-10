import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flash_card_stat_repository.dart';
import 'package:discere/catalog/repository/source_repository.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/catalog/service/species_image_service.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/learning/service/deck_import_service.dart';

import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/repository/external_id_repository.dart';
import 'package:discere/enrichment/repository/external_id_cache_repository.dart';
import 'package:discere/enrichment/external/inaturalist_service.dart';
import 'package:discere/catalog/service/biology_service.dart';
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
import 'package:discere/learning/service/remote_deck_service.dart';
import 'package:discere/theme/ocean_theme/ocean_theme.dart';
import 'package:discere/app/main_screen_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'l10n/app_localizations.dart';

Future<void> main({NotificationService? notificationService}) async {
  HttpOverrides.global = AppHttpOverrides();
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  tz.initializeTimeZones();

  final providers = await setupServices(
    notificationService: notificationService,
  );
  FlutterNativeSplash.remove();
  runApp(MultiProvider(providers: providers, child: const FlashCardApp()));
}

Future<List<SingleChildWidget>> setupServices({
  NotificationService? notificationService,
}) async {
  if (kDebugMode) debugPrint('setupServices: starting...');
  final sharedPreferences = await SharedPreferences.getInstance();
  if (kDebugMode) debugPrint('setupServices: SharedPreferences ready');

  final flashCardStatRepository = FlashCardStatRepository();
  final speciesRepository = SpeciesRepository();
  final deckRepository = DeckRepository();
  final sourcesRepository = SourcesRepository();

  final activeNotificationService =
      notificationService ?? NotificationService();
  await activeNotificationService.initNotification();

  final imageService = ImageService();
  final iNatService = INaturalistService();
  final iNatCacheRepository = INatPhotoCacheRepository();
  final externalIdRepository = ExternalIdRepository();
  final externalIdCacheRepository = ExternalIdCacheRepository();
  final searchRepository = SearchRepository(iNatService: iNatService);
  final speciesImageService = SpeciesImageService(
    imageService,
    iNatCacheRepository,
    iNatService: iNatService,
    externalIdCacheRepository: externalIdCacheRepository,
  );
  final biologyService = BiologyService(
    speciesRepository,
    imageService,
    iNatCacheRepository,
    speciesImageService: speciesImageService,
  );
  final fsrsService = FsrsService();
  final enrichmentService = EnrichmentService(
    speciesRepository,
    flashCardStatRepository,
    imageService,
    iNatService,
    iNatCacheRepository,
    externalIdRepository,
    externalIdCacheRepository,
  );
  final deckService = DecksService(
    deckRepository,
    flashCardStatRepository,
    speciesRepository,
    imageService,
  );
  final iNatEnrichmentQueueService = INatEnrichmentQueueService(
    enrichmentService,
    preferences: sharedPreferences,
  );
  if (kDebugMode) debugPrint('setupServices: DecksService ready');

  final flashCardService = FlashCardService(
    speciesRepository,
    imageService,
    fsrsService,
    flashCardStatRepository,
    activeNotificationService,
    iNatCacheRepository,
    speciesImageService: speciesImageService,
  );

  final favoriteService = FavoriteService(sharedPreferences);
  final watchListService = WatchListService(sharedPreferences);
  final languageService = LanguageService(sharedPreferences);

  final remoteDeckService = RemoteDeckService();
  final importExportService = ImportExportService(deckService);
  final deckImportService = DeckImportService(
    deckService,
    speciesRepository,
    imageService,
  );
  final sourceService = SourceService(sourcesRepository);
  final userPreferencesService = UserPreferencesService(sharedPreferences);
  if (kDebugMode) debugPrint('setupServices: all services initialized');

  return [
    Provider<INaturalistService>.value(value: iNatService),
    Provider<ImageService>.value(value: imageService),
    Provider<EnrichmentService>.value(value: enrichmentService),
    Provider<FlashCardService>.value(value: flashCardService),
    Provider<BiologyService>.value(value: biologyService),
    Provider<NotificationService>.value(value: activeNotificationService),
    Provider<SearchRepository>.value(value: searchRepository),
    ChangeNotifierProvider<DecksService>.value(value: deckService),
    ChangeNotifierProvider<INatEnrichmentQueueService>.value(
      value: iNatEnrichmentQueueService,
    ),
    Provider<ImportExportService>.value(value: importExportService),
    Provider<DeckImportService>.value(value: deckImportService),
    Provider<RemoteDeckService>.value(value: remoteDeckService),
    ChangeNotifierProvider<FavoriteService>.value(value: favoriteService),
    ChangeNotifierProvider<WatchListService>.value(value: watchListService),
    ChangeNotifierProvider<LanguageService>.value(value: languageService),
    Provider<SourceService>.value(value: sourceService),
    ChangeNotifierProvider<UserPreferencesService>.value(
      value: userPreferencesService,
    ),
  ];
}

class FlashCardApp extends StatelessWidget {
  const FlashCardApp({super.key});

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
    return super.createHttpClient(context)
      ..userAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3';
  }
}
