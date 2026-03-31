import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'test_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Watchlist Flow: add from deck and remove from watchlist',
      (WidgetTester tester) async {
    final mockNotificationService = createMockNotificationService();

    final deckName = 'Watchlist Test Deck';
    await startApp(tester,
        notificationService: mockNotificationService,
        withTestDeck: true,
        deckName: deckName);

    // 2. Open the deck
    final deckFinder = find.text(deckName);
    await tester.scrollUntilVisible(
      deckFinder,
      500.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(deckFinder.last);
    await tester.pumpAndSettle();

    // 2.1 Handle activation dialog if it appears (My new feature)
    final titleFinder = find.byElementPredicate((element) {
      if (element.widget is Text) {
        final text = (element.widget as Text).data;
        return text == 'Es sind momentan keine weiteren Karten zu lernen bereit' ||
               text == 'There are currently no more cards to learn';
      }
      return false;
    });
    
    if (titleFinder.evaluate().isNotEmpty) {
      final yesButton = find.byElementPredicate((element) {
        if (element.widget is Text) {
          final text = (element.widget as Text).data;
          return text == 'Ja' || text == 'Yes';
        }
        return false;
      });
      await tester.tap(yesButton);
      await tester.pumpAndSettle();
    }

    // 3. Add current card to watchlist via popup menu
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    
    // Robust finder for "Add to watchlist" / "zu Merkliste hinzufügen"
    final addToWatchlistFinder = find.byElementPredicate((element) {
      if (element.widget is Text) {
        final text = (element.widget as Text).data;
        return text == 'Add to watchlist' || text == 'zu Merkliste hinzufügen';
      }
      return false;
    });
    await tester.tap(addToWatchlistFinder);
    await tester.pumpAndSettle();

    // 4. Go back to Home
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // 5. Navigate to Watchlist tab
    await tester.tap(find.byKey(const ValueKey('nav-watchlist')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2)); // Wait for WatchList FutureBuilder
    
    // 6. Verify species is in watchlist
    final watchlistSpeciesFinder = find.textContaining('Amphiprion ocellaris');
    await tester.scrollUntilVisible(
      watchlistSpeciesFinder.first,
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
      matching: find.byType(Card),
    );
    await tester.fling(speciesCard, const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
    if (kDebugMode) {
      print('Watchlist: Swipe performed');
    }

    // 8. Verify it's gone
    expect(find.textContaining('Amphiprion ocellaris'), findsNothing);
    if (kDebugMode) {
      print('Watchlist: Species successfully removed');
    }
  });
}
