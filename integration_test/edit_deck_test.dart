
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:discere/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  group('Edit Deck Page', () {
    testWidgets('can navigate to Edit Deck and see Cover Image options',
        (tester) async {
      await app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 1. Create a deck to edit
      final fab = find.byKey(const ValueKey('main-fab'));
      await tester.tap(fab);
      await tester.pumpAndSettle();

      final createButton = find.byIcon(Icons.create_new_folder_outlined);
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Deck Name'), 'Test Edit Deck');
      await tester.tap(find.text('Create Deck'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 2. Locate the created deck to edit
      final deckCardFinder = find.byType(Card);
      expect(deckCardFinder, findsWidgets, reason: 'Expected at least one deck card on home screen');
      
      final deckCard = deckCardFinder.first;

      // 3. Tap Edit on the deck
      final editButton = find.descendant(
        of: deckCard,
        matching: find.byIcon(Icons.edit_square),
      );
      expect(editButton, findsOneWidget, reason: 'Expected an edit button on the deck card');
      await tester.tap(editButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      // 3. Verify labels on Edit Deck Page
      expect(find.text('Edit Deck'), findsOneWidget);
      expect(find.text('Cover Image'), findsOneWidget);

      // 4. Verify Image Picker buttons
      expect(find.byIcon(Icons.photo_library_outlined), findsWidgets); // Gallery button
      expect(find.byIcon(Icons.image_search_outlined), findsWidgets);  // Search button

      // 5. Open Image Search Sheet
      final searchButton = find.ancestor(
        of: find.text('Search Images'),
        matching: find.byType(OutlinedButton),
      );
      await tester.dragUntilVisible(
        searchButton,
        find.byType(CustomScrollView),
        const Offset(0, -200),
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
