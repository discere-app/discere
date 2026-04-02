
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:discere/persistence/deck_repository.dart';
import 'package:discere/persistence/flash_card_stat_repository.dart';
import 'package:discere/persistence/source_repository.dart';
import 'package:discere/service/common/image_service.dart';
import 'package:discere/service/common/source_service.dart';

import 'package:discere/persistence/search_repository.dart';
import 'package:discere/persistence/species_repository.dart';
import 'package:discere/persistence/inat_photo_cache_repository.dart';
import 'package:discere/persistence/external_id_repository.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/service/common/biology_service.dart';
import 'package:discere/service/common/favorite_service.dart';
import 'package:discere/service/common/language_service.dart';
import 'package:discere/service/common/notification_service.dart';
import 'package:discere/service/common/watchlist_service.dart';
import 'package:discere/service/common/import_export_service.dart';
import 'package:discere/service/common/user_preferences_service.dart';
import 'package:discere/service/learning/decks_service.dart';
import 'package:discere/service/learning/flashcard_service.dart';
import 'package:discere/service/learning/fsrs_service.dart';
import 'package:discere/service/learning/remote_deck_service.dart';
import 'package:discere/theme/ocean_theme/ocean_theme.dart';
import 'package:discere/ui/pages/main_screen_page.dart';
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

  final providers = await setupServices(notificationService: notificationService);
  FlutterNativeSplash.remove();
  runApp(
    MultiProvider(
      providers: providers,
      child: const FlashCardApp(),
    ),
  );
}

Future<List<SingleChildWidget>> setupServices({NotificationService? notificationService}) async {
  if (kDebugMode) debugPrint('setupServices: starting...');
  final sharedPreferences = await SharedPreferences.getInstance();
  if (kDebugMode) debugPrint('setupServices: SharedPreferences ready');

  final flashCardStatRepository = FlashCardStatRepository();
  final searchRepository = SearchRepository();
  final speciesRepository = SpeciesRepository();
  final deckRepository = DeckRepository();
  final sourcesRepository = SourcesRepository();

  final activeNotificationService = notificationService ?? NotificationService();
  await activeNotificationService.initNotification();

  final imageService = ImageService();
  final iNatService = INaturalistService();
  final iNatCacheRepository = INatPhotoCacheRepository();
  final externalIdRepository = ExternalIdRepository();
  final biologyService = BiologyService(speciesRepository, imageService, iNatCacheRepository);
  final fsrsService = FsrsService();
  final deckService = DecksService(
    deckRepository,
    flashCardStatRepository,
    speciesRepository,
    imageService,
    iNatService,
    iNatCacheRepository,
    externalIdRepository,
  );
  if (kDebugMode) debugPrint('setupServices: DecksService ready');

  final flashCardService = FlashCardService(
    speciesRepository,
    imageService,
    fsrsService,
    flashCardStatRepository,
    activeNotificationService,
    iNatCacheRepository,
  );

  final favoriteService = FavoriteService(sharedPreferences);
  final watchListService = WatchListService(sharedPreferences);
  final languageService = LanguageService(sharedPreferences);

  final remoteDeckService = RemoteDeckService();
  final importExportService = ImportExportService(deckService, speciesRepository, imageService);
  final sourceService = SourceService(sourcesRepository);
  final userPreferencesService = UserPreferencesService(sharedPreferences);
  if (kDebugMode) debugPrint('setupServices: all services initialized');


  return [
    Provider<ImageService>.value(value: imageService),
    Provider<FlashCardService>.value(value: flashCardService),
    Provider<BiologyService>.value(value: biologyService),
    Provider<NotificationService>.value(value: activeNotificationService),
    Provider<SearchRepository>.value(value: searchRepository),
    ChangeNotifierProvider<DecksService>.value(value: deckService),
    Provider<ImportExportService>.value(value: importExportService),
    Provider<RemoteDeckService>.value(value: remoteDeckService),
    ChangeNotifierProvider<FavoriteService>.value(value: favoriteService),
    ChangeNotifierProvider<WatchListService>.value(value: watchListService),
    ChangeNotifierProvider<LanguageService>.value(value: languageService),
    Provider<SourceService>.value(value: sourceService),
    ChangeNotifierProvider<UserPreferencesService>.value(value: userPreferencesService),
  ];
}

class FlashCardApp extends StatelessWidget {
  const FlashCardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LanguageService>(builder: (context, languageService, child) {
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
    });
  }
}

class AppHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3';
  }
}
