import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/deck_stat.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/service/fsrs_service.dart';
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
  DateTime? nextReviewDate,
}) {
  return FlashcardStat(
    speciesId: speciesId,
    deckId: deckId,
    nextReviewDate: nextReviewDate ?? DateTime(2030),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockSpeciesMediaService mockSpeciesMediaService;
  late MockFlashcardStatRepository mockFlashcardStatRepo;
  late MockNotificationService mockNotificationService;
  late FsrsService fsrsService;
  late FlashcardService service;

  setUp(() {
    mockSpeciesMediaService = MockSpeciesMediaService();
    mockFlashcardStatRepo = MockFlashcardStatRepository();
    mockNotificationService = MockNotificationService();
    fsrsService = const FsrsService();

    // Safe defaults
    when(
      mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any),
    ).thenAnswer((_) async {});
    when(
      mockFlashcardStatRepo.getFlashcardStat(any, any),
    ).thenAnswer((_) async => null);
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
    when(
      mockSpeciesMediaService.resolveFromCache(any),
    ).thenAnswer((_) async => SpeciesWithLocalImages(makeSpecies(), []));
    when(
      mockSpeciesMediaService.resolveEnsuringSingleImage(any),
    ).thenAnswer((_) async => SpeciesWithLocalImages(makeSpecies(), []));

    service = FlashcardService(
      fsrsService,
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

    test(
      'builds review flashcards from cache without eager downloads',
      () async {
        when(
          mockFlashcardStatRepo.getFlashcardStatsForReview(any, any),
        ).thenAnswer(
          (_) async => [makeStat(speciesId: 'sp1'), makeStat(speciesId: 'sp2')],
        );

        await service.getFlashCardsForReview('deck1');

        verify(mockSpeciesMediaService.resolveFromCache('sp1')).called(1);
        verify(mockSpeciesMediaService.resolveFromCache('sp2')).called(1);
        verifyNever(mockSpeciesMediaService.resolveWithDownload(any));
      },
    );
  });

  group('FlashcardService.ensureSingleImageForSpecies', () {
    test('delegates to the single-image media resolver', () async {
      await service.ensureSingleImageForSpecies('sp1');

      verify(
        mockSpeciesMediaService.resolveEnsuringSingleImage('sp1'),
      ).called(1);
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

    test('Again on new card enters learning state', () async {
      final stat = await captureStatAfterReview(ReviewGrade.again);
      expect(stat.cardState, CardState.learning);
    });

    test('Easy on new card graduates to review', () async {
      final stat = await captureStatAfterReview(ReviewGrade.easy);
      expect(stat.cardState, CardState.review);
      expect(stat.stability, greaterThan(0));
    });

    test('Easy produces higher stability than Again after review', () async {
      final easyResult = await captureStatAfterReview(ReviewGrade.easy);

      // Reset mock for Again
      when(
        mockFlashcardStatRepo.getFlashcardStat(any, any),
      ).thenAnswer((_) async => null);
      final againResult = await captureStatAfterReview(ReviewGrade.again);

      expect(easyResult.stability, greaterThan(againResult.stability));
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

    test(
      'reviewCard does not itself reschedule notifications (session-level concern now)',
      () async {
        for (final grade in ReviewGrade.values) {
          clearInteractions(mockNotificationService);
          when(
            mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any),
          ).thenAnswer((_) async {});
          when(
            mockFlashcardStatRepo.getFlashcardStat(any, any),
          ).thenAnswer((_) async => null);

          await service.reviewCard('sp1', 'deck1', grade);

          verifyNever(
            mockNotificationService.rescheduleAll(
              cardDueDates: anyNamed('cardDueDates'),
              preferredHour: anyNamed('preferredHour'),
              preferredMinute: anyNamed('preferredMinute'),
              daysAhead: anyNamed('daysAhead'),
              title: anyNamed('title'),
              bodyBuilder: anyNamed('bodyBuilder'),
            ),
          );
          verifyNever(mockNotificationService.requestPermissions());
        }
      },
    );

    test(
      'rescheduleNotifications() reads all due dates and reschedules once',
      () async {
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
      },
    );

    test('review loads existing stat from repository and updates it', () async {
      final existingStat = makeStat(speciesId: 'sp1');
      existingStat.stability = 5.0;
      existingStat.cardState = CardState.review;
      existingStat.lastReviewDate = DateTime.now().subtract(
        const Duration(days: 5),
      );

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

      await service.reviewCard('sp1', 'deck1', ReviewGrade.good);

      expect(captured!.stability, greaterThan(5.0));
      expect(captured!.lastReviewDate, isNotNull);
    });

    test(
      'reviewing a freshly activated card for the first time initializes stability',
      () async {
        final activatedStat = FlashcardStat(speciesId: 'sp1', deckId: 'deck1');
        activatedStat.nextReviewDate = DateTime.now();
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

        await service.reviewCard('sp1', 'deck1', ReviewGrade.good);

        expect(captured!.lastReviewDate, isNotNull);
      },
    );
  });

  // ── learning-mode isolation ───────────────────────────────────────────────

  group('FlashcardService respects the deck\'s configured learning mode', () {
    late MockDeckConfigRepository mockDeckConfigRepo;
    late FlashcardService familyModeService;

    setUp(() {
      mockDeckConfigRepo = MockDeckConfigRepository();
      when(mockDeckConfigRepo.getOrDefault(any)).thenAnswer(
        (_) async => const DeckConfig(
          deckId: 'deck1',
          learningMode: LearningMode.family,
        ),
      );
      familyModeService = FlashcardService(
        fsrsService,
        mockFlashcardStatRepo,
        mockNotificationService,
        mockSpeciesMediaService,
        deckConfigRepository: mockDeckConfigRepo,
      );
    });

    test(
      'reviewCard loads and persists the family-mode stat, not the '
      'species-mode stat, when the deck is configured for family learning',
      () async {
        when(
          mockFlashcardStatRepo.getFlashcardStat(
            'sp1',
            'deck1',
            LearningMode.family,
          ),
        ).thenAnswer((_) async => null);

        FlashcardStat? captured;
        when(
          mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any),
        ).thenAnswer((inv) async {
          captured = (inv.positionalArguments[0] as Set<FlashcardStat>).first;
        });

        await familyModeService.reviewCard('sp1', 'deck1', ReviewGrade.good);

        expect(captured!.learningMode, LearningMode.family);
        verify(
          mockFlashcardStatRepo.getFlashcardStat(
            'sp1',
            'deck1',
            LearningMode.family,
          ),
        ).called(1);
        verifyNever(
          mockFlashcardStatRepo.getFlashcardStat(
            'sp1',
            'deck1',
            LearningMode.species,
          ),
        );
      },
    );

    test(
      'reviewCard updates the existing family-mode stat rather than '
      'creating a fresh one, when both modes already have progress',
      () async {
        final familyStat = FlashcardStat(
          speciesId: 'sp1',
          deckId: 'deck1',
          learningMode: LearningMode.family,
          stability: 8.0,
          cardState: CardState.review,
          lastReviewDate: DateTime.now().subtract(const Duration(days: 3)),
        );

        when(
          mockFlashcardStatRepo.getFlashcardStat(
            'sp1',
            'deck1',
            LearningMode.family,
          ),
        ).thenAnswer((_) async => familyStat);

        FlashcardStat? captured;
        when(
          mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any),
        ).thenAnswer((inv) async {
          captured = (inv.positionalArguments[0] as Set<FlashcardStat>).first;
        });

        await familyModeService.reviewCard('sp1', 'deck1', ReviewGrade.good);

        expect(captured!.learningMode, LearningMode.family);
        expect(captured!.stability, greaterThan(8.0));
      },
    );

    test(
      'getPreviewIntervals reads the family-mode stat for interval preview',
      () async {
        when(
          mockFlashcardStatRepo.getFlashcardStat(
            'sp1',
            'deck1',
            LearningMode.family,
          ),
        ).thenAnswer((_) async => null);

        await familyModeService.getPreviewIntervals('sp1', 'deck1');

        verify(
          mockFlashcardStatRepo.getFlashcardStat(
            'sp1',
            'deck1',
            LearningMode.family,
          ),
        ).called(1);
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
