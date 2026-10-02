import 'dart:async';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/learning/flashcard/review_session_controller.dart';
import 'package:discere/learning/flashcard/service/deck_session_service.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/flashcard/service/multiple_choice_distractor_pool_service.dart';
import 'package:discere/learning/flashcard/service/taxonomy_distractor_pools.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers ReviewSessionController — the state of one review session, which
/// card is showing and what follows from that. Driven directly here: the
/// point of the class is that none of this needs a pumped widget tree to be
/// checked.

class _TestFlashcardService extends Fake implements FlashcardService {
  _TestFlashcardService(this.config);

  final DeckConfig config;

  @override
  Future<DeckConfig> getDeckConfig(String deckId) async => config;
}

class _TestSessionService extends Fake implements DeckSessionService {
  _TestSessionService({required this.data, this.error});

  final DeckSessionData data;
  final Object? error;
  final List<String> removedSpeciesIds = [];
  final List<String> previewRequests = [];

  @override
  Future<DeckSessionData> loadSessionData({
    required BaseDeck deck,
    required DeckConfig config,
  }) async {
    if (error != null) throw error!;
    return data;
  }

  @override
  Future<void> removeSpeciesFromDeck(String deckId, String speciesId) async {
    removedSpeciesIds.add(speciesId);
  }

  @override
  Future<Map<ReviewGrade, String>> getPreviewIntervals(
    String speciesId,
    String deckId,
  ) async {
    previewRequests.add(speciesId);
    return {ReviewGrade.good: '1d'};
  }
}

Species _species(String id, String commonName, {String genusId = 'genus-1'}) =>
    Species(
  id,
  id,
  'fishbase',
  'Scientific $id',
  {
    Language.en: [commonName],
  },
  Classification(
    'Genus',
    const {},
    null,
    'Family',
    const {},
    'Order',
    const {},
    'Class',
    const {},
    null,
    genusId: genusId,
  ),
  const [],
);

SpeciesWithLocalImages _card(
  String id, {
  bool withImage = true,
  String genusId = 'genus-1',
}) {
  final species = _species(id, 'Name $id', genusId: genusId);
  return SpeciesWithLocalImages(species, [
    if (withImage)
      LocalPicture(
        Picture(id: 'pic-$id', species: id, origin: 'fishbase', isUsable: 1),
        '/tmp/$id.jpg',
      ),
  ]);
}

/// Stands in for the reference-DB-backed pool builder: the controller only
/// cares how many distinct names a card's pool yields, not where they came
/// from.
class _FixedPoolService extends Fake
    implements MultipleChoiceDistractorPoolService {
  _FixedPoolService(this.pool);

  final List<String> pool;

  /// Holds every pool build open while set, so a test can act while a card's
  /// pool is still loading.
  Completer<void>? gate;

  @override
  Future<List<String>> buildPool({
    required Species currentSpecies,
    required List<Species> deckSpecies,
    required LearningMode learningMode,
    required Language language,
    required NameType nameType,
    int minimumDistinctNames = 3,
  }) async {
    await gate?.future;
    return pool;
  }
}

DeckSessionData _sessionData({
  List<SpeciesWithLocalImages> reviewableCards = const [],
  List<SpeciesWithLocalImages> awaitingImageCards = const [],
  bool isWaitingForImages = false,
  List<String>? distractorNames,
  _FixedPoolService? poolService,
}) => DeckSessionData(
  reviewableCards: reviewableCards,
  isWaitingForImages: isWaitingForImages,
  awaitingImageCards: awaitingImageCards,
  pendingCommonNameSpeciesIds: const {},
  distractorPools: distractorNames == null && poolService == null
      ? null
      : TaxonomyDistractorPools(
          poolService:
              poolService ?? _FixedPoolService(distractorNames ?? const []),
          deckSpecies: [
            for (final card in [...reviewableCards, ...awaitingImageCards])
              card.species,
          ],
          learningMode: LearningMode.species,
          nameType: NameType.commonName,
          language: Language.en,
        ),
);

ReviewSessionController _controller({
  required DeckSessionData data,
  DeckConfig? config,
  Object? loadError,
  _TestSessionService? sessionService,
}) => ReviewSessionController(
  deck: BaseDeck(
  id: 'deck-1',
  name: 'Deck',
  description: '', language: Language.en),
  flashcardService: _TestFlashcardService(
    config ??
        const DeckConfig(deckId: 'deck-1'),
  ),
  sessionService:
      sessionService ?? _TestSessionService(data: data, error: loadError),
);

void main() {
  test('reports the loaded cards and settles on ready', () async {
    final controller = _controller(
      data: _sessionData(reviewableCards: [_card('a'), _card('b')]),
    );
    expect(controller.status, ReviewSessionStatus.loading);

    await controller.load();

    expect(controller.status, ReviewSessionStatus.ready);
    expect(controller.cards, hasLength(2));
    expect(controller.currentCard.species.id, 'a');
  });

  test('keeps a failed load out of the card state', () async {
    final controller = _controller(
      data: _sessionData(),
      loadError: StateError('deck gone'),
    );

    await controller.load();

    expect(controller.status, ReviewSessionStatus.failed);
    expect(controller.error, isA<StateError>());
    expect(controller.hasCards, isFalse);
  });

  test('advances through the cards and stops on the last one', () async {
    final controller = _controller(
      data: _sessionData(reviewableCards: [_card('a'), _card('b')]),
    );
    await controller.load();

    await controller.advance();
    expect(controller.currentCard.species.id, 'b');
    expect(controller.isOnLastCard, isTrue);

    // Running out of cards is the page's decision — the controller holds.
    await controller.advance();
    expect(controller.currentCard.species.id, 'b');
  });

  test('a requeued card extends the session past its former last card', () async {
    final controller = _controller(
      data: _sessionData(reviewableCards: [_card('a'), _card('b')]),
    );
    await controller.load();
    await controller.advance();
    expect(controller.isOnLastCard, isTrue);

    controller.requeueCurrentCard();

    expect(controller.isOnLastCard, isFalse);
    await controller.advance();
    expect(controller.currentCard.species.id, 'b');
  });

  test('removing the last card leaves the index on a card that exists', () async {
    final service = _TestSessionService(
      data: _sessionData(reviewableCards: [_card('a'), _card('b')]),
    );
    final controller = _controller(data: _sessionData(), sessionService: service);
    await controller.load();
    await controller.advance();

    await controller.removeSpecies('b');

    expect(service.removedSpeciesIds, ['b']);
    expect(controller.cards, hasLength(1));
    expect(controller.currentCard.species.id, 'a');
  });

  test('swaps in a card that just gained an image', () async {
    final controller = _controller(
      data: _sessionData(
        reviewableCards: [_card('a', withImage: false), _card('b')],
      ),
    );
    await controller.load();
    expect(controller.currentCard.localPictures, isEmpty);

    controller.replaceCard(_card('a'));

    expect(controller.currentCard.localPictures, isNotEmpty);
    expect(controller.cards, hasLength(2));
  });

  test('shows the held-back cards once image fetching gives up', () async {
    final controller = _controller(
      data: _sessionData(
        awaitingImageCards: [_card('a', withImage: false)],
        isWaitingForImages: true,
      ),
    );
    await controller.load();
    expect(controller.hasCards, isFalse);
    expect(controller.isWaitingForImages, isTrue);

    await controller.showAwaitingCardsWithoutImages();

    expect(controller.cards, hasLength(1));
    expect(controller.isWaitingForImages, isFalse);
  });

  test(
    'falls back to flip for a card whose pool has too few distractors',
    () async {
      final controller = _controller(
        config: const DeckConfig(
          deckId: 'deck-1',
          reviewMode: ReviewMode.multipleChoice,
        ),
        data: _sessionData(
          reviewableCards: [_card('a')],
          distractorNames: const ['Name a', 'Name b'],
        ),
      );

      await controller.load();

      expect(controller.options, isEmpty);
      expect(controller.effectiveReviewMode, ReviewMode.flip);
    },
  );

  test('builds the options of the card on screen from its scope pool', () async {
    final controller = _controller(
      config: const DeckConfig(
        deckId: 'deck-1',
        reviewMode: ReviewMode.multipleChoice,
      ),
      data: _sessionData(
        reviewableCards: [_card('a')],
        distractorNames: const ['Name b', 'Name c', 'Name d'],
      ),
    );

    await controller.load();

    expect(controller.effectiveReviewMode, ReviewMode.multipleChoice);
    expect(controller.options, hasLength(4));
    expect(
      controller.options
          .where((option) => option.isCorrect)
          .map((option) => option.label),
      ['Name a'],
    );
  });

  test(
    'two advances during a pool load land on the same card with its options',
    () async {
      final poolService = _FixedPoolService(const [
        'Name x',
        'Name y',
        'Name z',
      ]);
      final controller = _controller(
        config: const DeckConfig(
          deckId: 'deck-1',
          reviewMode: ReviewMode.multipleChoice,
        ),
        data: _sessionData(
          // Each card in its own scope, so advancing really does wait for a
          // pool that isn't built yet.
          reviewableCards: [
            _card('a'),
            _card('b', genusId: 'genus-2'),
            _card('c', genusId: 'genus-3'),
          ],
          poolService: poolService,
        ),
      );
      await controller.load();

      // The continue button stays tappable while the next card's pool loads,
      // so a second tap inside that window must not skip a card or leave the
      // previous card's options on screen (its correct answer would be
      // missing, and tapping one would grade the wrong card).
      poolService.gate = Completer<void>();
      final firstTap = controller.advance();
      final secondTap = controller.advance();
      poolService.gate!.complete();
      await Future.wait([firstTap, secondTap]);

      expect(controller.currentIndex, 1);
      expect(controller.currentCard.species.id, 'b');
      expect(
        controller.options
            .where((option) => option.isCorrect)
            .map((option) => option.label),
        ['Name b'],
      );
    },
  );

  test('notifies its listeners when the current card changes', () async {
    final controller = _controller(
      data: _sessionData(reviewableCards: [_card('a'), _card('b')]),
    );
    await controller.load();

    var notifications = 0;
    controller.addListener(() => notifications++);
    await controller.advance();

    expect(notifications, 1);
  });

  test('drops work that lands after disposal', () async {
    final controller = _controller(
      data: _sessionData(reviewableCards: [_card('a')]),
    );
    await controller.load();
    controller.addListener(() => fail('must not notify after dispose'));

    controller.dispose();

    expect(controller.isDisposed, isTrue);
    await controller.loadPreviews();
    expect(controller.previews, isEmpty);
  });
}
