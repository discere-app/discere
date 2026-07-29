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

  testWidgets(
    'Flashcard Review Flow: open deck and answer cards',
    (WidgetTester tester) async {
      final mockNotificationService = createMockNotificationService();

      final deckName = 'Review Test Deck';
      await startApp(
        tester,
        notificationService: mockNotificationService,
        withTestDeck: true,
        deckName: deckName,
      );

      // 1. Open the deck
      final deckFinder = find.text(deckName);

      // Use the robust utility if needed, but for now simple scroll works
      await tester.scrollUntilVisible(
        deckFinder,
        500.0,
        scrollable: find.descendant(
          of: find.byKey(const Key('home_deck_list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(deckFinder.last);
      await safePumpAndSettle(tester);

      // 1.1 Handle activation dialog if it appears
      final titleFinder = find.byKey(const Key('activation_dialog_title'));

      if (titleFinder.evaluate().isNotEmpty) {
        final yesButton = find.byKey(const Key('activation_dialog_yes_button'));
        await tester.tap(yesButton);
        await safePumpAndSettle(tester);
      }

      // 2. Wait for first card (card initialization is DB-only, should be fast)
      bool foundCard = false;
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.byIcon(Icons.thumb_up_rounded).evaluate().isNotEmpty) {
          foundCard = true;
          break;
        }
      }
      expect(
        foundCard,
        isTrue,
        reason:
            'Flashcard interaction buttons (Thumb Up Rounded) did not appear within 10 seconds',
      );

      // 3. Tap Easy (Correct answer)
      await tester.tap(find.byIcon(Icons.thumb_up_rounded));
      await safePumpAndSettle(tester);

      // 4. Verify completion dialog or back on home
      // Since it's a 1-card deck, it should show a completion dialog
      final okButton = find.text('OK');
      if (okButton.evaluate().isNotEmpty) {
        await tester.tap(okButton);
        await safePumpAndSettle(tester);
      }

      // Final check: we should be back on a screen that doesn't have the explicit button anymore
      final thumbUpFinder = find.byIcon(Icons.thumb_up_rounded);
      await waitForAbsence(tester, thumbUpFinder);
      expect(thumbUpFinder, findsNothing);
    },
    timeout: integrationTestTimeout,
  );
}
