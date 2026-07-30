import 'package:discere/learning/model/deck_config.dart';
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

  group('Edit Deck Page', () {
    testWidgets(
      'can navigate to Edit Deck and see Cover Image options',
      (tester) async {
        final mockNotificationService = createMockNotificationService();

        await startApp(
          tester,
          notificationService: mockNotificationService,
          withTestDeck: true,
        );

        // 2. Locate the created deck to edit
        final deckCardFinder = find.byType(Card);
        expect(
          deckCardFinder,
          findsWidgets,
          reason: 'Expected at least one deck card on home screen',
        );

        final deckCard = deckCardFinder.first;

        // 3. Tap Edit on the deck
        final editButton = find.descendant(
          of: deckCard,
          matching: find.byIcon(Icons.edit_square),
        );
        expect(
          editButton,
          findsOneWidget,
          reason: 'Expected an edit button on the deck card',
        );
        await tester.tap(editButton);
        await safePumpAndSettle(tester);

        // 3. Verify labels on Edit Deck Page (using Icons/Keys where possible)
        // We expect the title to be 'Edit Deck', but we can also verify by the Save button key
        expect(find.byKey(const Key('edit_deck_save_button')), findsOneWidget);

        final scrollable = find.byType(CustomScrollView).first;
        await tester.drag(scrollable, const Offset(0, -900));
        await safePumpAndSettle(tester);
        await tester.drag(scrollable, const Offset(0, -900));
        await safePumpAndSettle(tester);

        expect(
          find.textContaining('Amphiprion ocellaris'),
          findsAtLeastNWidgets(1),
        );
        expect(find.textContaining('anemonefish'), findsAtLeastNWidgets(1));

        // 4. Verify the image picker's gallery button (scroll back up to the
        // cover image section)
        final galleryButton = find.byIcon(Icons.photo_library_outlined);

        await tester.scrollUntilVisible(
          galleryButton,
          -300.0,
          scrollable: find.byType(Scrollable).first,
        );
        await safePumpAndSettle(tester);

        expect(galleryButton, findsWidgets);
      },
      timeout: integrationTestTimeout,
    );

    testWidgets(
      'species in deck can be tapped to open detail page and return to edit deck',
      (tester) async {
        final mockNotificationService = createMockNotificationService();

        await startApp(
          tester,
          notificationService: mockNotificationService,
          withTestDeck: true,
        );

        // Navigate to edit deck
        await tester.tap(
          find.descendant(
            of: find.byType(Card).first,
            matching: find.byIcon(Icons.edit_square),
          ),
        );
        await safePumpAndSettle(tester);

        expect(find.byKey(const Key('edit_deck_save_button')), findsOneWidget);

        // Scroll to the species list
        final scrollable = find.byType(CustomScrollView).first;
        await tester.drag(scrollable, const Offset(0, -900));
        await safePumpAndSettle(tester);
        await tester.drag(scrollable, const Offset(0, -900));
        await safePumpAndSettle(tester);

        expect(
          find.textContaining('Amphiprion ocellaris'),
          findsAtLeastNWidgets(1),
        );

        // Tap species to open detail page
        await tester.tap(find.textContaining('Amphiprion ocellaris').first);
        await safePumpAndSettle(tester);

        // Verify species detail page is shown (watchlist button is unique to it)
        final watchlistButton = find.byKey(
          const Key('species_detail_watchlist_button'),
        );
        expect(watchlistButton, findsOneWidget);

        // Tap back via the AppBar that belongs to the species detail page —
        // using the watchlist button as anchor avoids hitting the edit deck
        // page's own back button, which is also in the widget tree.
        final detailAppBar = find.ancestor(
          of: watchlistButton,
          matching: find.byType(AppBar),
        );
        await tester.tap(
          find.descendant(of: detailAppBar, matching: find.byType(BackButton)),
        );
        await safePumpAndSettle(tester);

        // Verify we're back on the edit deck page
        expect(find.byKey(const Key('edit_deck_save_button')), findsOneWidget);
      },
      timeout: integrationTestTimeout,
    );

    testWidgets(
      'Multiple Choice stays disabled with fewer than 4 distinct species names',
      (tester) async {
        final mockNotificationService = createMockNotificationService();

        // Default test deck has a single species, far below the 4-distinct-
        // name threshold required to enable Multiple Choice review.
        await startApp(
          tester,
          notificationService: mockNotificationService,
          withTestDeck: true,
        );

        await tester.tap(
          find.descendant(
            of: find.byType(Card).first,
            matching: find.byIcon(Icons.edit_square),
          ),
        );
        await safePumpAndSettle(tester);
        expect(find.byKey(const Key('edit_deck_save_button')), findsOneWidget);

        final reviewModeButtonFinder = find.byKey(
          const Key('review_mode_segmented_button'),
        );
        await tester.scrollUntilVisible(
          reviewModeButtonFinder,
          300,
          scrollable: find.byType(Scrollable).first,
        );

        final reviewModeButton = tester.widget<SegmentedButton<ReviewMode>>(
          reviewModeButtonFinder,
        );
        final multipleChoiceSegment = reviewModeButton.segments.firstWhere(
          (segment) => segment.value == ReviewMode.multipleChoice,
        );
        expect(multipleChoiceSegment.enabled, isFalse);

        expect(
          find.textContaining('Multiple choice needs at least 4 species'),
          findsOneWidget,
        );
      },
      timeout: integrationTestTimeout,
    );
  });
}
