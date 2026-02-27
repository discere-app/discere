import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:discere/main.dart' as app;
import 'package:mockito/mockito.dart';
import 'mocks.mocks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Favorites Interaction: toggle favorite and verify in tab',
      (WidgetTester tester) async {
    final mockNotificationService = MockNotificationService();
    when(mockNotificationService.requestPermissions()).thenAnswer((_) async {});

    await app.main(notificationService: mockNotificationService);
    await tester.pumpAndSettle();

    // 1. Find a deck and heart icon (using first deck in dummy list)
    const String targetDeck = 'Haie';
    final favoriteButton = find.descendant(
      of: find.ancestor(of: find.text(targetDeck), matching: find.byType(Card)),
      matching: find.byIcon(Icons.favorite_border),
    );
    expect(favoriteButton, findsOneWidget);
    
    // 2. Tap to favorite
    await tester.tap(favoriteButton);
    await tester.pumpAndSettle();

    // 3. Switch to Favorites tab
    await tester.tap(find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.byIcon(Icons.favorite_border),
    ));
    await tester.pumpAndSettle();

    // 4. Verify it's there
    expect(find.text(targetDeck), findsOneWidget);

    // 5. Unfavorite from here
    final unfavoriteButton = find.descendant(
      of: find.ancestor(of: find.text(targetDeck), matching: find.byType(Card)),
      matching: find.byIcon(Icons.favorite),
    );
    await tester.tap(unfavoriteButton);
    await tester.pumpAndSettle();

    // 6. Verify it's gone from favorites
    expect(find.text(targetDeck), findsNothing);
  });
}
