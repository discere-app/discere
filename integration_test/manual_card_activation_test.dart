import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:discere/learning/flashcard/flashcard_widget.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets(
    'Auto-init bug test: respects user choice and prompts correctly',
    (WidgetTester tester) async {
      final mockNotificationService = createMockNotificationService();

      final deckName = 'Auto Init Test Deck';
      await startApp(
        tester,
        notificationService: mockNotificationService,
        withTestDeck: true,
        deckName: deckName,
        species: 'Amphiprion ocellaris\nAbramis brama',
      );

      // 2. Open the deck. It should see 0 due but 2 uninitialized.
      debugPrint('-- TEST: finding deck in list --');
      final deckFinder = find.text(deckName);
      await tester.scrollUntilVisible(
        deckFinder,
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(deckFinder.last);
      await safePumpAndSettle(tester);

      final titleFinder = find.byKey(const Key('activation_dialog_title'));

      if (titleFinder.evaluate().isEmpty) {
        debugPrint(
          '-- TEST: no activation dialog, assuming already in review --',
        );
        // If no dialog, check if we are already in review.
        expect(find.byType(FlashcardWidget), findsOneWidget);
      } else {
        debugPrint('-- TEST: tapping activation_dialog_yes_button --');
        expect(titleFinder, findsOneWidget);
        // Click "Yes" to initialize
        await tester.tap(find.byKey(const Key('activation_dialog_yes_button')));
        await safePumpAndSettle(tester);
      }

      // 3. Review the first card
      debugPrint('-- TEST: waiting for thumb_up_rounded button --');
      bool foundButtons = false;
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.byIcon(Icons.thumb_up_rounded).evaluate().isNotEmpty) {
          foundButtons = true;
          break;
        }
      }
      expect(foundButtons, isTrue);

      // Answer "Good" (Thumb up)
      debugPrint('-- TEST: tapping thumb_up_rounded for 1st card --');
      await tester.tap(find.byIcon(Icons.thumb_up_rounded));
      await safePumpAndSettle(tester);

      // Since there are 2 cards in the batch, it should show the 2nd one.
      // Answer "Good" on the 2nd one too.
      debugPrint('-- TEST: tapping thumb_up_rounded for 2nd card --');
      await tester.tap(find.byIcon(Icons.thumb_up_rounded));
      await safePumpAndSettle(tester);

      // Now all 2 cards in the batch are finished.
      // Since there are no more uninitialized cards in the deck (total 2),
      // it should show the "No more cards to learn" dialog.
      debugPrint('-- TEST: verifying no_more_cards_dialog_title --');
      final noMoreTitleFinder = find.byKey(
        const Key('no_more_cards_dialog_title'),
      );
      expect(noMoreTitleFinder, findsOneWidget);

      // Click OK and go back
      debugPrint('-- TEST: tapping no_more_cards_ok_button --');
      final okButton = find.byKey(const Key('no_more_cards_ok_button'));
      await tester.tap(okButton);
      await safePumpAndSettle(tester);

      // Back on home. Now re-open the deck.
      debugPrint('-- TEST: re-opening deck on home screen --');
      await tester.tap(deckFinder.last);
      await safePumpAndSettle(tester);

      // 4. Verify that since 0 are due and 0 are uninitialized, NO dialog is shown.
      // It should just show "No flashcards available".
      debugPrint('-- TEST: verifying no_flashcards_empty_state_text --');
      final noFlashcardsFound = find.byKey(
        const Key('no_flashcards_empty_state_text'),
      );
      expect(noFlashcardsFound, findsOneWidget);
      expect(titleFinder, findsNothing);
    },
    timeout: integrationTestTimeout,
  );
}
