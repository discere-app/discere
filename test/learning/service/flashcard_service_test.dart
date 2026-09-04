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
    when(
      mockNotificationService.rescheduleAll(
        cardDueDates: anyNamed('cardDueDates'),
        preferredHour: anyNamed('preferredHour'),
        preferredMinute: anyNamed('preferredMinute'),
        daysAhead: anyNamed('daysAhead'),
        title: anyNamed('title'),
        bodyBuilder: anyNamed('bodyBuilder'),
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
    test('reads all due dates and reschedules once', () async {
      await service.rescheduleNotifications(
        notificationTitle: 'Title',
        notificationBodyBuilder: (count) => 'Body $count',
      );

      verify(mockFlashcardStatRepo.getAllNextReviewDates()).called(1);
      verify(
        mockNotificationService.rescheduleAll(
          cardDueDates: anyNamed('cardDueDates'),
          preferredHour: anyNamed('preferredHour'),
          preferredMinute: anyNamed('preferredMinute'),
          daysAhead: anyNamed('daysAhead'),
          title: 'Title',
          bodyBuilder: anyNamed('bodyBuilder'),
        ),
      ).called(1);
    });
  });
}
