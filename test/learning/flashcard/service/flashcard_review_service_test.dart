import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/learning/flashcard/service/flashcard_review_service.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

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

/// The configuration a session would have read once and handed to every call.
/// The service no longer looks it up, so the tests pass it the same way the
/// session does.
const config = DeckConfig(deckId: 'deck1');

void main() {
  late MockSpeciesMediaService mockSpeciesMediaService;
  late MockFlashcardStatRepository mockFlashcardStatRepo;
  late MockSpeciesPhotoGapAckRepository mockPhotoGapAckRepo;
  late FlashcardReviewService service;

  setUp(() {
    mockSpeciesMediaService = MockSpeciesMediaService();
    mockFlashcardStatRepo = MockFlashcardStatRepository();
    mockPhotoGapAckRepo = MockSpeciesPhotoGapAckRepository();

    // Safe defaults
    when(
      mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any),
    ).thenAnswer((_) async {});
    when(
      mockFlashcardStatRepo.getFlashcardStat(any, any),
    ).thenAnswer((_) async => null);
    when(mockSpeciesMediaService.resolveAllFromCache(any)).thenAnswer(
      (invocation) async => [
        for (final id in invocation.positionalArguments.first as Set<String>)
          SpeciesWithLocalImages(makeSpecies(id: id), []),
      ],
    );
    when(
      mockPhotoGapAckRepo.getAcknowledgedSpeciesIds(any),
    ).thenAnswer((_) async => {});
    when(
      mockSpeciesMediaService.resolveEnsuringSingleImage(any),
    ).thenAnswer((_) async => SpeciesWithLocalImages(makeSpecies(), []));
    when(
      mockSpeciesMediaService.findSpeciesWithoutLocalImage(any),
    ).thenAnswer(
      (invocation) async => invocation.positionalArguments.first as Set<String>,
    );

    service = FlashcardReviewService(
      mockFlashcardStatRepo,
      mockSpeciesMediaService,
      mockPhotoGapAckRepo,
    );
  });

  // ── initializeNextBatch ────────────────────────────────────────────────────

  group('FlashcardReviewService.initializeNextBatch', () {
    test('fetches uninitialized stats from the repository', () async {
      when(
        mockFlashcardStatRepo.getUninitializedFlashcardStats('deck1', 10),
      ).thenAnswer((_) async => {});

      await service.initializeNextBatch('deck1', config);

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
      Set<FlashcardStat>? persisted;
      when(mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any)).thenAnswer((
        inv,
      ) {
        persisted = inv.positionalArguments[0] as Set<FlashcardStat>;
        return Future.value();
      });

      final before = DateTime.now().subtract(const Duration(seconds: 1));
      await service.initializeNextBatch('deck1', config);
      final after = DateTime.now().add(const Duration(seconds: 1));

      expect(
        persisted!.map((stat) => stat.speciesId).toSet(),
        {'sp1', 'sp2'},
      );
      for (final stat in persisted!) {
        expect(stat.nextReviewDate, isNotNull);
        expect(stat.nextReviewDate!.isAfter(before), isTrue);
        expect(stat.nextReviewDate!.isBefore(after), isTrue);
      }
    });

    test('persists one stat per uninitialized card', () async {
      final stats = {FlashcardStat(speciesId: 'sp1', deckId: 'deck1')};
      when(
        mockFlashcardStatRepo.getUninitializedFlashcardStats(any, any),
      ).thenAnswer((_) async => stats);
      Set<FlashcardStat>? persisted;
      when(mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any)).thenAnswer((
        inv,
      ) {
        persisted = inv.positionalArguments[0] as Set<FlashcardStat>;
        return Future.value();
      });

      await service.initializeNextBatch('deck1', config);

      expect(persisted, hasLength(1));
      expect(persisted!.single.speciesId, 'sp1');
      expect(persisted!.single.deckId, 'deck1');
    });

    test('respects a custom batchSize parameter', () async {
      when(
        mockFlashcardStatRepo.getUninitializedFlashcardStats('deck1', 5),
      ).thenAnswer((_) async => {});

      await service.initializeNextBatch('deck1', config, batchSize: 5);

      verify(
        mockFlashcardStatRepo.getUninitializedFlashcardStats('deck1', 5),
      ).called(1);
    });
  });

  // ── getFlashCardsForReview ────────────────────────────────────────────────

  group('FlashcardReviewService.getFlashCardsForReview', () {
    test(
      'returns empty list when no cards are due and deck is partially learned',
      () async {
        when(
          mockFlashcardStatRepo.getFlashcardStatsForReview(any, any),
        ).thenAnswer((_) async => []);

        final result = await service.getFlashCardsForReview('deck1', config);

        expect(result, isEmpty);
      },
    );

    test('returns empty list when deck is completely uninitialized', () async {
      when(
        mockFlashcardStatRepo.getFlashcardStatsForReview(any, any),
      ).thenAnswer((_) async => []);

      final result = await service.getFlashCardsForReview('deck1', config);

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

        final cards = await service.getFlashCardsForReview('deck1', config);

        // Order is deliberately not asserted: a review session shuffles.
        expect(cards.map((card) => card.species.id).toSet(), {'sp1', 'sp2'});
        verify(
          mockSpeciesMediaService.resolveAllFromCache({'sp1', 'sp2'}),
        ).called(1);
        verifyNever(mockSpeciesMediaService.resolveFromCache(any));
      },
    );

    test(
      'resolves every due card in one pass, however many are due',
      () async {
        // The scaling guard for #229: one call for 1 due card and one for 25
        // is what keeps the time to the first card independent of how much is
        // due. species_media_service_test guards the query count behind that
        // single call.
        Future<void> loadDueCards(int count) async {
          when(
            mockFlashcardStatRepo.getFlashcardStatsForReview(any, any),
          ).thenAnswer(
            (_) async => [
              for (var i = 0; i < count; i++) makeStat(speciesId: 'sp$i'),
            ],
          );
          await service.getFlashCardsForReview('deck1', config);
        }

        await loadDueCards(1);
        await loadDueCards(25);

        verify(mockSpeciesMediaService.resolveAllFromCache(any)).called(2);
        verifyNever(mockSpeciesMediaService.resolveFromCache(any));
      },
    );
  });

  group('FlashcardReviewService.getUnacknowledgedPhotoGaps', () {
    /// Lets the cheap first phase report exactly [gaps] as missing an image.
    void givenGaps(Set<String> gaps) {
      when(
        mockSpeciesMediaService.findSpeciesWithoutLocalImage(any),
      ).thenAnswer(
        (invocation) async => (invocation.positionalArguments.first
                as Set<String>)
            .intersection(gaps),
      );
    }

    test('returns species with no local picture at all', () async {
      givenGaps({'sp1'});

      final gaps = await service.getUnacknowledgedPhotoGaps('deck1', {'sp1'});

      expect(gaps.map((card) => card.species.id), ['sp1']);
    });

    test('excludes species that already have a local picture', () async {
      givenGaps(const {});

      final gaps = await service.getUnacknowledgedPhotoGaps('deck1', {'sp1'});

      expect(gaps, isEmpty);
    });

    test('reports every species when none of them has an image', () async {
      givenGaps({'sp1', 'sp2', 'sp3'});

      final gaps = await service.getUnacknowledgedPhotoGaps('deck1', {
        'sp1',
        'sp2',
        'sp3',
      });

      expect(gaps.map((card) => card.species.id).toSet(), {
        'sp1',
        'sp2',
        'sp3',
      });
    });

    test('loads full cards only for the gaps, not for the whole deck', () async {
      givenGaps({'sp2'});

      final gaps = await service.getUnacknowledgedPhotoGaps('deck1', {
        'sp1',
        'sp2',
        'sp3',
      });

      expect(gaps.map((card) => card.species.id), ['sp2']);
      // The heavy path (joins, common names, traits, native regions) is the
      // dialog's display name, needed for the gaps alone. Entering it for the
      // whole deck would pay that for every species to then discard all but
      // these.
      verify(
        mockSpeciesMediaService.resolveAllFromCache({'sp2'}),
      ).called(1);
    });

    test('never enters the heavy path when the deck has no gap', () async {
      givenGaps(const {});

      expect(
        await service.getUnacknowledgedPhotoGaps('deck1', {'sp1', 'sp2'}),
        isEmpty,
      );

      verifyNever(mockSpeciesMediaService.resolveAllFromCache(any));
    });

    test('never resolves a species already acknowledged for this deck', () async {
      when(
        mockPhotoGapAckRepo.getAcknowledgedSpeciesIds('deck1'),
      ).thenAnswer((_) async => {'sp1'});

      final gaps = await service.getUnacknowledgedPhotoGaps('deck1', {'sp1'});

      expect(gaps, isEmpty);
      // Subtracted before anything is examined: an acknowledged species is
      // work the dialog can no longer use.
      verifyNever(mockSpeciesMediaService.findSpeciesWithoutLocalImage(any));
      verifyNever(mockSpeciesMediaService.resolveAllFromCache(any));
    });

    test('examines nothing when asked about no species', () async {
      expect(
        await service.getUnacknowledgedPhotoGaps('deck1', const {}),
        isEmpty,
      );

      verifyNever(mockSpeciesMediaService.findSpeciesWithoutLocalImage(any));
      verifyNever(mockSpeciesMediaService.resolveAllFromCache(any));
    });

    test('examines the deck in one pass, however large it is', () async {
      Future<void> checkDeck(int speciesCount) async {
        givenGaps({'sp0'});
        await service.getUnacknowledgedPhotoGaps('deck1', {
          for (var i = 0; i < speciesCount; i++) 'sp$i',
        });
      }

      await checkDeck(1);
      await checkDeck(200);

      // One cheap scan per check regardless of deck size, and the heavy load
      // only ever for the one gap — not 1 vs. 200 species through the joins.
      verify(
        mockSpeciesMediaService.findSpeciesWithoutLocalImage(any),
      ).called(2);
      verify(mockSpeciesMediaService.resolveAllFromCache({'sp0'})).called(2);
    });
  });

  group('FlashcardReviewService.acknowledgePhotoGaps', () {
    test('delegates to the repository', () async {
      await service.acknowledgePhotoGaps('deck1', {'sp1', 'sp2'});

      verify(
        mockPhotoGapAckRepo.acknowledge('deck1', {'sp1', 'sp2'}),
      ).called(1);
    });
  });

  group('FlashcardReviewService.ensureSingleImageForSpecies', () {
    test('delegates to the single-image media resolver', () async {
      await service.ensureSingleImageForSpecies('sp1');

      verify(
        mockSpeciesMediaService.resolveEnsuringSingleImage('sp1'),
      ).called(1);
    });
  });

  // ── review actions ────────────────────────────────────────────────────────

  group('FlashcardReviewService review actions', () {
    // Helper: call reviewCard with a grade and capture what was persisted
    Future<FlashcardStat> captureStatAfterReview(ReviewGrade grade) async {
      FlashcardStat? captured;
      when(mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any)).thenAnswer((
        inv,
      ) async {
        captured = (inv.positionalArguments[0] as Set<FlashcardStat>).first;
      });

      await service.reviewCard('sp1', 'deck1', config, grade);
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

        await service.reviewCard('sp1', 'deck1', config, grade);

        verify(
          mockFlashcardStatRepo.insertOrUpdateFlashcardStats(any),
        ).called(1);
      }
    });

    test('review loads existing stat from repository and updates it', () async {
      final existingStat = makeStat(speciesId: 'sp1').copyWith(
        stability: 5.0,
        cardState: CardState.review,
        lastReviewDate: DateTime.now().subtract(const Duration(days: 5)),
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

      await service.reviewCard('sp1', 'deck1', config, ReviewGrade.good);

      expect(captured!.stability, greaterThan(5.0));
      expect(captured!.lastReviewDate, isNotNull);
    });

    test(
      'reviewing a freshly activated card for the first time initializes stability',
      () async {
        final activatedStat = FlashcardStat(
          speciesId: 'sp1',
          deckId: 'deck1',
          nextReviewDate: DateTime.now(),
        );
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

        await service.reviewCard('sp1', 'deck1', config, ReviewGrade.good);

        expect(captured!.lastReviewDate, isNotNull);
      },
    );
  });

  // ── learning-mode isolation ───────────────────────────────────────────────

  group(
    'FlashcardReviewService respects the deck\'s configured learning mode',
    () {
      // No second service and no mocked config repository: the mode is a value
      // the caller passes, so a family-mode deck is just a different config.
      const familyConfig = DeckConfig(
        deckId: 'deck1',
        learningMode: LearningMode.family,
      );

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

          await service.reviewCard('sp1', 'deck1', familyConfig, ReviewGrade.good);

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

          await service.reviewCard('sp1', 'deck1', familyConfig, ReviewGrade.good);

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

          await service.getPreviewIntervals('sp1', 'deck1', familyConfig);

          verify(
            mockFlashcardStatRepo.getFlashcardStat(
              'sp1',
              'deck1',
              LearningMode.family,
            ),
          ).called(1);
        },
      );
    },
  );
}
