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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EditDeckPage delete action', () {
    late MockDecksService decksService;
    late MockImageService imageService;
    late MockNotificationService notificationService;
    late MockFlashcardService flashcardService;
    late UserPreferencesService userPreferencesService;

    setUp(() async {
      decksService = MockDecksService();
      imageService = MockImageService();
      notificationService = MockNotificationService();
      flashcardService = MockFlashcardService();
      // The edit-deck tutorial's coach mark never settles once shown — mark
      // it seen so it stays out of the way of these delete-flow tests.
      SharedPreferences.setMockInitialValues({
        'has_seen_edit_deck_tutorial': true,
      });
      userPreferencesService = UserPreferencesService(
        await SharedPreferences.getInstance(),
      );

      when(
        notificationService.shouldPromptForPermission(),
      ).thenAnswer((_) async => false);
      when(decksService.updateDeck(any, any)).thenAnswer((_) async {});
      when(decksService.deleteDeck('deck-1')).thenAnswer((_) async {});
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => []);
      when(flashcardService.getDeckConfig(any)).thenAnswer(
        (inv) async => DeckConfig(
          deckId: inv.positionalArguments.first as String,
          desiredRetention: 0.9,
        ),
      );
    });

    testWidgets('cancelling the confirmation dialog keeps the deck', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.tap(find.text('Open Edit Deck'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit_deck_delete_button')));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Deletion'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('edit_deck_delete_cancel_button')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EditDeckPage), findsOneWidget);
      verifyNever(decksService.deleteDeck(any));
    });

    testWidgets(
      'confirming deletion deletes the deck and pops the page',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            decksService: decksService,
            imageService: imageService,
            notificationService: notificationService,
            flashcardService: flashcardService,
            userPreferencesService: userPreferencesService,
          ),
        );
        await tester.tap(find.text('Open Edit Deck'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('edit_deck_delete_button')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('edit_deck_delete_confirm_button')),
        );
        await tester.pumpAndSettle();

        verify(decksService.deleteDeck('deck-1')).called(1);
        expect(find.byType(EditDeckPage), findsNothing);
      },
    );

    testWidgets(
      'deleting after making unsaved changes does not trigger the discard '
      'confirmation',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            decksService: decksService,
            imageService: imageService,
            notificationService: notificationService,
            flashcardService: flashcardService,
            userPreferencesService: userPreferencesService,
          ),
        );
        await tester.tap(find.text('Open Edit Deck'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('edit_deck_name_field')),
          'Updated Deck',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('edit_deck_delete_button')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('edit_deck_delete_confirm_button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Discard changes?'), findsNothing);
        verify(decksService.deleteDeck('deck-1')).called(1);
        expect(find.byType(EditDeckPage), findsNothing);
        verifyNever(decksService.updateDeck(any, any));
      },
    );
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
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => EditDeckPage(
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
              ),
              child: const Text('Open Edit Deck'),
            ),
          ),
        ),
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
