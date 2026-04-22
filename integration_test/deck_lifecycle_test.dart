import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets('Deck Lifecycle: create and delete a deck', (
    WidgetTester tester,
  ) async {
    final mockNotificationService = createMockNotificationService();

    await startApp(tester, notificationService: mockNotificationService);

    // 1. Tap the '+' FAB and select Create New Deck
    debugPrint('-- TEST: tapping main-fab --');
    await tester.tap(find.byKey(const ValueKey('main-fab')));
    await tester.pumpAndSettle();

    debugPrint('-- TEST: tapping create icon --');
    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.pumpAndSettle();

    // 2. Fill in the Create Deck Dialog
    final deckName = 'Test Integration Deck';
    await tester.enterText(
      find.byKey(const Key('create_deck_name_field')),
      deckName,
    );
    await tester.enterText(
      find.byKey(const Key('create_deck_description_field')),
      'Integration test description',
    );

    // For off-screen fields inside a CustomScrollView, ensure they are visible
    final speciesFieldFinder = find.byKey(
      const Key('create_deck_species_field'),
    );
    await tester.scrollUntilVisible(
      speciesFieldFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(speciesFieldFinder, 'Amphiprion ocellaris');

    // 3. Tap 'Create'
    debugPrint('-- TEST: tapping create_deck_submit_button --');
    await tester.tap(find.byKey(const ValueKey('create_deck_submit_button')));

    // Handle the mandatory download dialog
    debugPrint('-- TEST: dismissing iNat download dialog --');
    await dismissDownloadDialog(tester);

    // 4. Verify the new deck is in the list
    debugPrint('-- TEST: verifying new deck is in list --');
    final deckFinder = find.text(deckName);
    await tester.scrollUntilVisible(
      deckFinder,
      500.0,
      scrollable: find.byType(Scrollable).first,
    );
    expect(deckFinder, findsAtLeastNWidgets(1));

    // 5. Delete the deck (Fling right to left)
    debugPrint('-- TEST: swiping to delete deck --');
    final deckCard = find.ancestor(
      of: find.text(deckName),
      matching: find.byType(Dismissible),
    );
    expect(deckCard, findsOneWidget);

    // Swipe from right to left to trigger delete
    await tester.drag(deckCard, const Offset(-500, 0));
    await tester.pumpAndSettle();

    // 5.1 Confirm Deletion in Dialog
    debugPrint('-- TEST: confirming deletion dialog --');
    final confirmButton = find.byKey(const Key('delete_deck_confirm_button'));
    expect(confirmButton, findsOneWidget);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    // 6. Verify the deck is removed
    debugPrint('-- TEST: verifying deck is removed --');
    expect(find.text(deckName), findsNothing);
  }, timeout: integrationTestTimeout);
}
