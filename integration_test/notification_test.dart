import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:discere/service/common/notification_service.dart';
import 'package:discere/model/learning/flash_card_stat.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'test_utils.dart';

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
      allCards: [
        FlashCardStat(
          speciesId: 'sp1', 
          deckId: 'd1', 
          nextReviewDate: now.add(const Duration(minutes: 10))
        ),
      ],
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
}
