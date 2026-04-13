import 'package:flutter_test/flutter_test.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'test_utils.dart';

class FakeNotificationPermissionHandler extends NotificationPermissionHandler {
  FakeNotificationPermissionHandler({
    required this.initialStatus,
    this.requestResult = PermissionStatus.denied,
  });

  PermissionStatus initialStatus;
  PermissionStatus requestResult;
  int requestCallCount = 0;

  @override
  Future<PermissionStatus> status() async => initialStatus;

  @override
  Future<PermissionStatus> request() async {
    requestCallCount++;
    initialStatus = requestResult;
    return requestResult;
  }
}

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets('NotificationService schedules a notification successfully',
      (WidgetTester tester) async {
    tz.initializeTimeZones();
    final service = NotificationService();

    // 1. Initialize notification service
    await service.initNotification();

    // 2. Clear out any existing pending notifications
    await service.notificationsPlugin.cancelAll();

    // 3. Schedule daily notifications (simulating some due cards)
    final now = DateTime.now();
    await service.rescheduleAll(
      cardDueDates: [now.add(const Duration(minutes: 10))],
      preferredHour: now.hour,
      preferredMinute: now.minute + 5, // A bit in the future
      title: 'Integration Test Title',
      bodyBuilder: (count) => 'You have $count cards',
    );

    // 4. Verify the notification was scheduled
    final pending = await service.notificationsPlugin.pendingNotificationRequests();
    expect(pending.isNotEmpty, true);

    // Verify that the title matches one of the scheduled notifications.
    expect(pending.any((req) => req.title == 'Integration Test Title'), true);

    // 5. Cleanup
    await service.notificationsPlugin.cancelAll();
  });

  testWidgets(
    'NotificationService requests notification permission only once after a denial',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final permissionHandler = FakeNotificationPermissionHandler(
        initialStatus: PermissionStatus.denied,
      );
      final service = NotificationService(
        preferences: prefs,
        permissionHandler: permissionHandler,
      );

      await service.requestPermissions();
      await service.requestPermissions();

      expect(permissionHandler.requestCallCount, 1);
      expect(prefs.getBool('notification_permission_requested'), true);
    },
  );
}
