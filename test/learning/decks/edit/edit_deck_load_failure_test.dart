import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/edit/edit_deck_page.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/model/language.dart';
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
import 'edit_deck_manual_enrichment_test.dart'
    show TestINatEnrichmentQueueService;

/// Covers EditDeckPage when loading the deck's species or learning config
/// fails: the page has to say so and offer a retry, and must never save —
/// [DecksService.updateDeck] diffs against the species set it is handed, so
/// a save with a species list that never loaded deletes every card.

Species _species(String id, String scientificName) => Species(
  id,
  scientificName,
  'fishbase',
  scientificName,
  const {},
  Classification(
    scientificName.split(' ').first,
    const {},
    null,
    'Pomacentridae',
    const {},
    'Perciformes',
    const {},
    'Actinopterygii',
    const {},
    null,
  ),
  const [],
);

const _retryButton = Key('edit_deck_retry_button');
const _saveButton = Key('edit_deck_save_button');
const _nameField = Key('edit_deck_name_field');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EditDeckPage load failure', () {
    late MockDecksService decksService;
    late MockFlashcardService flashcardService;
    late MockNotificationService notificationService;
    late UserPreferencesService userPreferencesService;

    setUp(() async {
      decksService = MockDecksService();
      flashcardService = MockFlashcardService();
      notificationService = MockNotificationService();
      // The coach mark never settles once shown, which would hang every
      // pumpAndSettle here.
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
      when(decksService.getSpeciesByDeckId('deck-1')).thenAnswer(
        (_) async => [
          _species('sp1', 'Amphiprion ocellaris'),
          _species('sp2', 'Dascyllus aruanus'),
        ],
      );
      when(flashcardService.getDeckConfig(any)).thenAnswer(
        (inv) async => DeckConfig(
          deckId: inv.positionalArguments.first as String,
          desiredRetention: 0.9,
        ),
      );
      when(flashcardService.saveDeckConfig(any)).thenAnswer((_) async {});
    });

    Future<void> openEditDeckPage(WidgetTester tester) async {
      // Tall enough that the whole page is laid out at once, so no step
      // below has to scroll first.
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          flashcardService: flashcardService,
          notificationService: notificationService,
          userPreferencesService: userPreferencesService,
        ),
      );
      await tester.tap(find.text('Open Edit Deck'));
      await tester.pumpAndSettle();
    }

    /// Edits every text field the page shows and taps Save — the way a user
    /// would turn a page that looks loaded into a save.
    Future<void> tryToSave(WidgetTester tester) async {
      for (final field in find.byType(EditableText).evaluate().toList()) {
        await tester.enterText(find.byWidget(field.widget), 'Renamed');
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_saveButton), warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    bool saveEnabled(WidgetTester tester) =>
        tester.widget<TextButton>(find.byKey(_saveButton)).onPressed != null;

    testWidgets('species failing to load shows the error and never saves', (
      tester,
    ) async {
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => throw Exception('species table unreadable'));

      await openEditDeckPage(tester);
      await tryToSave(tester);

      verifyNever(decksService.updateDeck(any, any));
      verifyNever(flashcardService.saveDeckConfig(any));
      expect(
        find.text('Could not load the deck: Something went wrong.'),
        findsOneWidget,
      );
      expect(find.byKey(_retryButton), findsOneWidget);
      expect(find.byKey(_nameField), findsNothing);
      expect(find.textContaining('Species in Deck'), findsNothing);
      expect(saveEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('learning config failing to load shows the error and never '
        'saves', (tester) async {
      when(
        flashcardService.getDeckConfig(any),
      ).thenAnswer((_) async => throw Exception('deck_config unreadable'));

      await openEditDeckPage(tester);
      await tryToSave(tester);

      verifyNever(decksService.updateDeck(any, any));
      verifyNever(flashcardService.saveDeckConfig(any));
      expect(find.byKey(_retryButton), findsOneWidget);
      expect(find.byKey(_nameField), findsNothing);
      expect(saveEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('retrying after a failure loads the deck, and saving keeps '
        'all of its species', (tester) async {
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => throw Exception('species table unreadable'));
      await openEditDeckPage(tester);

      when(decksService.getSpeciesByDeckId('deck-1')).thenAnswer(
        (_) async => [
          _species('sp1', 'Amphiprion ocellaris'),
          _species('sp2', 'Dascyllus aruanus'),
        ],
      );
      await tester.tap(find.byKey(_retryButton));
      await tester.pumpAndSettle();

      expect(find.text('Species in Deck (2)'), findsOneWidget);

      await tester.enterText(find.byKey(_nameField), 'Renamed');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_saveButton));
      await tester.pumpAndSettle();

      final saved = verify(
        decksService.updateDeck(captureAny, captureAny),
      ).captured;
      expect((saved[0] as BaseDeck).name, 'Renamed');
      expect(saved[1], {'sp1', 'sp2'});
    });

    testWidgets('going back from the error leaves without asking to discard', (
      tester,
    ) async {
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => throw Exception('species table unreadable'));
      await openEditDeckPage(tester);
      expect(find.byKey(_retryButton), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(EditDeckPage), findsNothing);
    });

    testWidgets('the tutorial waits for the deck to load', (tester) async {
      SharedPreferences.setMockInitialValues({
        'has_seen_edit_deck_tutorial': false,
      });
      userPreferencesService = UserPreferencesService(
        await SharedPreferences.getInstance(),
      );
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => throw Exception('species table unreadable'));
      await openEditDeckPage(tester);
      await tester.pump(const Duration(seconds: 1));

      // Its target, the learning settings section, is not on screen.
      expect(userPreferencesService.hasSeenEditDeckTutorial, isFalse);
      expect(tester.takeException(), isNull);

      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => [_species('sp1', 'Amphiprion ocellaris')]);
      await tester.tap(find.byKey(_retryButton));
      // The coach mark never stops animating once shown, so pumpAndSettle
      // can't be used from here on.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(userPreferencesService.hasSeenEditDeckTutorial, isTrue);
    });
  });
}

Widget _buildApp({
  required DecksService decksService,
  required FlashcardService flashcardService,
  required NotificationService notificationService,
  required UserPreferencesService userPreferencesService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DecksService>.value(value: decksService),
      Provider<ImageService>.value(value: MockImageService()),
      Provider<NotificationService>.value(value: notificationService),
      Provider<FlashcardService>.value(value: flashcardService),
      Provider<SpeciesMediaService>.value(value: MockSpeciesMediaService()),
      ChangeNotifierProvider<INatEnrichmentQueueService>.value(
        value: TestINatEnrichmentQueueService(),
      ),
      ChangeNotifierProvider<UserPreferencesService>.value(
        value: userPreferencesService,
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
                      id: 'deck-1',
                      name: 'Test Deck',
                      description: 'Description',
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
