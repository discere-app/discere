import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:discere/main.dart' as app;
import 'package:mockito/mockito.dart';
import 'mocks.mocks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Auto-init bug test: respects user choice and prompts correctly',
      (WidgetTester tester) async {
    final mockNotificationService = MockNotificationService();
    when(mockNotificationService.initNotification()).thenAnswer((_) async {});
    when(mockNotificationService.requestPermissions()).thenAnswer((_) async {});

    await app.main(notificationService: mockNotificationService);
    await tester.pumpAndSettle();

    // 1. Create a deck with 2 species
    await tester.tap(find.byKey(const ValueKey('main-fab')));
    await tester.pumpAndSettle();
    
    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.pumpAndSettle();
    
    final deckName = 'Auto Init Test Deck';
    await tester.enterText(find.byKey(const Key('create_deck_name_field')), deckName);
    
    final speciesFieldFinder = find.byKey(const Key('create_deck_species_field'));
    await tester.scrollUntilVisible(
      speciesFieldFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Use two species
    await tester.enterText(speciesFieldFinder, 'Amphiprion ocellaris\nAbramis brama');
    await tester.tap(find.byKey(const ValueKey('create_deck_submit_button')));
    await tester.pumpAndSettle();

    // 2. Open the deck. It should see 0 due but 2 uninitialized.
    // My fix should trigger the "Activate more cards" dialog immediately.
    final deckFinder = find.text(deckName);
    await tester.scrollUntilVisible(
      deckFinder,
      500.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(deckFinder.last);
    await tester.pumpAndSettle();

    // Verify dialog appears. Check for German or English title.
    final titleFinder = find.byElementPredicate((element) {
      if (element.widget is Text) {
        final text = (element.widget as Text).data;
        return text == 'Es sind momentan keine weiteren Karten zu lernen bereit' ||
               text == 'There are currently no more cards to learn';
      }
      return false;
    });
    expect(titleFinder, findsOneWidget);
    
    // Click "Yes" to initialize (Check for "Ja" or "Yes")
    final yesButton = find.byElementPredicate((element) {
      if (element.widget is Text) {
        final text = (element.widget as Text).data;
        return text == 'Ja' || text == 'Yes';
      }
      return false;
    });
    await tester.tap(yesButton);
    await tester.pumpAndSettle();

    // 3. Review the first card
    // Wait for buttons
    bool foundButtons = false;
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byIcon(Icons.thumb_up_rounded).evaluate().isNotEmpty) {
        foundButtons = true;
        break;
      }
    }
    expect(foundButtons, isTrue);

    // Answer "Good" (Thumb up)
    await tester.tap(find.byIcon(Icons.thumb_up_rounded));
    await tester.pumpAndSettle();

    // Since there are 2 cards in the batch, it should show the 2nd one.
    // Answer "Good" on the 2nd one too.
    await tester.tap(find.byIcon(Icons.thumb_up_rounded));
    await tester.pumpAndSettle();

    // Now all 2 cards in the batch are finished.
    // Since there are no more uninitialized cards in the deck (total 2),
    // it should show the "No more cards to learn" dialog.
    final noMoreTitleFinder = find.byElementPredicate((element) {
      if (element.widget is Text) {
        final text = (element.widget as Text).data;
        return text == 'Keine weiteren Karten verfügbar' ||
               text == 'No more cards available';
      }
      return false;
    });
    expect(noMoreTitleFinder, findsOneWidget);
    
    // Click OK and go back
    final okButton = find.byElementPredicate((element) {
      if (element.widget is Text) {
        final text = (element.widget as Text).data;
        return text == 'OK';
      }
      return false;
    });
    await tester.tap(okButton);
    await tester.pumpAndSettle();

    // Back on home. Now wait some time? (Fractional days mean it might be due in hours/days).
    // Re-open the deck.
    await tester.tap(deckFinder.last);
    await tester.pumpAndSettle();

    // 4. Verify that since 0 are due and 0 are uninitialized, NO dialog is shown.
    // It should just show "No flashcards available".
    final noFlashcardsFound = find.byElementPredicate((element) {
      if (element.widget is Text) {
        final text = (element.widget as Text).data;
        return text == 'Keine Lernkarten verfügbar' ||
               text == 'no flashcards available';
      }
      return false;
    });
    expect(noFlashcardsFound, findsOneWidget);
    expect(titleFinder, findsNothing);
  });
}
