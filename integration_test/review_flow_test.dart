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

    await app.main(notificationService: mockNotificationService);
    await tester.pumpAndSettle();

    // Create a very small deck first to ensure it's fast (avoiding large image downloads in emulator)
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    
    final deckName = 'Review Test Deck';
    await tester.enterText(find.widgetWithText(TextField, 'Name'), deckName);
    await tester.enterText(find.widgetWithText(TextField, 'Scientific names of the species'), 'Amphiprion ocellaris');
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
      if (find.text('Recognized').evaluate().isNotEmpty || 
          find.byIcon(Icons.thumb_up).evaluate().isNotEmpty) {
        foundCard = true;
        break;
      }
    }
    expect(foundCard, isTrue, reason: "Flashcard interaction buttons ('Recognized') did not appear within 60 seconds");

    // 3. Tap 'Recognized' (Correct answer)
    await tester.tap(find.text('Recognized'));
    await tester.pumpAndSettle();

    // 4. Verify completion dialog or back on home
    // Since it's a 1-card deck, it should show a completion dialog
    final okButton = find.text('OK');
    if (okButton.evaluate().isNotEmpty) {
      await tester.tap(okButton);
      await tester.pumpAndSettle();
    }
    
    // Final check: we should be back on a screen that doesn't have 'Recognized' anymore
    expect(find.text('Recognized'), findsNothing);
  });
}
