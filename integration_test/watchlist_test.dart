import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets('Watchlist Flow: add from deck and remove from watchlist', (
    WidgetTester tester,
  ) async {
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
    await tester.pumpAndSettle();

    // 2.1 Handle activation dialog if it appears
    final titleFinder = find.byKey(const Key('activation_dialog_title'));

    if (titleFinder.evaluate().isNotEmpty) {
      final yesButton = find.byKey(const Key('activation_dialog_yes_button'));
      await tester.tap(yesButton);
      await tester.pumpAndSettle();
    }

    // 3. Add current card to watchlist via popup menu
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('deck_popup_watchlist_add')));
    await tester.pumpAndSettle();

    // 4. Go back to Home
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // 5. Navigate to Watchlist tab
    await tester.tap(find.byKey(const ValueKey('nav-watchlist')));
    await tester.pumpAndSettle();

    // 6. Verify species is in watchlist with common and scientific name
    final watchlistCommonNameFinder = find.textContaining('Clown anemonefish');
    final watchlistSpeciesFinder = find.textContaining('Amphiprion ocellaris');
    await tester.scrollUntilVisible(
      watchlistCommonNameFinder.first,
      500.0,
      scrollable: find.byType(Scrollable).last,
    );
    expect(watchlistCommonNameFinder, findsAtLeastNWidgets(1));
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
    expect(find.textContaining('Clown anemonefish'), findsNothing);
    expect(find.textContaining('Amphiprion ocellaris'), findsNothing);
    if (kDebugMode) {
      print('Watchlist: Species successfully removed');
    }
  });
}
