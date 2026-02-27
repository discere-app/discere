
import 'package:discere/persistence/database_helper.dart';
import 'package:discere/persistence/deck_repository.dart';
import 'package:discere/persistence/flash_card_stat_repository.dart';
import 'package:discere/persistence/image_service.dart';
import 'package:discere/persistence/search_repository.dart';
import 'package:discere/persistence/species_repository.dart';
import 'package:discere/service/common/biology_service.dart';
import 'package:discere/service/common/favorite_service.dart';
import 'package:discere/service/common/language_service.dart';
import 'package:discere/service/common/notification_service.dart';
import 'package:discere/service/common/watchlist_service.dart';
import 'package:discere/service/learning/decks_service.dart';
import 'package:discere/service/learning/flashcard_service.dart';
import 'package:discere/service/learning/spaced_repetition_service.dart';
import 'package:discere/theme/marine_theme/marine_theme.dart';
import 'package:discere/ui/pages/main_screen_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;


import 'l10n/app_localizations.dart';

Future<void> main({NotificationService? notificationService}) async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  final providers = await setupServices(notificationService: notificationService);

  runApp(
    MultiProvider(
      providers: providers,
      child: const FlashCardApp(),
    ),
  );
}

Future<List<SingleChildWidget>> setupServices({NotificationService? notificationService}) async {
  final db = await DatabaseHelper.openAquaFlashDB();
  final sharedPreferences = await SharedPreferences.getInstance();

  final flashCardStatRepository = FlashCardStatRepository(db);
  final searchRepository = SearchRepository(db);
  final speciesRepository = SpeciesRepository(db);
  final deckRepository = DeckRepository(db);

  final activeNotificationService = notificationService ?? NotificationService();
  await activeNotificationService.initNotification();

  final imageService = ImageService();
  final biologyService = BiologyService(speciesRepository, imageService);
  final spacedRepetitionService = SpacedRepetitionService();
  final flashCardService = FlashCardService(
    speciesRepository,
    imageService,
    spacedRepetitionService,
    flashCardStatRepository,
    activeNotificationService,
  );

  final favoriteService = FavoriteService(sharedPreferences);
  final watchListService = WatchListService(sharedPreferences);
  final languageService = LanguageService(sharedPreferences);

  final deckService = DecksService(
    deckRepository,
    flashCardStatRepository,
    speciesRepository,
  );
  await deckService.createDummyDecks();

  return [
    Provider<FlashCardService>.value(value: flashCardService),
    Provider<BiologyService>.value(value: biologyService),
    Provider<NotificationService>.value(value: activeNotificationService),
    Provider<SearchRepository>.value(value: searchRepository),
    ChangeNotifierProvider<DecksService>.value(value: deckService),
    ChangeNotifierProvider<FavoriteService>.value(value: favoriteService),
    ChangeNotifierProvider<WatchListService>.value(value: watchListService),
    ChangeNotifierProvider<LanguageService>.value(value: languageService),
  ];
}

class FlashCardApp extends StatelessWidget {
  const FlashCardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: marineTheme,
      home: const MainScreenPage(),
    );
  }
}
