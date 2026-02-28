import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:discere/main.dart' as app;
import 'package:mockito/mockito.dart';
import 'mocks.mocks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Deck Lifecycle: create and delete a deck',
      (WidgetTester tester) async {
    final mockNotificationService = MockNotificationService();
    when(mockNotificationService.requestPermissions()).thenAnswer((_) async {});

    await app.main(notificationService: mockNotificationService);
    await tester.pumpAndSettle();

    // 1. Tap the '+' FAB
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // 2. Fill in the Create Deck Dialog
    final deckName = 'Test Integration Deck';
    await tester.enterText(find.widgetWithText(TextField, 'Name'), deckName);
    await tester.enterText(find.widgetWithText(TextField, 'Description'), 'Integration test description');
    await tester.enterText(find.widgetWithText(TextField, 'Scientific names of the species'), 'Amphiprion ocellaris');
    
    // 3. Tap 'Create'
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // 4. Verify the new deck is in the list
    expect(find.text(deckName), findsOneWidget);

    // 5. Delete the deck (Swipe right to left)
    final deckCard = find.widgetWithText(Card, deckName).first;
    await tester.drag(deckCard, const Offset(-500, 0));
    await tester.pumpAndSettle();

    // 6. Verify the deck is removed
    expect(find.text(deckName), findsNothing);
  });
}
