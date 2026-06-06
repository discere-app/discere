import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:discere/shared/persistence/database_helper.dart';
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

        expect(find.textContaining('Amphiprion ocellaris'), findsAtLeastNWidgets(1));
        expect(find.textContaining('anemonefish'), findsAtLeastNWidgets(1));

        // 4. Verify Image Picker buttons (scroll back up to cover image section)
        final searchButton = find.byKey(
          const Key('image_picker_search_button'),
        );

        await tester.scrollUntilVisible(
          searchButton,
          -300.0,
          scrollable: find.byType(Scrollable).first,
        );
        await safePumpAndSettle(tester);

        expect(
          find.byIcon(Icons.photo_library_outlined),
          findsWidgets,
        ); // Gallery button
        expect(
          find.byIcon(Icons.image_search_outlined),
          findsWidgets,
        ); // Search button

        // 5. Open Image Search Sheet
        await safePumpAndSettle(tester);
        await tester.tap(searchButton);
        await safePumpAndSettle(tester);

        // 6. Verify Search Sheet is open
        expect(
          find.byKey(const Key('image_search_sheet_title')),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsWidgets);

        // Close the sheet
        final closeButton = find.byIcon(Icons.close).last;
        await tester.tap(closeButton);
        await safePumpAndSettle(tester);

        await safePumpAndSettle(tester);
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
  });
}
