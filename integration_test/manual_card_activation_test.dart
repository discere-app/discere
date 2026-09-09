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
        final flashcardFinder = find.byType(FlashcardWidget);
        await waitForFinder(tester, flashcardFinder);
        expect(flashcardFinder, findsOneWidget);
      } else {
        debugPrint('-- TEST: tapping activation_dialog_yes_button --');
        expect(titleFinder, findsOneWidget);
        // Click "Yes" to initialize
        await tester.tap(find.byKey(const Key('activation_dialog_yes_button')));
        await safePumpAndSettle(tester);
      }

      // 3. Review the first card
      debugPrint('-- TEST: waiting for thumb_up_rounded button --');
      await waitForFinder(
        tester,
        find.byIcon(Icons.thumb_up_rounded),
        description: 'the card and its grading buttons to render',
      );

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
      // The dialog is shown after an async getDeckStat() DB read with no
      // frame scheduled in between (see waitForCondition's doc comment) —
      // pumpAndSettle can settle before it lands, so poll instead of a bare
      // expect right after the tap.
      await waitForFinder(tester, noMoreTitleFinder);
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
      // Same async-getDeckStat race as the dialogs above — wait instead of
      // asserting right after pumpAndSettle. A longer timeout than the other
      // waits in this file: this read follows loadSessionData's full chain
      // (getDeckConfig, getFlashCardsForReview, pendingCommonNameSpeciesIds),
      // which on a loaded CI runner has been observed to take longer than
      // the default 10s poll window.
      await waitForFinder(
        tester,
        noFlashcardsFound,
        timeout: const Duration(seconds: 30),
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
      final activationTitleFinder = find.byKey(
        const Key('activation_dialog_title'),
      );
      // Same async-getDeckStat race as the no-more-cards dialog below — wait
      // instead of asserting right after pumpAndSettle.
      await waitForFinder(tester, activationTitleFinder);
      expect(activationTitleFinder, findsOneWidget);
      await tester.tap(find.byKey(const Key('activation_dialog_yes_button')));
      // The dialog stays up until the batch has actually been written, so its
      // disappearance — not pumpAndSettle — is the signal that the new cards
      // exist. Tapping before that graded whatever was still on screen.
      await waitForAbsence(
        tester,
        activationTitleFinder,
        description: 'the activation dialog to close once the batch is ready',
      );

      debugPrint('-- TEST: playing through second batch of 10 cards --');
      await _reviewCardsWithEasy(tester, count: 10);

      // All 20 species are now initialized and reviewed.
      debugPrint('-- TEST: verifying no_more_cards_dialog_title --');
      final noMoreTitleFinder = find.byKey(
        const Key('no_more_cards_dialog_title'),
      );
      await waitForFinder(tester, noMoreTitleFinder);
      expect(noMoreTitleFinder, findsOneWidget);

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

      final noFlashcardsFound = find.byKey(
        const Key('no_flashcards_empty_state_text'),
      );
      // Same async-getDeckStat race as the dialogs above — wait instead of
      // asserting right after pumpAndSettle. Longer timeout: see the same
      // wait in the first test above for why.
      await waitForFinder(
        tester,
        noFlashcardsFound,
        timeout: const Duration(seconds: 30),
      );
      expect(noFlashcardsFound, findsOneWidget);
      expect(find.byKey(const Key('activation_dialog_title')), findsNothing);
    },
    timeout: integrationTestTimeout,
  );
}

/// Waits for the Easy ("thumb up") button and taps it [count] times.
///
/// Known to be fragile, see #130: the button is on screen for the card that
/// was just graded too, and advancing to the next card is asynchronous with
/// no frame in between — so when the advance is slower than the loop, the
/// same card is graded twice and the batch ends one card short.
///
/// Detecting the advance by comparing the visible text does not work: the
/// screen at that moment carries only the photo placeholder and the rating
/// labels, which read identically for consecutive cards. A reliable signal
/// still has to be found.
Future<void> _reviewCardsWithEasy(
  WidgetTester tester, {
  required int count,
}) async {
  final easyButton = find.byIcon(Icons.thumb_up_rounded);

  for (var cardIndex = 0; cardIndex < count; cardIndex++) {
    await waitForFinder(
      tester,
      easyButton,
      description:
          'the grading buttons of card ${cardIndex + 1} of $count to render',
    );

    await tester.tap(easyButton);
    await safePumpAndSettle(tester);
  }
}
