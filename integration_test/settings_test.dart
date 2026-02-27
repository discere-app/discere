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

    await app.main(notificationService: mockNotificationService);
    await tester.pumpAndSettle();

    // 1. Open Settings
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    print('Settings: Opened Settings page');

    // 2. Verify English title
    expect(find.text('Language').first, findsOneWidget);
    expect(find.text('Settings').first, findsOneWidget);

    // 3. Open Language dropdown
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();

    // 4. Select German (Deutsch)
    await tester.tap(find.text('German').last);
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
