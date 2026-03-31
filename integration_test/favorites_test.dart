import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'test_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Favorites Interaction: toggle favorite and verify in tab',
      (WidgetTester tester) async {
    final mockNotificationService = createMockNotificationService();
    const String targetDeck = 'Test Deck';

    await startApp(tester,
        notificationService: mockNotificationService, withTestDeck: true);

    final deckFinder = find.text(targetDeck);
    await tester.scrollUntilVisible(
      deckFinder,
      500.0,
      scrollable: find.byType(Scrollable).first,
    );
    final favoriteButton = find.descendant(
      of: find.ancestor(of: deckFinder, matching: find.byType(Card)),
      matching: find.byIcon(Icons.favorite_border),
    );
    expect(favoriteButton, findsOneWidget);
    
    // 2. Tap to favorite
    await tester.ensureVisible(favoriteButton);
    await tester.pumpAndSettle();
    await tester.tap(favoriteButton);
    await tester.pumpAndSettle();

    // 3. Switch to Favorites tab
    await tester.tap(find.byKey(const ValueKey('nav-favourites')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2)); // Wait for DecksView FutureBuilder

    // 4. Verify it's there
    // Ensure we are showing the list, not the "No decks" message
    final scrollableFinder = find.byType(Scrollable);
    int retry = 0;
    while (tester.any(scrollableFinder) == false && retry < 10) {
      await tester.pump(const Duration(milliseconds: 500));
      retry++;
    }

    final favoritesDeckFinder = find.text(targetDeck);
    await tester.scrollUntilVisible(
      favoritesDeckFinder,
      500.0,
      scrollable: scrollableFinder.first,
    );
    expect(favoritesDeckFinder, findsAtLeastNWidgets(1));

    // 5. Unfavorite from here
    final unfavoriteButton = find.descendant(
      of: find.ancestor(of: favoritesDeckFinder.last, matching: find.byType(Card)),
      matching: find.byIcon(Icons.favorite),
    );
    await tester.tap(unfavoriteButton);
    await tester.pumpAndSettle();

    // 6. Verify it's gone from favorites
    expect(find.text(targetDeck), findsNothing);
  });
}
