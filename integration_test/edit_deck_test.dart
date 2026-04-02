import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  group('Edit Deck Page', () {
    testWidgets('can navigate to Edit Deck and see Cover Image options',
        (tester) async {
      final mockNotificationService = createMockNotificationService();

      await startApp(tester,
          notificationService: mockNotificationService, withTestDeck: true);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 2. Locate the created deck to edit
      final deckCardFinder = find.byType(Card);
      expect(deckCardFinder, findsWidgets,
          reason: 'Expected at least one deck card on home screen');

      final deckCard = deckCardFinder.first;

      // 3. Tap Edit on the deck
      final editButton = find.descendant(
        of: deckCard,
        matching: find.byIcon(Icons.edit_square),
      );
      expect(editButton, findsOneWidget,
          reason: 'Expected an edit button on the deck card');
      await tester.tap(editButton);
      // Wait for navigation and potential database loading
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // 3. Verify labels on Edit Deck Page (using Icons/Keys where possible)
      // We expect the title to be 'Edit Deck', but we can also verify by the Save button key
      expect(find.byKey(const Key('edit_deck_save_button')), findsOneWidget);

      // 4. Verify Image Picker buttons
      expect(find.byIcon(Icons.photo_library_outlined),
          findsWidgets); // Gallery button
      expect(find.byIcon(Icons.image_search_outlined),
          findsWidgets); // Search button

      // 5. Open Image Search Sheet
      final searchButton = find.byKey(const Key('image_picker_search_button'));
      
      await tester.scrollUntilVisible(
        searchButton,
        300.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(searchButton);

      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      // 6. Verify Search Sheet is open
      expect(find.text('Search Wikimedia'), findsWidgets);
      expect(find.byType(TextField), findsWidgets);

      // Close the sheet
      final closeButton = find.byIcon(Icons.close).last;
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      // Final cleanup
      await tester.pumpWidget(Container());
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
