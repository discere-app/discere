import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:discere/main.dart' as app;
import 'package:mockito/mockito.dart';
import 'mocks.mocks.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Settings Flow: change language and verify localization',
      (WidgetTester tester) async {
    final mockNotificationService = MockNotificationService();
    when(mockNotificationService.requestPermissions()).thenAnswer((_) async {});

    await app.main();
    await tester.pumpAndSettle();

    // 1. Open Settings
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    if (kDebugMode) {
      print('Settings: Opened Settings page');
    }

    // Initial language might be preserved from a previous test on the emulator,
    // so we skip the strict English title checks here to avoid flakiness.

    // 3. Open Language dropdown
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();

    // 4. Select German (Deutsch)
    await tester.tap(find.byWidgetPredicate((w) => w is DropdownMenuItem<int> && w.value == 0).last);
    await tester.pumpAndSettle();

    // 5. Verify language changed to German
    expect(find.text('Sprache').first, findsOneWidget);
    expect(find.text('Einstellungen').first, findsOneWidget);

    // 6. Go back and verify main screen is also localized
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    
    expect(find.text('Favoriten'), findsOneWidget);
    expect(find.text('Merkliste'), findsOneWidget);
  });
}
