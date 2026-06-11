import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  group('Create Deck Page', () {
    testWidgets(
      'can navigate to Create Deck and see Cover Image options',
      (tester) async {
        final mockNotificationService = createMockNotificationService();

        await startApp(tester, notificationService: mockNotificationService);

        // 1. Open FAB
        final fab = find.byKey(const ValueKey('main-fab'));
        await tester.tap(fab);
        await safePumpAndSettle(tester);

        // 2. Tap Create Deck
        final createButton = find.byIcon(Icons.create_new_folder_outlined);
        await tester.tap(createButton);
        await safePumpAndSettle(tester);

        // 3. Verify labels on Create Deck Page
        expect(find.text('Create New Deck'), findsOneWidget);
        expect(find.text('Cover Image'), findsOneWidget);

        // 4. Verify Image Picker buttons
        expect(
          find.byIcon(Icons.photo_library_outlined),
          findsWidgets,
        ); // Gallery button
        expect(
          find.byIcon(Icons.image_search_outlined),
          findsWidgets,
        ); // Search button

        // 5. Open Image Search Sheet
        final searchButton = find.ancestor(
          of: find.text('Search Images'),
          matching: find.byType(OutlinedButton),
        );
        await tester.dragUntilVisible(
          searchButton,
          find.byType(CustomScrollView),
          const Offset(0, -200),
        );
        await safePumpAndSettle(tester);
        await tester.tap(searchButton);
        await safePumpAndSettle(tester);

        // 6. Verify Search Sheet is open
        expect(
          find.byKey(const Key('image_search_sheet_title')),
          findsOneWidget,
        );
        // TextField might be inside a layout widget that obscures it or has multiples
        expect(find.byType(TextField), findsWidgets);
      },
      timeout: integrationTestTimeout,
    );
  });
}
