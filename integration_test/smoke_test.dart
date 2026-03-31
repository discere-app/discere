import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'test_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Smoke test: verify app starts and shows correct title',
      (WidgetTester tester) async {
    final mockNotificationService = createMockNotificationService();

    await startApp(tester, notificationService: mockNotificationService);

    expect(find.text('Discere'), findsOneWidget);
  });
}
