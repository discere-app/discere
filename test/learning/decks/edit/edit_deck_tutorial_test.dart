import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/edit/edit_deck_page.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../mocks.mocks.dart';

/// Covers EditDeckPage's first-run coach mark over the learning settings
/// section (lib/learning/decks/edit/edit_deck_tutorial.dart), scheduled by
/// EditDeckPageState._maybeScheduleTutorial.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDecksService decksService;
  late MockImageService imageService;
  late MockNotificationService notificationService;
  late MockFlashcardService flashcardService;

  setUp(() {
    decksService = MockDecksService();
    imageService = MockImageService();
    notificationService = MockNotificationService();
    flashcardService = MockFlashcardService();

    when(
      notificationService.shouldPromptForPermission(),
    ).thenAnswer((_) async => false);
    when(decksService.getSpeciesByDeckId('deck-1')).thenAnswer((_) async => []);
    when(flashcardService.getDeckConfig(any)).thenAnswer(
      (inv) async => DeckConfig(
        deckId: inv.positionalArguments.first as String,
        desiredRetention: 0.9,
      ),
    );
  });

  Future<UserPreferencesService> userPreferencesService(bool hasSeen) async {
    SharedPreferences.setMockInitialValues({
      'has_seen_edit_deck_tutorial': hasSeen,
    });
    return UserPreferencesService(await SharedPreferences.getInstance());
  }

  testWidgets(
    'shows the learning-settings coach mark the first time the page opens',
    (tester) async {
      final prefs = await userPreferencesService(false);

      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
          userPreferencesService: prefs,
        ),
      );
      await tester.pumpAndSettle();
      // Mirrors deck_page_multiple_choice_test.dart's tutorial test:
      // TutorialCoachMark's overlay never stops animating once shown, so
      // pumpAndSettle() can't be used afterwards.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.text('Learning settings'), findsOneWidget);
      expect(prefs.hasSeenEditDeckTutorial, isTrue);
    },
  );

  testWidgets('does not show again once already seen', (tester) async {
    final prefs = await userPreferencesService(true);

    await tester.pumpWidget(
      _buildApp(
        decksService: decksService,
        imageService: imageService,
        notificationService: notificationService,
        flashcardService: flashcardService,
        userPreferencesService: prefs,
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Learning settings'), findsNothing);
  });
}

Widget _buildApp({
  required DecksService decksService,
  required ImageService imageService,
  required NotificationService notificationService,
  required FlashcardService flashcardService,
  required UserPreferencesService userPreferencesService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DecksService>.value(value: decksService),
      Provider<ImageService>.value(value: imageService),
      Provider<NotificationService>.value(value: notificationService),
      Provider<FlashcardService>.value(value: flashcardService),
      ChangeNotifierProvider<UserPreferencesService>.value(
        value: userPreferencesService,
      ),
      ChangeNotifierProvider<INatEnrichmentQueueService>.value(
        value: _TestINatEnrichmentQueueService(),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: EditDeckPage(
        deck: BaseDeck(
          'deck-1',
          'Test Deck',
          'Description',
          language: Language.en,
        ),
        buildSpeciesDetailPage: (speciesId, language) =>
            const SizedBox.shrink(),
      ),
    ),
  );
}

class _TestINatEnrichmentQueueService extends ChangeNotifier
    implements INatEnrichmentQueueService {
  @override
  INatEnrichmentStatus get status => INatEnrichmentStatus.idle;

  @override
  HostCooldownSnapshot? get activeCooldown => null;

  @override
  Future<bool> get isForegroundServiceRunning async => false;

  @override
  Future<Set<String>> pendingCommonNameSpeciesIds(Set<String> speciesIds) async {
    return {};
  }

  @override
  DeckEnrichmentInfo deckInfo(String deckId) => const DeckEnrichmentInfo(
    status: EnrichmentJobStatus.completed,
    lastCompletedAt: null,
    lastAttemptedAt: null,
  );

  @override
  Future<void> scheduleDeckEnrichment(
    List<String> deckIds, {
    bool includeINatPhotos = true,
    bool includeCommonNames = true,
    Map<String, String?> coverImageUrlsByDeckId = const {},
    Map<String, List<String>> unresolvedNamesByDeckId = const {},
    bool waitForForegroundIdle = false,
  }) async {}

  @override
  void cancelDeckEnrichment(String deckId) {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> enterInteractivePriorityMode() async {}

  @override
  Future<void> leaveInteractivePriorityMode() async {}
}
