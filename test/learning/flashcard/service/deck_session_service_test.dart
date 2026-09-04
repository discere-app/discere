import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/queue/model/enrichment_job.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/flashcard/service/deck_session_service.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/flashcard/service/multiple_choice_distractor_pool_service.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

class FakeEnrichmentQueueService extends Fake
    implements INatEnrichmentQueueService {
  FakeEnrichmentQueueService({
    this.imageStagesComplete = true,
    this.pendingCommonNames = const {},
  });

  final bool imageStagesComplete;
  final Set<String> pendingCommonNames;

  @override
  DeckEnrichmentInfo deckInfo(String deckId) => DeckEnrichmentInfo(
    status: imageStagesComplete
        ? EnrichmentJobStatus.completed
        : EnrichmentJobStatus.runningForeground,
    lastCompletedAt: null,
    lastAttemptedAt: null,
    imageStagesComplete: imageStagesComplete,
  );

  @override
  Future<Set<String>> pendingCommonNameSpeciesIds(
    Set<String> speciesIds,
  ) async => pendingCommonNames.intersection(speciesIds);
}

Species _species(String id, {String genus = 'Carcharodon'}) {
  return Species(
    id,
    id,
    'fishbase',
    'epithet-$id',
    const {},
    Classification(
      genus,
      const {},
      null,
      'Lamnidae',
      const {},
      'Lamniformes',
      const {},
      'Chondrichthyes',
      const {},
      null,
      genusId: 'genus-$genus',
      familyId: 'family-1',
      orderId: 'order-1',
      classId: 'class-1',
    ),
    const [],
  );
}

SpeciesWithLocalImages _card(String id, {bool hasImage = true}) {
  return SpeciesWithLocalImages(_species(id), [
    if (hasImage)
      LocalPicture(
        Picture(id: 'pic-$id', species: id, origin: 'inaturalist', isUsable: 1),
        '/tmp/$id.jpg',
      ),
  ]);
}

BaseDeck _deck() => BaseDeck('deck-1', 'Test Deck', 'Description');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFlashcardReviewService flashcardReviewService;
  late MockDecksService decksService;

  setUp(() {
    flashcardReviewService = MockFlashcardReviewService();
    decksService = MockDecksService();
  });

  DeckSessionService buildService({
    required INatEnrichmentQueueService enrichmentQueueService,
    MultipleChoiceDistractorPoolService? distractorPoolService,
  }) {
    return DeckSessionService(
      flashcardReviewService: flashcardReviewService,
      decksService: decksService,
      enrichmentQueueService: enrichmentQueueService,
      distractorPoolService:
          distractorPoolService ??
          MultipleChoiceDistractorPoolService(
            taxonomyRepository: MockTaxonomyRepository(),
          ),
    );
  }

  group('scopeIdFor', () {
    test('species mode uses the genus id', () {
      final service = buildService(
        enrichmentQueueService: FakeEnrichmentQueueService(),
      );
      expect(
        service.scopeIdFor(LearningMode.species, _species('sp1')),
        'genus-Carcharodon',
      );
    });

    test('genus mode uses the family id', () {
      final service = buildService(
        enrichmentQueueService: FakeEnrichmentQueueService(),
      );
      expect(service.scopeIdFor(LearningMode.genus, _species('sp1')), 'family-1');
    });

    test('family mode uses the order id', () {
      final service = buildService(
        enrichmentQueueService: FakeEnrichmentQueueService(),
      );
      expect(service.scopeIdFor(LearningMode.family, _species('sp1')), 'order-1');
    });
  });

  group('loadSessionData', () {
    test('skips distractor pool computation in flip mode', () async {
      when(
        flashcardReviewService.getFlashCardsForReview('deck-1'),
      ).thenAnswer((_) async => [_card('sp1')]);

      final service = buildService(
        enrichmentQueueService: FakeEnrichmentQueueService(),
      );
      final data = await service.loadSessionData(
        deck: _deck(),
        config: const DeckConfig(deckId: 'deck-1'),
      );

      expect(data.deckNamePool, isEmpty);
      expect(data.taxonomyPoolByScopeId, isEmpty);
      expect(data.reviewableCards, hasLength(1));
      verifyNever(decksService.getSpeciesByDeckId(any));
    });

    test('computes name pools in multiple-choice mode', () async {
      final deckSpecies = [_species('sp1'), _species('sp2', genus: 'Isurus')];
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => deckSpecies);
      when(
        flashcardReviewService.getFlashCardsForReview('deck-1'),
      ).thenAnswer((_) async => [_card('sp1')]);

      final service = buildService(
        enrichmentQueueService: FakeEnrichmentQueueService(),
      );
      final data = await service.loadSessionData(
        deck: _deck(),
        config: const DeckConfig(
          deckId: 'deck-1',
          reviewMode: ReviewMode.multipleChoice,
        ),
      );

      expect(data.deckNamePool, isNotEmpty);
      expect(data.taxonomyPoolByScopeId.keys, contains('genus-Carcharodon'));
    });

    test(
      'hides cards without a local image while image stages are incomplete',
      () async {
        when(flashcardReviewService.getFlashCardsForReview('deck-1')).thenAnswer(
          (_) async => [_card('sp1', hasImage: false), _card('sp2')],
        );

        final service = buildService(
          enrichmentQueueService: FakeEnrichmentQueueService(
            imageStagesComplete: false,
          ),
        );
        final data = await service.loadSessionData(
          deck: _deck(),
          config: const DeckConfig(deckId: 'deck-1'),
        );

        expect(data.reviewableCards.map((c) => c.species.id), ['sp2']);
        expect(data.isWaitingForImages, isFalse);
      },
    );

    test(
      'reports isWaitingForImages when every due card lacks a local image',
      () async {
        when(flashcardReviewService.getFlashCardsForReview('deck-1')).thenAnswer(
          (_) async => [_card('sp1', hasImage: false)],
        );

        final service = buildService(
          enrichmentQueueService: FakeEnrichmentQueueService(
            imageStagesComplete: false,
          ),
        );
        final data = await service.loadSessionData(
          deck: _deck(),
          config: const DeckConfig(deckId: 'deck-1'),
        );

        expect(data.reviewableCards, isEmpty);
        expect(data.isWaitingForImages, isTrue);
        expect(data.awaitingImageCards, hasLength(1));
      },
    );

    test(
      'only queries pending common names for species + commonName mode',
      () async {
        when(
          flashcardReviewService.getFlashCardsForReview('deck-1'),
        ).thenAnswer((_) async => [_card('sp1')]);

        final service = buildService(
          enrichmentQueueService: FakeEnrichmentQueueService(
            pendingCommonNames: {'sp1'},
          ),
        );

        final speciesModeData = await service.loadSessionData(
          deck: _deck(),
          config: const DeckConfig(
            deckId: 'deck-1',
            learningMode: LearningMode.species,
            nameType: NameType.commonName,
          ),
        );
        expect(speciesModeData.pendingCommonNameSpeciesIds, {'sp1'});

        final genusModeData = await service.loadSessionData(
          deck: _deck(),
          config: const DeckConfig(
            deckId: 'deck-1',
            learningMode: LearningMode.genus,
            nameType: NameType.commonName,
          ),
        );
        expect(genusModeData.pendingCommonNameSpeciesIds, isEmpty);
      },
    );
  });

  group('gradeCard', () {
    test('requeues cards still in learning/relearning', () async {
      when(
        flashcardReviewService.reviewCard('sp1', 'deck-1', ReviewGrade.again),
      ).thenAnswer(
        (_) async => FlashcardStat(
          speciesId: 'sp1',
          deckId: 'deck-1',
          cardState: CardState.learning,
        ),
      );

      final service = buildService(
        enrichmentQueueService: FakeEnrichmentQueueService(),
      );
      final result = await service.gradeCard(
        speciesId: 'sp1',
        deckId: 'deck-1',
        grade: ReviewGrade.again,
      );

      expect(result.cardState, CardState.learning);
      expect(result.shouldRequeue, isTrue);
    });

    test('does not requeue a card back in normal review', () async {
      when(
        flashcardReviewService.reviewCard('sp1', 'deck-1', ReviewGrade.good),
      ).thenAnswer(
        (_) async => FlashcardStat(
          speciesId: 'sp1',
          deckId: 'deck-1',
          cardState: CardState.review,
        ),
      );

      final service = buildService(
        enrichmentQueueService: FakeEnrichmentQueueService(),
      );
      final result = await service.gradeCard(
        speciesId: 'sp1',
        deckId: 'deck-1',
        grade: ReviewGrade.good,
      );

      expect(result.shouldRequeue, isFalse);
    });
  });

  group('photo gaps', () {
    test('getUnacknowledgedPhotoGaps resolves deck species then queries gaps', () async {
      when(
        decksService.getSpeciesByDeckId('deck-1'),
      ).thenAnswer((_) async => [_species('sp1'), _species('sp2')]);
      when(
        flashcardReviewService.getUnacknowledgedPhotoGaps('deck-1', {'sp1', 'sp2'}),
      ).thenAnswer((_) async => [_card('sp1', hasImage: false)]);

      final service = buildService(
        enrichmentQueueService: FakeEnrichmentQueueService(),
      );
      final gaps = await service.getUnacknowledgedPhotoGaps('deck-1');

      expect(gaps.map((c) => c.species.id), ['sp1']);
    });

    test('removeSpeciesAndAcknowledgeGaps removes then acknowledges', () async {
      when(
        decksService.removeSpeciesFromDeck('deck-1', 'sp1'),
      ).thenAnswer((_) async {});
      when(
        flashcardReviewService.acknowledgePhotoGaps('deck-1', {'sp2'}),
      ).thenAnswer((_) async {});

      final service = buildService(
        enrichmentQueueService: FakeEnrichmentQueueService(),
      );
      await service.removeSpeciesAndAcknowledgeGaps(
        deckId: 'deck-1',
        toRemove: {'sp1'},
        toAcknowledge: {'sp2'},
      );

      verify(decksService.removeSpeciesFromDeck('deck-1', 'sp1')).called(1);
      verify(flashcardReviewService.acknowledgePhotoGaps('deck-1', {'sp2'})).called(1);
    });

    test(
      'removeSpeciesAndAcknowledgeGaps skips acknowledging when nothing to keep',
      () async {
        when(
          decksService.removeSpeciesFromDeck('deck-1', 'sp1'),
        ).thenAnswer((_) async {});

        final service = buildService(
          enrichmentQueueService: FakeEnrichmentQueueService(),
        );
        await service.removeSpeciesAndAcknowledgeGaps(
          deckId: 'deck-1',
          toRemove: {'sp1'},
          toAcknowledge: {},
        );

        verifyNever(flashcardReviewService.acknowledgePhotoGaps(any, any));
      },
    );
  });
}
