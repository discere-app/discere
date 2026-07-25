import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets(
    'Watchlist Flow:add from deck and remove from watchlist',
    (WidgetTester tester) async {
      final mockNotificationService = createMockNotificationService();

      final deckName = 'Watchlist Test Deck';
      await startApp(
        tester,
        notificationService: mockNotificationService,
        withTestDeck: true,
        deckName: deckName,
      );

      // 2. Open the deck
      final deckFinder = find.text(deckName);
      await tester.scrollUntilVisible(
        deckFinder,
        500.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(deckFinder.last);
      await safePumpAndSettle(tester);

      // 2.1 Handle activation dialog if it appears
      final titleFinder = find.byKey(const Key('activation_dialog_title'));

      if (titleFinder.evaluate().isNotEmpty) {
        final yesButton = find.byKey(const Key('activation_dialog_yes_button'));
        await tester.tap(yesButton);
        await safePumpAndSettle(tester);
      }

      // 2.2 Wait until flashcard is loaded (auto-init is async, needs real time)
      for (int i = 0; i < 5; i++) {
        await safePumpAndSettle(tester);
        if (find.byIcon(Icons.thumb_up_rounded).evaluate().isNotEmpty) break;
      }
      expect(
        find.byIcon(Icons.thumb_up_rounded),
        findsOneWidget,
        reason: 'Flashcard not loaded; deck auto-initialization may have failed',
      );

      // 3. Add current card to watchlist via bookmark button
      await tester.tap(find.byIcon(Icons.bookmark_border).first);
      await safePumpAndSettle(tester);

      // 4. Go back to Home
      await tester.tap(find.byType(BackButton));
      await safePumpAndSettle(tester);

      // 5. Navigate to Watchlist tab
      await tester.tap(find.byKey(const ValueKey('nav-watchlist')));
      await safePumpAndSettle(tester);

      // 6. Verify species is in watchlist with common and scientific name
      final watchlistCommonNameFinder = find.textContaining(
        'Clown anemonefish',
      );
      final watchlistSpeciesFinder = find.textContaining(
        'Amphiprion ocellaris',
      );

      // Wait for WatchlistPage FutureBuilder (resolveAllWithDownload) to complete.
      // It may attempt image downloads (50ms timeout each), so we poll instead
      // of relying on a fixed number of safePumpAndSettle calls.
      for (int i = 0; i < 15; i++) {
        await safePumpAndSettle(tester);
        if (watchlistCommonNameFinder.evaluate().isNotEmpty) break;
      }

      expect(
        watchlistCommonNameFinder,
        findsAtLeastNWidgets(1),
        reason: 'Species not found in watchlist after polling; '
            'watchlist may be empty or resolveAllWithDownload returned null',
      );

      await tester.scrollUntilVisible(
        watchlistCommonNameFinder.first,
        500.0,
        scrollable: find.byType(Scrollable).last,
      );
      expect(watchlistSpeciesFinder, findsAtLeastNWidgets(1));
      if (kDebugMode) {
        print('Watchlist: Species found in list');
      }

      // 7. Remove from watchlist (Swipe right to left)
      final speciesCard = find.ancestor(
        of: watchlistSpeciesFinder.last,
        matching: find.byType(Dismissible),
      );
      await tester.fling(speciesCard, const Offset(-500, 0), 1000);
      await safePumpAndSettle(tester);
      if (kDebugMode) {
        print('Watchlist: Swipe performed');
      }

      // 8. Verify it's gone
      expect(find.textContaining('Clown anemonefish'), findsNothing);
      expect(find.textContaining('Amphiprion ocellaris'), findsNothing);
      if (kDebugMode) {
        print('Watchlist: Species successfully removed');
      }
    },
    timeout: integrationTestTimeout,
  );
}
