import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets('Species Search: verify search functionality',
      (WidgetTester tester) async {
    final mockNotificationService = createMockNotificationService();

    await startApp(tester, notificationService: mockNotificationService);

    // 1. Tap the Search Icon in the AppBar
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    // 2. Enter search query
    final String query = 'Carcharodon carcharias';
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle(); // Wait for debouncing/suggestions

    // 3. Wait for search results to appear in a ListView
    bool resultsFound = false;
    for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.textContaining('Carcharodon').evaluate().isNotEmpty) {
            resultsFound = true;
            break;
        }
    }
    expect(resultsFound, isTrue, reason: "Search results for '$query' did not appear within 5 seconds");

    // 4. Tap the first result containing 'Carcharodon'
    final resultItem = find.textContaining('Carcharodon').first;
    await tester.tap(resultItem);
    await tester.pumpAndSettle(); // Wait for navigation animation

    // 5. Wait for the details page to load (DB lookup, should be fast)
    bool detailsLoaded = false;
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.textContaining('carcharias').evaluate().isNotEmpty ||
          find.textContaining('Class:').evaluate().isNotEmpty) {
        detailsLoaded = true;
        break;
      }
    }
    expect(detailsLoaded, isTrue, reason: "Species Detail page did not load for '$query' within 10 seconds");
  });
}
