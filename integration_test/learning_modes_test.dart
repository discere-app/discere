import 'package:discere/learning/flashcard/flashcard_multiple_choice_front.dart';
import 'package:discere/learning/flashcard/flashcard_widget.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'multiple_choice_deck_species.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  tearDown(() async {
    await DatabaseHelper.close();
  });

  testWidgets(
    'Genus + Scientific Name + Flip: card shows the genus scientific name',
    (tester) async {
      final mockNotificationService = createMockNotificationService();
      const deckName = 'Genus Mode Deck';

      await startApp(
        tester,
        notificationService: mockNotificationService,
        withTestDeck: true,
        deckName: deckName,
      );

      // Open Edit Deck
      await tester.tap(
        find.descendant(
          of: find.byType(Card).first,
          matching: find.byIcon(Icons.edit_square),
        ),
      );
      await safePumpAndSettle(tester);
      expect(find.byKey(const Key('edit_deck_save_button')), findsOneWidget);

      // Switch Learning Mode to Genus
      final genusSegment = find.descendant(
        of: find.byKey(const Key('learning_mode_segmented_button')),
        matching: find.byIcon(Icons.account_tree_rounded),
      );
      await tester.ensureVisible(genusSegment);
      await safePumpAndSettle(tester);
      await tester.tap(genusSegment);
      await safePumpAndSettle(tester);

      // Switch Name Type to Scientific
      final scientificSegment = find.descendant(
        of: find.byKey(const Key('name_type_segmented_button')),
        matching: find.byIcon(Icons.biotech_outlined),
      );
      await tester.ensureVisible(scientificSegment);
      await safePumpAndSettle(tester);
      await tester.tap(scientificSegment);
      await safePumpAndSettle(tester);

      // Save (the Save action lives in the AppBar, always reachable without
      // scrolling back to the top).
      await tester.tap(find.byKey(const Key('edit_deck_save_button')));
      await safePumpAndSettle(tester);

      // Open the deck for review
      await openDeck(tester, deckName);

      final activationTitle = find.byKey(const Key('activation_dialog_title'));
      if (activationTitle.evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('activation_dialog_yes_button')));
        await waitForAbsence(
          tester,
          find.byKey(const Key('activation_dialog_title')),
          description: 'the activation dialog to close once the batch is ready',
        );
      }

      // Wait for the card (and its grading buttons — flip mode)
      await waitForFinder(
        tester,
        find.byIcon(Icons.thumb_up_rounded),
        description: 'the card and its grading buttons to render',
      );

      // Flip the card to reveal the genus scientific name. The test deck's
      // default species is Amphiprion ocellaris, whose genus is Amphiprion.
      // Tapping the image itself now opens the fullscreen viewer instead of
      // flipping (see FlashcardFront), so tap near the bottom of the card
      // instead — that's the flip-wired footer when a photo loaded, and
      // still within the flip-wired placeholder when it didn't (e.g. no
      // network access, as in CI).
      final cardRect = tester.getRect(find.byType(FlashcardWidget));
      await tester.tapAt(Offset(cardRect.center.dx, cardRect.bottom - 20));
      await safePumpAndSettle(tester);

      expect(find.text('Amphiprion'), findsWidgets);

      // Navigate back to Home so DeckPage.dispose() (which fires an
      // unawaited enrichment-queue refresh) runs while the test's database
      // is still open, rather than racing tearDown's DatabaseHelper.close().
      await tester.pageBack();
      await safePumpAndSettle(tester);
    },
    timeout: integrationTestTimeout,
  );

  testWidgets(
    'Species + Common Name + Multiple Choice: answering a card highlights the result and grades it',
    (tester) async {
      final mockNotificationService = createMockNotificationService();
      const deckName = 'Multiple Choice Deck';

      await startApp(
        tester,
        notificationService: mockNotificationService,
        withTestDeck: true,
        deckName: deckName,
        species: multipleChoiceDeckSpecies.join('\n'),
      );

      // Open Edit Deck
      await tester.tap(
        find.descendant(
          of: find.byType(Card).first,
          matching: find.byIcon(Icons.edit_square),
        ),
      );
      await safePumpAndSettle(tester);
      expect(find.byKey(const Key('edit_deck_save_button')), findsOneWidget);

      // Switch Review Mode to Multiple Choice (species/commonName stay at
      // their defaults). What makes the deck usable here is that every card
      // finds three close relatives to draw distractors from — see
      // multipleChoiceDeckSpecies.
      final multipleChoiceSegment = find.descendant(
        of: find.byKey(const Key('review_mode_segmented_button')),
        matching: find.byIcon(Icons.checklist_outlined),
      );
      await tester.ensureVisible(multipleChoiceSegment);
      await safePumpAndSettle(tester);
      await tester.tap(multipleChoiceSegment);
      await safePumpAndSettle(tester);

      await tester.tap(find.byKey(const Key('edit_deck_save_button')));
      await safePumpAndSettle(tester);

      // Open the deck for review
      await openDeck(tester, deckName);

      final activationTitle = find.byKey(const Key('activation_dialog_title'));
      if (activationTitle.evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('activation_dialog_yes_button')));
        await waitForAbsence(
          tester,
          find.byKey(const Key('activation_dialog_title')),
          description: 'the activation dialog to close once the batch is ready',
        );
      }

      await waitForFinder(
        tester,
        find.byType(FlashcardMultipleChoiceFront),
        description: 'the multiple-choice options to render',
      );

      // Scope to the 2 option rows rather than the whole front widget — the
      // latter also contains the watchlist IconButton (itself backed by an
      // InkWell) and each option tile's own icon+text Row, none of which
      // should count as an option row. The 2 real option rows are the only
      // ones left at their default mainAxisSize (max); the tile-internal
      // icon+text rows explicitly use mainAxisSize.min.
      final optionRows = find.descendant(
        of: find.byType(FlashcardMultipleChoiceFront),
        matching: find.byWidgetPredicate(
          (widget) => widget is Row && widget.mainAxisSize == MainAxisSize.max,
        ),
      );
      expect(optionRows, findsNWidgets(2));

      final optionTiles = find.descendant(
        of: optionRows,
        matching: find.byType(InkWell),
      );
      expect(optionTiles, findsNWidgets(4));

      // Tap an option. The correct/incorrect highlight appears on the front
      // immediately (a single pump, before the 600ms auto-flip timer fires);
      // safePumpAndSettle would ride straight through that timer and the
      // flip animation to the back content, missing this transient state.
      await tester.tap(optionTiles.first);
      await tester.pump();

      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      // Now let the reveal timer fire and the flip animation settle.
      await safePumpAndSettle(tester);

      final continueButton = find.text('Continue');
      await waitForFinder(tester, continueButton);
      expect(continueButton, findsOneWidget);

      // Flip back to the front to look at the image again — tapping
      // anywhere on the revealed back (away from its own interactive
      // widgets) flips it, same as flip mode's card.
      await tester.tapAt(tester.getCenter(find.byType(FlashcardWidget)));
      await safePumpAndSettle(tester);

      expect(find.byType(FlashcardMultipleChoiceFront), findsOneWidget);
      expect(find.text('Continue'), findsNothing);

      // The answer must stay locked in — tapping a different option now
      // must not change the graded result.
      final relockedTiles = find.descendant(
        of: find.descendant(
          of: find.byType(FlashcardMultipleChoiceFront),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Row && widget.mainAxisSize == MainAxisSize.max,
          ),
        ),
        matching: find.byType(InkWell),
      );
      expect(relockedTiles, findsNWidgets(4));
      await tester.tap(relockedTiles.last);
      await tester.pump();

      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      // Flip forward again to reach Continue.
      await tester.tap(find.text('Which one is it?'));
      await safePumpAndSettle(tester);

      await tester.tap(find.text('Continue'));
      await safePumpAndSettle(tester);

      // Navigate back to Home so DeckPage.dispose() (which fires an
      // unawaited enrichment-queue refresh) runs while the test's database
      // is still open, rather than racing tearDown's DatabaseHelper.close().
      await tester.pageBack();
      await safePumpAndSettle(tester);
    },
    timeout: integrationTestTimeout,
  );
}
