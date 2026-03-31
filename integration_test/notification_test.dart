import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:discere/service/common/notification_service.dart';
import 'package:discere/model/learning/flash_card_stat.dart';
import 'package:timezone/data/latest_all.dart' as tz;

Future<void> _grantPermissions() async {
  if (!Platform.isAndroid) return;
  const package = 'ch.feberle.discere';
  const permissions = [
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.SCHEDULE_EXACT_ALARM',
  ];
  for (final perm in permissions) {
    await Process.run(
      'adb',
      ['shell', 'pm', 'grant', package, perm],
      runInShell: true,
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  setUpAll(() async {
    await _grantPermissions();
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
    await service.rescheduleAll(
      allCards: [
        FlashCardStat(
          speciesId: 'sp1', 
          deckId: 'd1', 
          nextReviewDate: DateTime.now().add(const Duration(minutes: 10))
        ),
      ],
      preferredHour: DateTime.now().hour, 
      preferredMinute: DateTime.now().minute + 5, // A bit in the future
      title: 'Integration Test Title',
      bodyBuilder: (count) => 'You have $count cards',
    );

    // 4. Verify the notification was scheduled
    final pending = await service.notificationsPlugin.pendingNotificationRequests();
    expect(pending.isNotEmpty, true);
    
    // Note: Since NotificationService rounds to the next 30-minute interval, 
    // the title/body might be null if it just uses the defaults or if 
    // the specific method doesn't pass them in properly, but in this case 
    // we passed them directly.
    expect(pending.any((req) => req.title == 'Integration Test Title'), true);

    // 5. Cleanup
    await service.notificationsPlugin.cancelAll();
  });
}
