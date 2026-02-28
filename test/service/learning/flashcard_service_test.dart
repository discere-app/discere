import 'package:discere/model/biology/classification.dart';
import 'package:discere/model/biology/species.dart';
import 'package:discere/model/biology/species_with_local_images.dart';
import 'package:discere/model/language.dart';
import 'package:discere/model/learning/deck_stat.dart';
import 'package:discere/model/learning/flash_card_stat.dart';
import 'package:discere/service/learning/flashcard_service.dart';
import 'package:discere/service/learning/spaced_repetition_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

Species makeSpecies({String id = 'sp1', List<String> images = const []}) {
  return Species(
    id,
    'carcharias',
    {Language.de: 'Weißer Hai', Language.en: 'Great white shark'},
    Classification(
      'Carcharodon', {Language.de: 'Weiße Haie'}, null,
      'Lamnidae', {Language.de: 'Makrelenhaie', Language.en: 'Mackerel sharks'},
      'Lamniformes', {Language.de: 'Makrelenhaiartige', Language.en: 'Mackerel sharks'},
      'Chondrichthyes', {Language.de: 'Knorpelfische'}, null,
    ),
    images,
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
    when(mockNotificationService.scheduleNotification(
      title: anyNamed('title'),
      body: anyNamed('body'),
      scheduledNotificationDateTime:
          anyNamed('scheduledNotificationDateTime'),
    )).thenAnswer((_) async {});
    when(mockImageService.downloadAndSaveImages(any))
        .thenAnswer((_) async => ['/local/img.jpg']);

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
          .thenAnswer((_) async => DeckStat(10, 5)); // not all uninitialized

      final result = await service.getFlashCardsForReview('deck1');

      expect(result, isEmpty);
    });

    test(
        'auto-initializes and returns cards when deck is completely uninitialized',
        () async {
      // First call: no cards due + all uninitialized → triggers initializeNextBatch
      // Second call (recursive): returns one due card
      final stat = makeStat(nextReviewDate: DateTime(2020)); // already due
      int callCount = 0;
      when(mockFlashCardStatRepo.getFlashCardStatsForReview(any, any))
          .thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? [] : [stat]; // second call returns stats
      });
      when(mockFlashCardStatRepo.getDeckStat(any))
          .thenAnswer((_) async => DeckStat(5, 5)); // all uninitialized
      when(mockFlashCardStatRepo.getUninitializedFlashCardStats(any, any))
          .thenAnswer((_) async =>
              {FlashCardStat(speciesId: 'sp1', deckId: 'deck1')});
      when(mockSpeciesRepo.getSpecies({'sp1'}))
          .thenAnswer((_) async => {makeSpecies()});

      final result = await service.getFlashCardsForReview('deck1');

      expect(result, isA<List<SpeciesWithLocalImages>>());
    });
  });

  // ── review actions ────────────────────────────────────────────────────────

  group('FlashCardService review actions', () {
    // Helper: call a review method and capture what was persisted
    Future<FlashCardStat> captureStatAfterReview(
        void Function(String, String) reviewFn) async {
      FlashCardStat? captured;
      when(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(any))
          .thenAnswer((inv) async {
        captured =
            (inv.positionalArguments[0] as Set<FlashCardStat>).first;
      });

      reviewFn('sp1', 'deck1');
      // Give async persistence a tick
      await Future<void>.delayed(Duration.zero);
      return captured!;
    }

    test('totalBlackout (quality=0) sets repetition to 0 and interval to 1',
        () async {
      final stat =
          await captureStatAfterReview(service.totalBlackout);
      expect(stat.repetition, 0);
      expect(stat.interval, 1);
    });

    test('rateVeryEasy (quality=5) increases ease factor', () async {
      final stat = await captureStatAfterReview(service.rateVeryEasy);
      expect(stat.easeFactor, greaterThan(2.5));
    });

    test('rateVeryEasy produces higher ease factor than totalBlackout',
        () async {
      FlashCardStat? easyResult;
      FlashCardStat? blackoutResult;

      when(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(any))
          .thenAnswer((inv) async {
        easyResult =
            (inv.positionalArguments[0] as Set<FlashCardStat>).first;
      });
      service.rateVeryEasy('sp1', 'deck1');
      await Future<void>.delayed(Duration.zero);

      when(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(any))
          .thenAnswer((inv) async {
        blackoutResult =
            (inv.positionalArguments[0] as Set<FlashCardStat>).first;
      });
      service.totalBlackout('sp1', 'deck1');
      await Future<void>.delayed(Duration.zero);

      expect(
        easyResult!.easeFactor,
        greaterThan(blackoutResult!.easeFactor),
      );
    });

    test('every review method persists the updated FlashCardStat', () async {
      final reviewMethods = [
        service.totalBlackout,
        service.incorrectButFamiliar,
        service.incorrectButNowIRemember,
        service.correctButDifficult,
        service.correctButNeededSomeTime,
        service.rateVeryEasy,
      ];

      for (final fn in reviewMethods) {
        clearInteractions(mockFlashCardStatRepo);
        fn('sp1', 'deck1');
        await Future<void>.delayed(Duration.zero);

        verify(mockFlashCardStatRepo.insertOrUpdateFlashCardStats(any))
            .called(1);
      }
    });

    test('every review method schedules a notification', () async {
      final reviewMethods = [
        service.totalBlackout,
        service.incorrectButFamiliar,
        service.incorrectButNowIRemember,
        service.correctButDifficult,
        service.correctButNeededSomeTime,
        service.rateVeryEasy,
      ];

      for (final fn in reviewMethods) {
        clearInteractions(mockNotificationService);
        fn('sp1', 'deck1');
        await Future<void>.delayed(Duration.zero);

        verify(mockNotificationService.scheduleNotification(
          title: anyNamed('title'),
          body: anyNamed('body'),
          scheduledNotificationDateTime:
              anyNamed('scheduledNotificationDateTime'),
        )).called(1);
      }
    });
  });

  // ── getDeckStat ───────────────────────────────────────────────────────────

  group('FlashCardService.getDeckStat', () {
    test('delegates to FlashCardStatRepository.getDeckStat', () async {
      when(mockFlashCardStatRepo.getDeckStat('deck1'))
          .thenAnswer((_) async => DeckStat(20, 5));

      final result = await service.getDeckStat('deck1');

      verify(mockFlashCardStatRepo.getDeckStat('deck1')).called(1);
      expect(result.totalCount, 20);
      expect(result.uninitializedCount, 5);
    });
  });
}
