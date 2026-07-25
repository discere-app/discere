import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets('About page shows a licenses section that opens the license page', (
    tester,
  ) async {
    final mockNotificationService = createMockNotificationService();
    await startApp(tester, notificationService: mockNotificationService);

    // Navigate to Settings
    await tester.tap(find.byIcon(Icons.settings).last);
    await safePumpAndSettle(tester);

    // Tap on About
    final aboutTile = find.byKey(const Key('settings_about_tile'));
    expect(aboutTile, findsOneWidget);
    await tester.tap(aboutTile);
    await safePumpAndSettle(tester);

    // Scroll to the Licenses section and open it
    final scrollable = find.byType(Scrollable).last;
    final licensesButton = find.widgetWithText(OutlinedButton, 'Show licenses');
    await tester.scrollUntilVisible(licensesButton, 200.0, scrollable: scrollable);
    expect(licensesButton, findsOneWidget);

    await tester.tap(licensesButton);
    await safePumpAndSettle(tester);

    // Verify the built-in license page opened
    expect(find.byType(LicensePage), findsOneWidget);

    // Go back to the About page
    await tester.tap(find.byType(BackButton));
    await safePumpAndSettle(tester);

    expect(find.text('About Discere'), findsOneWidget);
  }, timeout: integrationTestTimeout);
}
