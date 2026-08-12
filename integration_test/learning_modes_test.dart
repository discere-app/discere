import 'package:discere/learning/flashcard/flashcard_multiple_choice_front.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final deckFinder = find.text(deckName);
      await tester.scrollUntilVisible(
        deckFinder,
        500,
        scrollable: find.descendant(
          of: find.byKey(const Key('home_deck_list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(deckFinder.last);
      await safePumpAndSettle(tester);

      final activationTitle = find.byKey(const Key('activation_dialog_title'));
      if (activationTitle.evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('activation_dialog_yes_button')));
        await safePumpAndSettle(tester);
      }

      // Wait for the card (and its grading buttons — flip mode)
      bool foundCard = false;
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.byIcon(Icons.thumb_up_rounded).evaluate().isNotEmpty) {
          foundCard = true;
          break;
        }
      }
      expect(foundCard, isTrue);

      // Flip the card to reveal the genus scientific name. The test deck's
      // default species is Amphiprion ocellaris, whose genus is Amphiprion.
      // Tapping the image itself now opens the fullscreen viewer instead of
      // flipping (see FlashcardFront), so tap the "tap to reveal" hint below
      // it, which is still wired to the flip gesture.
      await tester.tap(find.byIcon(Icons.visibility_outlined));
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
        species:
            'Amphiprion ocellaris\nAbramis brama\nCarcharodon carcharias\nEnteroctopus dofleini',
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
      // their defaults — 4 species with distinct common names are enough to
      // enable it).
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
      final deckFinder = find.text(deckName);
      await tester.scrollUntilVisible(
        deckFinder,
        500,
        scrollable: find.descendant(
          of: find.byKey(const Key('home_deck_list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(deckFinder.last);
      await safePumpAndSettle(tester);

      final activationTitle = find.byKey(const Key('activation_dialog_title'));
      if (activationTitle.evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('activation_dialog_yes_button')));
        await safePumpAndSettle(tester);
      }

      // Wait for the multiple-choice options to render
      bool foundOptions = false;
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.byType(FlashcardMultipleChoiceFront).evaluate().isNotEmpty) {
          foundOptions = true;
          break;
        }
      }
      expect(foundOptions, isTrue);

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
      await tester.tap(continueButton);
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
