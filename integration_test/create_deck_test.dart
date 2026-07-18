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

        // 4. Verify the image picker's gallery button
        final galleryButton = find.byIcon(Icons.photo_library_outlined);
        await tester.dragUntilVisible(
          galleryButton,
          find.byType(CustomScrollView),
          const Offset(0, -200),
        );
        await safePumpAndSettle(tester);
        expect(galleryButton, findsWidgets);
      },
      timeout: integrationTestTimeout,
    );
  });
}
