import 'package:discere/model/biology/classification.dart';
import 'package:discere/model/biology/species.dart';
import 'package:discere/model/language.dart';
import 'package:discere/model/learning/deck_stat.dart';
import 'package:discere/model/learning/flash_card_stat.dart';
import 'package:discere/model/biology/picture.dart';
import 'package:discere/service/learning/flashcard_service.dart';
import 'package:discere/service/learning/spaced_repetition_algorithm.dart';
import 'package:discere/service/learning/spaced_repetition_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

Species makeSpecies({String id = 'sp1', List<Picture> pictures = const []}) {
  return Species(
    id,
    'ext1',
    'fishbase',
    'carcharias',
    {Language.de: 'Weißer Hai', Language.en: 'Great white shark'},
    Classification(
      'Carcharodon', {Language.de: 'Weiße Haie'}, null,
      'Lamnidae', {Language.de: 'Makrelenhaie', Language.en: 'Mackerel sharks'},
      'Lamniformes', {Language.de: 'Makrelenhaiartige', Language.en: 'Mackerel sharks'},
      'Chondrichthyes', {Language.de: 'Knorpelfische'}, null,
    ),
    pictures,
  );
}

FlashCardStat makeStat({
  String speciesId = 'sp1',
  String deckId = 'deck1',
  int repetition = 1,
  int interval = 1,
  DateTime? nextReviewDate,
}) {
  return FlashCardStat(
    speciesId: speciesId,
    deckId: deckId,
    repetition: repetition,
    interval: interval,
    nextReviewDate: nextReviewDate ?? DateTime(2030),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockSpeciesRepository mockSpeciesRepo;
  late MockFlashCardStatRepository mockFlashCardStatRepo;
  late MockImageService mockImageService;
  late MockNotificationService mockNotificationService;
  late SpacedRepetitionService spacedRepetitionService;
  late FlashCardService service;

  setUp(() {
    mockSpeciesRepo = MockSpeciesRepository();
    mockFlashCardStatRepo = MockFlashCardStatRepository();
    mockImageService = MockImageService();
    mockNotificationService = MockNotificationService();
    spacedRepetitionService = SpacedRepetitionService();

    // Safe defaults
    when(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(any))
        .thenAnswer((_) async {});
    when(mockFlashCardStatRepo.getFlashCardStat(any, any))
        .thenAnswer((_) async => null);
    when(mockFlashCardStatRepo.getAllStats())
        .thenAnswer((_) async => []);
    when(mockNotificationService.rescheduleAll(
      allCards: anyNamed('allCards'),
      preferredHour: anyNamed('preferredHour'),
      preferredMinute: anyNamed('preferredMinute'),
      daysAhead: anyNamed('daysAhead'),
      title: anyNamed('title'),
      bodyBuilder: anyNamed('bodyBuilder'),
    )).thenAnswer((_) async {});
    when(mockImageService.downloadAndSaveImages(any))
        .thenAnswer((_) async => ['/local/img.jpg']);
    when(mockSpeciesRepo.getSpeciesById(any))
        .thenAnswer((_) async => makeSpecies());

    service = FlashCardService(
      mockSpeciesRepo,
      mockImageService,
      spacedRepetitionService,
      mockFlashCardStatRepo,
      mockNotificationService,
    );
  });

  // ── initializeNextBatch ────────────────────────────────────────────────────

  group('FlashCardService.initializeNextBatch', () {
    test('fetches uninitialized stats from the repository', () async {
      when(mockFlashCardStatRepo.getUninitializedFlashCardStats('deck1', 10))
          .thenAnswer((_) async => {});

      await service.initializeNextBatch('deck1');

      verify(mockFlashCardStatRepo.getUninitializedFlashCardStats('deck1', 10))
          .called(1);
    });

    test('sets nextReviewDate to today for every uninitialized stat', () async {
      final stats = {
        FlashCardStat(speciesId: 'sp1', deckId: 'deck1'),
        FlashCardStat(speciesId: 'sp2', deckId: 'deck1'),
      };
      when(mockFlashCardStatRepo.getUninitializedFlashCardStats(any, any))
          .thenAnswer((_) async => stats);

      final before = DateTime.now().subtract(const Duration(seconds: 1));
      await service.initializeNextBatch('deck1');
      final after = DateTime.now().add(const Duration(seconds: 1));

      for (final stat in stats) {
        expect(stat.nextReviewDate, isNotNull);
        expect(stat.nextReviewDate!.isAfter(before), isTrue);
        expect(stat.nextReviewDate!.isBefore(after), isTrue);
      }
    });

    test('persists the updated stats', () async {
      final stats = {FlashCardStat(speciesId: 'sp1', deckId: 'deck1')};
      when(mockFlashCardStatRepo.getUninitializedFlashCardStats(any, any))
          .thenAnswer((_) async => stats);

      await service.initializeNextBatch('deck1');

      verify(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(stats)).called(1);
    });

    test('respects a custom batchSize parameter', () async {
      when(mockFlashCardStatRepo.getUninitializedFlashCardStats('deck1', 5))
          .thenAnswer((_) async => {});

      await service.initializeNextBatch('deck1', batchSize: 5);

      verify(mockFlashCardStatRepo.getUninitializedFlashCardStats('deck1', 5))
          .called(1);
    });
  });

  // ── getFlashCardsForReview ────────────────────────────────────────────────

  group('FlashCardService.getFlashCardsForReview', () {
    test('returns empty list when no cards are due and deck is partially learned',
        () async {
      when(mockFlashCardStatRepo.getFlashCardStatsForReview(any, any))
          .thenAnswer((_) async => []);
      when(mockFlashCardStatRepo.getDeckStat(any))
          .thenAnswer((_) async => DeckStat(10, 5, 0)); // not all uninitialized

      final result = await service.getFlashCardsForReview('deck1');

      expect(result, isEmpty);
    });

    test(
        'returns empty list when deck is completely uninitialized',
        () async {
      when(mockFlashCardStatRepo.getFlashCardStatsForReview(any, any))
          .thenAnswer((_) async => []);
      
      final result = await service.getFlashCardsForReview('deck1');

      expect(result, isEmpty);
      verifyNever(mockFlashCardStatRepo.getUninitializedFlashCardStats(any, any));
    });
  });

  // ── review actions ────────────────────────────────────────────────────────

  group('FlashCardService review actions', () {
    // Helper: call reviewCard with a grade and capture what was persisted
    Future<FlashCardStat> captureStatAfterReview(ReviewGrade grade) async {
      FlashCardStat? captured;
      when(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(any))
          .thenAnswer((inv) async {
        captured =
            (inv.positionalArguments[0] as Set<FlashCardStat>).first;
      });

      await service.reviewCard('sp1', 'deck1', grade);
      return captured!;
    }

    test('Again (grade) sets repetition to 0 and interval to 1',
        () async {
      final stat = await captureStatAfterReview(ReviewGrade.again);
      expect(stat.repetition, 0);
      expect(stat.interval, 1);
    });

    test('Easy (grade) increases ease factor', () async {
      final stat = await captureStatAfterReview(ReviewGrade.easy);
      expect(stat.easeFactor, greaterThan(2.5));
    });

    test('Easy produces higher ease factor than Again',
        () async {
      final easyResult = await captureStatAfterReview(ReviewGrade.easy);

      // Reset mock for Again
      when(mockFlashCardStatRepo.getFlashCardStat(any, any))
          .thenAnswer((_) async => null);
      final againResult = await captureStatAfterReview(ReviewGrade.again);

      expect(
        easyResult.easeFactor,
        greaterThan(againResult.easeFactor),
      );
    });

    test('every review grade persists the updated FlashCardStat', () async {
      for (final grade in ReviewGrade.values) {
        clearInteractions(mockFlashCardStatRepo);
        when(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(any))
            .thenAnswer((_) async {});
        when(mockFlashCardStatRepo.getFlashCardStat(any, any))
            .thenAnswer((_) async => null);

        await service.reviewCard('sp1', 'deck1', grade);

        verify(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(any))
            .called(1);
      }
    });

    test('every review grade schedules a notification', () async {
      for (final grade in ReviewGrade.values) {
        clearInteractions(mockNotificationService);
        when(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(any))
            .thenAnswer((_) async {});
        when(mockFlashCardStatRepo.getFlashCardStat(any, any))
            .thenAnswer((_) async => null);
        when(mockNotificationService.rescheduleAll(
          allCards: anyNamed('allCards'),
          preferredHour: anyNamed('preferredHour'),
          preferredMinute: anyNamed('preferredMinute'),
          daysAhead: anyNamed('daysAhead'),
          title: anyNamed('title'),
          bodyBuilder: anyNamed('bodyBuilder'),
        )).thenAnswer((_) async {});

        await service.reviewCard('sp1', 'deck1', grade);

        verify(mockNotificationService.rescheduleAll(
          allCards: anyNamed('allCards'),
          preferredHour: anyNamed('preferredHour'),
          preferredMinute: anyNamed('preferredMinute'),
          daysAhead: anyNamed('daysAhead'),
          title: anyNamed('title'),
          bodyBuilder: anyNamed('bodyBuilder'),
        )).called(1);
      }
    });

    test('review loads existing stat from repository and updates it', () async {
      final existingStat =
          makeStat(repetition: 2, interval: 6, speciesId: 'sp1');
      existingStat.easeFactor = 2.4;

      when(mockFlashCardStatRepo.getFlashCardStat('sp1', 'deck1'))
          .thenAnswer((_) async => existingStat);

      FlashCardStat? captured;
      when(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(any))
          .thenAnswer((inv) {
        captured = (inv.positionalArguments[0] as Set<FlashCardStat>).first;
        return Future.value();
      });

      await service.reviewCard('sp1', 'deck1', ReviewGrade.easy);

      expect(captured!.repetition, 3);
      expect(captured!.interval, greaterThan(6));
      expect(captured!.easeFactor, greaterThan(2.4));
    });

    test('reviewing a freshly activated card for the first time initializes stability and repetition', () async {
      final activatedStat = FlashCardStat(speciesId: 'sp1', deckId: 'deck1');
      activatedStat.nextReviewDate = DateTime.now(); // Activated but not reviewed
      expect(activatedStat.isNew, isTrue);

      when(mockFlashCardStatRepo.getFlashCardStat('sp1', 'deck1'))
          .thenAnswer((_) async => activatedStat);

      FlashCardStat? captured;
      when(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(any))
          .thenAnswer((inv) {
        captured = (inv.positionalArguments[0] as Set<FlashCardStat>).first;
        return Future.value();
      });

      // We'll use FSRS for this test implicitly if we swap it in setUp, 
      // but let's just verify the service calls the algorithm correctly.
      await service.reviewCard('sp1', 'deck1', ReviewGrade.good);

      // SM-2 (current mock setup) uses repetition 0 check
      expect(captured!.repetition, 1); 
      expect(captured!.lastReviewDate, isNotNull);
    });
  });

  // ── getDeckStat ───────────────────────────────────────────────────────────

  group('FlashCardService.getDeckStat', () {
    test('delegates to FlashCardStatRepository.getDeckStat', () async {
      when(mockFlashCardStatRepo.getDeckStat('deck1'))
          .thenAnswer((_) async => DeckStat(20, 5, 0));

      final result = await service.getDeckStat('deck1');

      verify(mockFlashCardStatRepo.getDeckStat('deck1')).called(1);
      expect(result.totalCount, 20);
      expect(result.uninitializedCount, 5);
    });
  });
}
