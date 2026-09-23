import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

/// Covers only the deck-level config/stat/notification surface shared across
/// decks/, app/, and flashcard/ — see
/// test/learning/flashcard/flashcard_review_service_test.dart for the actual
/// review-engine behavior (grading, due-card sourcing, photo gaps, image
/// resolution), which now lives on the separate FlashcardReviewService.
void main() {
  late MockFlashcardStatRepository mockFlashcardStatRepo;
  late MockNotificationService mockNotificationService;
  late FlashcardService service;

  setUp(() {
    mockFlashcardStatRepo = MockFlashcardStatRepository();
    mockNotificationService = MockNotificationService();

    when(
      mockFlashcardStatRepo.getAllNextReviewDates(),
    ).thenAnswer((_) async => []);
    when(mockNotificationService.cancelAllScheduled()).thenAnswer((_) async {});
    when(mockNotificationService.hasPermission()).thenAnswer((_) async => true);
    when(
      mockNotificationService.scheduleAt(
        when: anyNamed('when'),
        title: anyNamed('title'),
        body: anyNamed('body'),
        payload: anyNamed('payload'),
      ),
    ).thenAnswer((_) async {});

    service = FlashcardService(mockFlashcardStatRepo, mockNotificationService);
  });

  group('FlashcardService.getDeckStat', () {
    test('delegates to FlashcardStatRepository.getDeckStat', () async {
      when(
        mockFlashcardStatRepo.getDeckStat('deck1'),
      ).thenAnswer((_) async => DeckStat(20, 5, 0));

      final result = await service.getDeckStat('deck1');

      verify(mockFlashcardStatRepo.getDeckStat('deck1')).called(1);
      expect(result.totalCount, 20);
      expect(result.uninitializedCount, 5);
    });
  });

  group('FlashcardService.rescheduleNotifications', () {
    test('clears the pending series before scheduling a new one', () async {
      await service.rescheduleNotifications(
        notificationTitle: 'Title',
        notificationBodyBuilder: (count) => 'Body $count',
      );

      verify(mockFlashcardStatRepo.getAllNextReviewDates()).called(1);
      verify(mockNotificationService.cancelAllScheduled()).called(1);
    });

    test('schedules nothing when notifications are not permitted', () async {
      when(
        mockNotificationService.hasPermission(),
      ).thenAnswer((_) async => false);
      when(
        mockFlashcardStatRepo.getAllNextReviewDates(),
      ).thenAnswer((_) async => [DateTime.now().add(const Duration(days: 1))]);

      await service.rescheduleNotifications();

      verifyNever(
        mockNotificationService.scheduleAt(
          when: anyNamed('when'),
          title: anyNamed('title'),
          body: anyNamed('body'),
          payload: anyNamed('payload'),
        ),
      );
    });

    test('posts one reminder per day that has cards due', () async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      when(mockFlashcardStatRepo.getAllNextReviewDates()).thenAnswer(
        (_) async => [
          DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8),
          DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9),
        ],
      );

      await service.rescheduleNotifications(
        notificationTitle: 'Title',
        notificationBodyBuilder: (count) => 'Body $count',
      );

      verify(
        mockNotificationService.scheduleAt(
          when: anyNamed('when'),
          title: 'Title',
          body: 'Body 2',
          payload: anyNamed('payload'),
        ),
      ).called(1);
    });
  });
}
