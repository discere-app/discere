import 'package:flutter_test/flutter_test.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets('Smoke test: verify app starts and shows correct title',
      (WidgetTester tester) async {
    final mockNotificationService = createMockNotificationService();

    await startApp(tester, notificationService: mockNotificationService);

    expect(find.text('Discere'), findsOneWidget);
  });
}
