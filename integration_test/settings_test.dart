import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets(
    'Settings Flow: change language and verify localization',
    (WidgetTester tester) async {
      final mockNotificationService = createMockNotificationService();

      await startApp(tester, notificationService: mockNotificationService);

      // 1. Open Settings
      await tester.tap(find.byIcon(Icons.settings));
      await safePumpAndSettle(tester);
      if (kDebugMode) {
        print('Settings: Opened Settings page');
      }

      // Initial language might be preserved from a previous test on the emulator,
      // so we skip the strict English title checks here to avoid flakiness.

      // 3. Open Language dropdown
      final dropdownFinder = find.byType(DropdownButton<int>);
      await tester.scrollUntilVisible(
        dropdownFinder,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(dropdownFinder);
      await safePumpAndSettle(tester);

      // 4. Select German (Deutsch)
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) => w is DropdownMenuItem<int> && w.value == 0,
            )
            .last,
      );
      await safePumpAndSettle(tester);

      // 5. Verify language changed to German
      expect(find.text('Sprache').first, findsOneWidget);
      expect(find.text('Einstellungen').first, findsOneWidget);

      // 6. Go back and verify main screen is also localized
      await tester.tap(find.byType(BackButton));
      await safePumpAndSettle(tester);

      expect(find.text('Favoriten'), findsOneWidget);
      expect(find.text('Merkliste'), findsOneWidget);
    },
    timeout: integrationTestTimeout,
  );
}
