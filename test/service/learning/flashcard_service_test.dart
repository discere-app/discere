import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/service/spaced_repetition_algorithm.dart';
import 'package:discere/learning/service/spaced_repetition_service.dart';
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
    {
      Language.de: ['Weißer Hai'],
      Language.en: ['Great white shark'],
    },
    Classification(
      'Carcharodon',
      {
        Language.de: ['Weiße Haie'],
      },
      null,
      'Lamnidae',
      {
        Language.de: ['Makrelenhaie'],
        Language.en: ['Mackerel sharks'],
      },
      'Lamniformes',
      {
        Language.de: ['Makrelenhaiartige'],
        Language.en: ['Mackerel sharks'],
      },
      'Chondrichthyes',
      {
        Language.de: ['Knorpelfische'],
      },
      null,
    ),
    pictures,
  );
}

FlashcardStat makeStat({
  String speciesId = 'sp1',
  String deckId = 'deck1',
  int repetition = 1,
  int interval = 1,
  DateTime? nextReviewDate,
}) {
  return FlashcardStat(
    speciesId: speciesId,
    deckId: deckId,
    repetition: repetition,
    interval: interval,
    nextReviewDate: nextReviewDate ?? DateTime(2030),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockSpeciesMediaService mockSpeciesMediaService;
  late MockFlashcardStatRepository mockFlashcardStatRepo;
  late MockNotificationService mockNotificationService;
  late SpacedRepetitionService spacedRepetitionService;
  late FlashcardService service;

  setUp(() {
    mockSpeciesMediaService = MockSpeciesMediaService();
    mockFlashcardStatRepo = MockFlashcardStatRepository();
    mockNotificationService = MockNotificationService();
    spacedRepetitionService = SpacedRepetitionService();

    // Safe defaults
    when(
      mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any),
    ).thenAnswer((_) async {});
    when(
      mockFlashcardStatRepo.getFlashcardStat(any, any),
    ).thenAnswer((_) async => null);
    when(mockFlashcardStatRepo.getAllStats()).thenAnswer((_) async => []);
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
    when(
      mockSpeciesMediaService.resolveWithDownload(any),
    ).thenAnswer((_) async => SpeciesWithLocalImages(makeSpecies(), []));

    service = FlashcardService(
      spacedRepetitionService,
      mockFlashcardStatRepo,
      mockNotificationService,
      mockSpeciesMediaService,
    );
  });

  // ── initializeNextBatch ────────────────────────────────────────────────────

  group('FlashcardService.initializeNextBatch', () {
    test('fetches uninitialized stats from the repository', () async {
      when(
        mockFlashcardStatRepo.getUninitializedFlashcardStats('deck1', 10),
      ).thenAnswer((_) async => {});

      await service.initializeNextBatch('deck1');

      verify(
        mockFlashcardStatRepo.getUninitializedFlashcardStats('deck1', 10),
      ).called(1);
    });

    test('sets nextReviewDate to today for every uninitialized stat', () async {
      final stats = {
        FlashcardStat(speciesId: 'sp1', deckId: 'deck1'),
        FlashcardStat(speciesId: 'sp2', deckId: 'deck1'),
      };
      when(
        mockFlashcardStatRepo.getUninitializedFlashcardStats(any, any),
      ).thenAnswer((_) async => stats);

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
      final stats = {FlashcardStat(speciesId: 'sp1', deckId: 'deck1')};
      when(
        mockFlashcardStatRepo.getUninitializedFlashcardStats(any, any),
      ).thenAnswer((_) async => stats);

      await service.initializeNextBatch('deck1');

      verify(
        mockFlashcardStatRepo.insertOrUpdateFlashcardStats(stats),
      ).called(1);
    });

    test('respects a custom batchSize parameter', () async {
      when(
        mockFlashcardStatRepo.getUninitializedFlashcardStats('deck1', 5),
      ).thenAnswer((_) async => {});

      await service.initializeNextBatch('deck1', batchSize: 5);

      verify(
        mockFlashcardStatRepo.getUninitializedFlashcardStats('deck1', 5),
      ).called(1);
    });
  });

  // ── getFlashCardsForReview ────────────────────────────────────────────────

  group('FlashcardService.getFlashCardsForReview', () {
    test(
      'returns empty list when no cards are due and deck is partially learned',
      () async {
        when(
          mockFlashcardStatRepo.getFlashcardStatsForReview(any, any),
        ).thenAnswer((_) async => []);
        when(
          mockFlashcardStatRepo.getDeckStat(any),
        ).thenAnswer((_) async => DeckStat(10, 5, 0)); // not all uninitialized

        final result = await service.getFlashCardsForReview('deck1');

        expect(result, isEmpty);
      },
    );

    test('returns empty list when deck is completely uninitialized', () async {
      when(
        mockFlashcardStatRepo.getFlashcardStatsForReview(any, any),
      ).thenAnswer((_) async => []);

      final result = await service.getFlashCardsForReview('deck1');

      expect(result, isEmpty);
      verifyNever(
        mockFlashcardStatRepo.getUninitializedFlashcardStats(any, any),
      );
    });
  });

  // ── review actions ────────────────────────────────────────────────────────

  group('FlashcardService review actions', () {
    // Helper: call reviewCard with a grade and capture what was persisted
    Future<FlashcardStat> captureStatAfterReview(ReviewGrade grade) async {
      FlashcardStat? captured;
      when(mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any)).thenAnswer((
        inv,
      ) async {
        captured = (inv.positionalArguments[0] as Set<FlashcardStat>).first;
      });

      await service.reviewCard('sp1', 'deck1', grade);
      return captured!;
    }

    test('Again (grade) sets repetition to 0 and interval to 1', () async {
      final stat = await captureStatAfterReview(ReviewGrade.again);
      expect(stat.repetition, 0);
      expect(stat.interval, 1);
    });

    test('Easy (grade) increases ease factor', () async {
      final stat = await captureStatAfterReview(ReviewGrade.easy);
      expect(stat.easeFactor, greaterThan(2.5));
    });

    test('Easy produces higher ease factor than Again', () async {
      final easyResult = await captureStatAfterReview(ReviewGrade.easy);

      // Reset mock for Again
      when(
        mockFlashcardStatRepo.getFlashcardStat(any, any),
      ).thenAnswer((_) async => null);
      final againResult = await captureStatAfterReview(ReviewGrade.again);

      expect(easyResult.easeFactor, greaterThan(againResult.easeFactor));
    });

    test('every review grade persists the updated FlashcardStat', () async {
      for (final grade in ReviewGrade.values) {
        clearInteractions(mockFlashcardStatRepo);
        when(
          mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any),
        ).thenAnswer((_) async {});
        when(
          mockFlashcardStatRepo.getFlashcardStat(any, any),
        ).thenAnswer((_) async => null);

        await service.reviewCard('sp1', 'deck1', grade);

        verify(
          mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any),
        ).called(1);
      }
    });

    test('every review grade schedules a notification', () async {
      for (final grade in ReviewGrade.values) {
        clearInteractions(mockNotificationService);
        when(
          mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any),
        ).thenAnswer((_) async {});
        when(
          mockFlashcardStatRepo.getFlashcardStat(any, any),
        ).thenAnswer((_) async => null);
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

        await service.reviewCard('sp1', 'deck1', grade);

        verify(
          mockNotificationService.rescheduleAll(
            cardDueDates: anyNamed('cardDueDates'),
            preferredHour: anyNamed('preferredHour'),
            preferredMinute: anyNamed('preferredMinute'),
            daysAhead: anyNamed('daysAhead'),
            title: anyNamed('title'),
            bodyBuilder: anyNamed('bodyBuilder'),
          ),
        ).called(1);
      }
    });

    test('review loads existing stat from repository and updates it', () async {
      final existingStat = makeStat(
        repetition: 2,
        interval: 6,
        speciesId: 'sp1',
      );
      existingStat.easeFactor = 2.4;

      when(
        mockFlashcardStatRepo.getFlashcardStat('sp1', 'deck1'),
      ).thenAnswer((_) async => existingStat);

      FlashcardStat? captured;
      when(mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any)).thenAnswer((
        inv,
      ) {
        captured = (inv.positionalArguments[0] as Set<FlashcardStat>).first;
        return Future.value();
      });

      await service.reviewCard('sp1', 'deck1', ReviewGrade.easy);

      expect(captured!.repetition, 3);
      expect(captured!.interval, greaterThan(6));
      expect(captured!.easeFactor, greaterThan(2.4));
    });

    test(
      'reviewing a freshly activated card for the first time initializes stability and repetition',
      () async {
        final activatedStat = FlashcardStat(speciesId: 'sp1', deckId: 'deck1');
        activatedStat.nextReviewDate =
            DateTime.now(); // Activated but not reviewed
        expect(activatedStat.isNew, isTrue);

        when(
          mockFlashcardStatRepo.getFlashcardStat('sp1', 'deck1'),
        ).thenAnswer((_) async => activatedStat);

        FlashcardStat? captured;
        when(
          mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any),
        ).thenAnswer((inv) {
          captured = (inv.positionalArguments[0] as Set<FlashcardStat>).first;
          return Future.value();
        });

        // We'll use FSRS for this test implicitly if we swap it in setUp,
        // but let's just verify the service calls the algorithm correctly.
        await service.reviewCard('sp1', 'deck1', ReviewGrade.good);

        // SM-2 (current mock setup) uses repetition 0 check
        expect(captured!.repetition, 1);
        expect(captured!.lastReviewDate, isNotNull);
      },
    );
  });

  // ── getDeckStat ───────────────────────────────────────────────────────────

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
}
