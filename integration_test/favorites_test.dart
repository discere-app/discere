import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets(
    'Favorites Interaction: toggle favorite and verify in tab',
    (WidgetTester tester) async {
      final mockNotificationService = createMockNotificationService();
      const String targetDeck = 'Test Deck';

      await startApp(
        tester,
        notificationService: mockNotificationService,
        withTestDeck: true,
      );

      debugPrint('-- TEST: finding deck card --');
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
      debugPrint('-- TEST: tapping favorite button --');
      await tester.ensureVisible(favoriteButton);
      await safePumpAndSettle(tester);
      await tester.tap(favoriteButton);
      await safePumpAndSettle(tester);

      // 3. Switch to Favorites tab
      debugPrint('-- TEST: switching to favorites tab --');
      await tester.tap(find.byKey(const ValueKey('nav-favourites')));
      await safePumpAndSettle(tester);

      // 4. Verify it's there
      debugPrint('-- TEST: verifying deck in favorites tab --');
      final favoritesDeckFinder = find.text(targetDeck);
      await tester.scrollUntilVisible(
        favoritesDeckFinder,
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(favoritesDeckFinder, findsAtLeastNWidgets(1));

      // 5. Unfavorite from here
      debugPrint('-- TEST: unfavoriting deck --');
      final unfavoriteButton = find.descendant(
        of: find.ancestor(
          of: favoritesDeckFinder.last,
          matching: find.byType(Card),
        ),
        matching: find.byIcon(Icons.favorite),
      );
      await tester.tap(unfavoriteButton);
      await safePumpAndSettle(tester);

      // 6. Verify it's gone from favorites
      debugPrint('-- TEST: verifying deck is removed from favorites --');
      expect(find.text(targetDeck), findsNothing);
    },
    timeout: integrationTestTimeout,
  );
}
