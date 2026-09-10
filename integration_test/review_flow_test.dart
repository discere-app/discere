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
      await openDeck(tester, deckName);

      // 1.1 Handle activation dialog if it appears
      final titleFinder = find.byKey(const Key('activation_dialog_title'));

      if (titleFinder.evaluate().isNotEmpty) {
        final yesButton = find.byKey(const Key('activation_dialog_yes_button'));
        await tester.tap(yesButton);
        await waitForAbsence(
          tester,
          find.byKey(const Key('activation_dialog_title')),
          description: 'the activation dialog to close once the batch is ready',
        );
      }

      // 2. Wait for first card (card initialization is DB-only, should be fast)
      await waitForFinder(
        tester,
        find.byIcon(Icons.thumb_up_rounded),
        description: 'the flashcard grading buttons to render',
      );

      // 3. Tap Easy (Correct answer)
      await tester.tap(find.byIcon(Icons.thumb_up_rounded));
      await safePumpAndSettle(tester);

      // 4. Verify completion dialog or back on home
      // Since it's a 1-card deck, it should show a completion dialog. Grading
      // triggers an async getDeckStat before the dialog is built, so wait for
      // either the dialog or (if it's fast enough to not need waiting) the
      // review screen already being gone, instead of checking immediately.
      final okButton = find.text('OK');
      final thumbUpFinder = find.byIcon(Icons.thumb_up_rounded);
      await waitForCondition(
        tester,
        () =>
            okButton.evaluate().isNotEmpty || thumbUpFinder.evaluate().isEmpty,
        description: 'the session to end or its completion dialog to appear',
      );
      if (okButton.evaluate().isNotEmpty) {
        await tester.tap(okButton);
        await safePumpAndSettle(tester);
      }

      // Final check: we should be back on a screen that doesn't have the explicit button anymore
      await waitForAbsence(tester, thumbUpFinder);
      expect(thumbUpFinder, findsNothing);
    },
    timeout: integrationTestTimeout,
  );
}
