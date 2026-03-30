import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:discere/main.dart' as app;
import 'package:mockito/mockito.dart';
import 'mocks.mocks.dart';
import 'test_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Deck Lifecycle: create and delete a deck',
      (WidgetTester tester) async {
    final mockNotificationService = createMockNotificationService();

    await app.main(notificationService: mockNotificationService);
    setScreenSize(tester);
    await tester.pumpAndSettle();

    // 1. Tap the '+' FAB and select Create New Deck
    await tester.tap(find.byKey(const ValueKey('main-fab')));
    await tester.pumpAndSettle();
    
    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.pumpAndSettle();

    // 2. Fill in the Create Deck Dialog
    final deckName = 'Test Integration Deck';
    await tester.enterText(find.byKey(const Key('create_deck_name_field')), deckName);
    await tester.enterText(find.byKey(const Key('create_deck_description_field')), 'Integration test description');
    // For off-screen fields inside a CustomScrollView, ensure they are visible
    final speciesFieldFinder = find.byKey(const Key('create_deck_species_field'));
    await tester.scrollUntilVisible(
      speciesFieldFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(speciesFieldFinder, 'Amphiprion ocellaris');
    
    // 3. Tap 'Create'
    await tester.tap(find.byKey(const ValueKey('create_deck_submit_button')));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 4. Verify the new deck is in the list
    final deckFinder = find.text(deckName);
    await tester.scrollUntilVisible(
      deckFinder,
      500.0,
      scrollable: find.byType(Scrollable).first,
    );
    expect(deckFinder, findsAtLeastNWidgets(1));

    // 5. Delete the deck (Fling right to left)
    final deckCard = deckFinder.last;
    await tester.fling(deckCard, const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1)); // Wait for Dismissible animation

    // 6. Verify the deck is removed
    expect(find.text(deckName), findsNothing);
    // 7. Flush any remaining animations from the SnackBar
    await tester.pump(const Duration(seconds: 5));
  });
}
