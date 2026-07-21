import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/edit/edit_deck_page.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EditDeckPage discard confirmation', () {
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
      when(decksService.updateDeck(any, any)).thenAnswer((_) async {});
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

    testWidgets('pops without a dialog when there are no unsaved changes', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
        ),
      );
      await tester.tap(find.text('Open Edit Deck'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byType(EditDeckPage), findsNothing);
      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('cancelling the dialog keeps unsaved changes on screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
        ),
      );
      await tester.tap(find.text('Open Edit Deck'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('edit_deck_name_field')),
        'Updated Deck',
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(EditDeckPage), findsOneWidget);
    });

    testWidgets('confirming discard pops the page', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
        ),
      );
      await tester.tap(find.text('Open Edit Deck'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('edit_deck_name_field')),
        'Updated Deck',
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.byType(EditDeckPage), findsNothing);
      verifyNever(decksService.updateDeck(any, any));
    });

    testWidgets('system back gesture triggers the same discard confirmation', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          decksService: decksService,
          imageService: imageService,
          notificationService: notificationService,
          flashcardService: flashcardService,
        ),
      );
      await tester.tap(find.text('Open Edit Deck'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('edit_deck_name_field')),
        'Updated Deck',
      );
      await tester.pump();

      // Simulates the Android hardware/predictive back gesture, which
      // (unlike a plain Navigator.pop() call) is gated by PopScope.canPop.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.byType(EditDeckPage), findsOneWidget);

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.byType(EditDeckPage), findsNothing);
    });
  });
}

Widget _buildApp({
  required DecksService decksService,
  required ImageService imageService,
  required NotificationService notificationService,
  required FlashcardService flashcardService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<DecksService>.value(value: decksService),
      Provider<ImageService>.value(value: imageService),
      Provider<NotificationService>.value(value: notificationService),
      Provider<FlashcardService>.value(value: flashcardService),
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
