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
}
