import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:discere/main.dart' as app;
import 'package:mockito/mockito.dart';
import 'mocks.mocks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Watchlist Flow: add from deck and remove from watchlist',
      (WidgetTester tester) async {
    final mockNotificationService = MockNotificationService();
    when(mockNotificationService.initNotification()).thenAnswer((_) async {});
    when(mockNotificationService.requestPermissions()).thenAnswer((_) async {});

    await app.main(notificationService: mockNotificationService);
    await tester.pumpAndSettle();

    // 1. Create a deck to have something to add from
    await tester.tap(find.byKey(const ValueKey('main-fab')));
    await tester.pumpAndSettle();
    
    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.pumpAndSettle();
    
    final deckName = 'Watchlist Test Deck';
    await tester.enterText(find.byKey(const Key('create_deck_name_field')), deckName);
    // For off-screen fields inside a CustomScrollView, ensure they are visible
    final speciesFieldFinder = find.byKey(const Key('create_deck_species_field'));
    await tester.scrollUntilVisible(
      speciesFieldFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(speciesFieldFinder, 'Amphiprion ocellaris');
    await tester.tap(find.byKey(const ValueKey('create_deck_submit_button')));
    await tester.pumpAndSettle();

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
