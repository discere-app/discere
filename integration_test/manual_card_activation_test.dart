import 'package:discere/learning/flashcard/flashcard_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets(
    'plays through two full 10-card batches and returns to the home screen',
    (WidgetTester tester) async {
      final mockNotificationService = createMockNotificationService();

      final deckName = 'Batch Test Deck';
      // 20 unambiguous species (each resolves to exactly one reference-DB
      // entry) so the default batchSize of 10 (see
      // FlashcardService.initializeNextBatch) yields exactly two full
      // batches with nothing left over.
      const speciesNames = [
        'Amphiprion ocellaris',
        'Abramis brama',
        'Carcharodon carcharias',
        'Enteroctopus dofleini',
        'Natator depressus',
        'Oncorhynchus mykiss',
        'Phoxinus phoxinus',
        'Pterois miles',
        'Rhincodon typus',
        'Thymallus thymallus',
        'Chelonia mydas',
        'Galeocerdo cuvier',
        'Costoanachis cascabulloi',
        'Staurastrum limneticum',
        'Nicolea chilensis',
        'Trichopodus trichopterus',
        'Americhelidium shoemakeri',
        'Labracinus atrofasciatus',
        'Scabricola eximia',
        'Stercorarius pomarinus',
      ];

      await startApp(
        tester,
        notificationService: mockNotificationService,
        withTestDeck: true,
        deckName: deckName,
        species: speciesNames.join('\n'),
      );

      debugPrint('-- TEST: finding deck in list --');
      final deckFinder = find.text(deckName);
      await tester.scrollUntilVisible(
        deckFinder,
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(deckFinder.last);
      await safePumpAndSettle(tester);

      // Brand-new deck: the first batch of 10 auto-initializes without a
      // dialog (uninitializedCount == totalCount branch in
      // DeckPageState._initializeFlashcards).
      debugPrint('-- TEST: playing through first batch of 10 cards --');
      await _reviewCardsWithEasy(tester, count: 10);

      // 10 of 20 species are now initialized: the next "Continue" shows the
      // "more cards available" dialog instead of auto-activating.
      debugPrint('-- TEST: verifying activation_dialog_title for 2nd batch --');
      expect(find.byKey(const Key('activation_dialog_title')), findsOneWidget);
      await tester.tap(find.byKey(const Key('activation_dialog_yes_button')));
      await safePumpAndSettle(tester);

      debugPrint('-- TEST: playing through second batch of 10 cards --');
      await _reviewCardsWithEasy(tester, count: 10);

      // All 20 species are now initialized and reviewed.
      debugPrint('-- TEST: verifying no_more_cards_dialog_title --');
      expect(find.byKey(const Key('no_more_cards_dialog_title')), findsOneWidget);

      debugPrint('-- TEST: tapping no_more_cards_ok_button --');
      await tester.tap(find.byKey(const Key('no_more_cards_ok_button')));
      await safePumpAndSettle(tester);

      debugPrint('-- TEST: verifying back on home screen --');
      expect(find.byKey(const ValueKey('main-fab')), findsOneWidget);
      expect(deckFinder, findsWidgets);

      // Re-opening the exhausted deck should show the empty state, not the
      // activation dialog again.
      debugPrint('-- TEST: re-opening deck on home screen --');
      await tester.tap(deckFinder.last);
      await safePumpAndSettle(tester);

      expect(
        find.byKey(const Key('no_flashcards_empty_state_text')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('activation_dialog_title')), findsNothing);
    },
    timeout: integrationTestTimeout,
  );
}

/// Waits for the Easy ("thumb up") button and taps it [count] times,
/// grading each card Easy so it graduates straight to Review (no learning
/// requeue) and the batch is exhausted after exactly [count] taps.
Future<void> _reviewCardsWithEasy(WidgetTester tester, {required int count}) async {
  for (var cardIndex = 0; cardIndex < count; cardIndex++) {
    bool foundButtons = false;
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byIcon(Icons.thumb_up_rounded).evaluate().isNotEmpty) {
        foundButtons = true;
        break;
      }
    }
    expect(
      foundButtons,
      isTrue,
      reason: 'Easy button not found for card ${cardIndex + 1} of $count',
    );

    await tester.tap(find.byIcon(Icons.thumb_up_rounded));
    await safePumpAndSettle(tester);
  }
}
