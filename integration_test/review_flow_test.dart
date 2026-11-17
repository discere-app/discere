import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  group('review flow', () {
    setUp(() async {
      await resetTestState();
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

        // 2. Grade the first card Easy (correct answer) as soon as its buttons
        // are there (card initialization is DB-only, so this is fast)
        await tapWhenHitTestable(
          tester,
          find.byIcon(Icons.thumb_up_rounded),
          description: 'the flashcard grading buttons to render',
        );
        await safePumpAndSettle(tester);

        // 3. Verify completion dialog or back on home
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
          await tapWhenHitTestable(tester, okButton);
          await safePumpAndSettle(tester);
        }

        // Final check: we should be back on a screen that doesn't have the explicit button anymore
        await waitForAbsence(
          tester,
          thumbUpFinder,
          description: 'the review screen to be left behind',
        );
        expect(thumbUpFinder, findsNothing);
      },
      timeout: integrationTestTimeout,
    );
  });
}
