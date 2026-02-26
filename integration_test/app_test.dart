import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:discere/main.dart' as app;
import 'package:discere/service/common/notification_service.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<NotificationService>()])
import 'app_test.mocks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Smoke test: verify app starts and shows correct title', (WidgetTester tester) async {
    final mockNotificationService = MockNotificationService();
    when(mockNotificationService.initNotification()).thenAnswer((_) async {});
    when(mockNotificationService.requestPermissions()).thenAnswer((_) async {});

    // Start the app with a mock service that doesn't trigger native dialogs
    await app.main(notificationService: mockNotificationService);

    // Give the app time to fully render the first frame and settle animations
    // The permission dialog might show up here depending on os versions,
    // but the Flutter tree should still be fully pumped underneath it.
    await tester.pumpAndSettle();

    // Verify that the title 'Discere AquaLife' is present in the AppBar
    expect(find.text('Discere AquaLife'), findsOneWidget);
  });

  testWidgets('Deck Lifecycle: create and delete a deck', (WidgetTester tester) async {
    final mockNotificationService = MockNotificationService();
    when(mockNotificationService.initNotification()).thenAnswer((_) async {});
    when(mockNotificationService.requestPermissions()).thenAnswer((_) async {});

    await app.main(notificationService: mockNotificationService);
    await tester.pumpAndSettle();

    // 1. Open Create Deck Dialog
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    await tester.tap(fab);
    await tester.pumpAndSettle();

    // 2. Fill in the form (using English strings from app_en.arb)
    final String testDeckName = 'Test Integration Deck';
    await tester.enterText(find.widgetWithText(TextField, 'Name'), testDeckName);
    await tester.enterText(find.widgetWithText(TextField, 'Description'), 'Description for integration test');
    await tester.enterText(find.widgetWithText(TextField, 'Scientific names of the species'), 'Amphiprion ocellaris\nPremnas biaculeatus');
    await tester.pumpAndSettle();

    // 3. Tap 'Create'
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // 4. Verify Deck exists in list
    expect(find.text(testDeckName), findsOneWidget);

    // 5. Delete the deck (Swipe right to left)
    // Find the ListTile containing the deck name
    final deckItem = find.ancestor(
      of: find.text(testDeckName),
      matching: find.byType(Dismissible),
    );
    expect(deckItem, findsOneWidget);

    // Perform swipe
    await tester.drag(deckItem, const Offset(-500.0, 0.0));
    await tester.pumpAndSettle();

    // 6. Verify Deck is gone
    expect(find.text(testDeckName), findsNothing);
  });

  testWidgets('Favorites Interaction: toggle favorite and verify in tab', (WidgetTester tester) async {
    final mockNotificationService = MockNotificationService();
    when(mockNotificationService.initNotification()).thenAnswer((_) async {});
    when(mockNotificationService.requestPermissions()).thenAnswer((_) async {});

    await app.main(notificationService: mockNotificationService);
    await tester.pumpAndSettle();

    // 1. Identify a deck on Home tab (should have 'Haie' from dummy data)
    final String targetDeck = 'Haie';
    expect(find.text(targetDeck), findsOneWidget);

    // 2. Tap the favorite icon for this deck
    // The favorite icon is in a trailing IconButton of the ListTile
    final favoriteButton = find.descendant(
      of: find.ancestor(of: find.text(targetDeck), matching: find.byType(Card)),
      matching: find.byType(IconButton),
    );
    expect(favoriteButton, findsOneWidget);
    await tester.tap(favoriteButton);
    await tester.pumpAndSettle();

    // 3. Switch to Favorites tab
    await tester.tap(find.text('Favourites'));
    await tester.pumpAndSettle();

    // 4. Verify deck is in Favorites tab
    expect(find.text(targetDeck), findsOneWidget);

    // 5. Remove from favorites
    final unfavoriteButton = find.descendant(
      of: find.ancestor(of: find.text(targetDeck), matching: find.byType(Card)),
      matching: find.byType(IconButton),
    );
    await tester.tap(unfavoriteButton);
    await tester.pumpAndSettle();

    // 6. Verify deck is gone from Favorites tab
    expect(find.text(targetDeck), findsNothing);
    
    // 7. Go back to Home and verify it's still there (but unfavorited)
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text(targetDeck), findsOneWidget);
  });

  testWidgets('Flashcard Review Flow: open deck and answer cards', (WidgetTester tester) async {
    final mockNotificationService = MockNotificationService();
    when(mockNotificationService.initNotification()).thenAnswer((_) async {});
    when(mockNotificationService.requestPermissions()).thenAnswer((_) async {});

    await app.main(notificationService: mockNotificationService);
    await tester.pumpAndSettle();

    // 1. Create a small deck first to ensure fast image downloads (if any)
    final String reviewDeckName = 'Review Test Deck';
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), reviewDeckName);
    await tester.enterText(find.widgetWithText(TextField, 'Scientific names of the species'), 'Amphiprion ocellaris');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // 2. Open the newly created deck
    await tester.tap(find.text(reviewDeckName));
    await tester.pumpAndSettle();

    // 3. Wait for cards to load (FutureBuilder)
    // It might take a moment if it tries to download even 1 image
    await tester.pumpAndSettle(const Duration(seconds: 5));
    
    // 4. Test 'Recognized' button (Thumb up)
    final recognizedButton = find.text('Recognized');
    expect(recognizedButton, findsOneWidget);
    await tester.tap(recognizedButton);
    await tester.pumpAndSettle();
    
    // 5. Test 'Not Recognized' button (Thumb down)
    // (If the deck only had 1 card, we might see the completion dialog now)
    final okButton = find.text('OK');
    if (okButton.evaluate().isNotEmpty) {
      await tester.tap(okButton);
      await tester.pumpAndSettle();
    } else {
      final notRecognizedButton = find.text('Not Recognized');
      expect(notRecognizedButton, findsOneWidget);
      await tester.tap(notRecognizedButton);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Species Search: verify search functionality', (WidgetTester tester) async {
    final mockNotificationService = MockNotificationService();
    when(mockNotificationService.initNotification()).thenAnswer((_) async {});
    when(mockNotificationService.requestPermissions()).thenAnswer((_) async {});

    await app.main(notificationService: mockNotificationService);
    await tester.pumpAndSettle();

    // 1. Tap the Search Icon in the AppBar
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    // 2. Enter search query
    final String query = 'Carcharodon carcharias';
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle(); // Wait for debouncing/suggestions
 

    // 3. Wait for search results to appear in a ListView
    bool resultsFound = false;
    for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.textContaining('Carcharodon').evaluate().isNotEmpty) {
            resultsFound = true;
            break;
        }
    }
    expect(resultsFound, isTrue, reason: "Search results for '$query' did not appear within 20 seconds");

    // 4. Tap the first result containing 'Carcharodon'
    final resultItem = find.textContaining('Carcharodon').first;
    await tester.tap(resultItem);
    await tester.pumpAndSettle(); // Wait for navigation animation

    // 5. Wait for the details page to load (look for the binomial name fragment or taxonomy)
    bool detailsLoaded = false;
    for (int i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.textContaining('carcharias').evaluate().isNotEmpty || 
          find.textContaining('Class:').evaluate().isNotEmpty) {
        detailsLoaded = true;
        break;
      }
    }
    expect(detailsLoaded, isTrue, reason: "Species Detail page did not load for '$query' within 60 seconds");
  });
}
}
