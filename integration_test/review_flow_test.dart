import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:discere/main.dart' as app;
import 'package:mockito/mockito.dart';
import 'mocks.mocks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Flashcard Review Flow: open deck and answer cards',
      (WidgetTester tester) async {
    final mockNotificationService = MockNotificationService();
    when(mockNotificationService.requestPermissions()).thenAnswer((_) async {});

    await app.main();
    await tester.pumpAndSettle();

    // Create a very small deck first to ensure it's fast (avoiding large image downloads in emulator)
    await tester.tap(find.byKey(const ValueKey('main-fab')));
    await tester.pumpAndSettle();
    
    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.pumpAndSettle();
    
    final deckName = 'Review Test Deck';
    await tester.enterText(find.byKey(const Key('create_deck_name_field')), deckName);
    // For off-screen fields inside a CustomScrollView, ensure they are visible
    final speciesFieldFinder = find.byKey(const Key('create_deck_species_field'));
    await tester.scrollUntilVisible(
      speciesFieldFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(speciesFieldFinder, 'Amphiprion ocellaris');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // 1. Open the deck
    await tester.tap(find.text(deckName).first);
    await tester.pumpAndSettle();

    // 2. Wait for first card (might take some time for image attempt)
    // We use a 60s timeout because emulator might be slow with image timeouts
    bool foundCard = false;
    for (int i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byIcon(Icons.thumb_up_rounded).evaluate().isNotEmpty) {
        foundCard = true;
        break;
      }
    }
    expect(foundCard, isTrue, reason: "Flashcard interaction buttons (Thumb Up Rounded) did not appear within 60 seconds");

    // 3. Tap Easy (Correct answer)
    await tester.tap(find.byIcon(Icons.thumb_up_rounded));
    await tester.pumpAndSettle();

    // 4. Verify completion dialog or back on home
    // Since it's a 1-card deck, it should show a completion dialog
    final okButton = find.text('OK');
    if (okButton.evaluate().isNotEmpty) {
      await tester.tap(okButton);
      await tester.pumpAndSettle();
    }
    
    // Final check: we should be back on a screen that doesn't have the explicit button anymore
    expect(find.byIcon(Icons.thumb_up_rounded), findsNothing);
  });
}
