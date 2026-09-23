import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/learning/flashcard/review_session_controller.dart';
import 'package:discere/learning/flashcard/service/deck_session_service.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/learning_mode.dart';
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
  String? scopeIdFor(LearningMode learningMode, Species species) =>
      species.classification.genusId;

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

Species _species(String id, String commonName) => Species(
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
    'genus-1',
    'Family',
    const {},
    'Order',
    const {},
    'Class',
    const {},
    null,
  ),
  const [],
);

SpeciesWithLocalImages _card(String id, {bool withImage = true}) {
  final species = _species(id, 'Name $id');
  return SpeciesWithLocalImages(species, [
    if (withImage)
      LocalPicture(
        Picture(id: 'pic-$id', species: id, origin: 'fishbase', isUsable: 1),
        '/tmp/$id.jpg',
      ),
  ]);
}

DeckSessionData _sessionData({
  List<SpeciesWithLocalImages> reviewableCards = const [],
  List<SpeciesWithLocalImages> awaitingImageCards = const [],
  bool isWaitingForImages = false,
  List<String> deckNamePool = const [],
}) => DeckSessionData(
  reviewableCards: reviewableCards,
  isWaitingForImages: isWaitingForImages,
  awaitingImageCards: awaitingImageCards,
  deckNamePool: deckNamePool,
  taxonomyPoolByScopeId: const {},
  pendingCommonNameSpeciesIds: const {},
);

ReviewSessionController _controller({
  required DeckSessionData data,
  DeckConfig? config,
  Object? loadError,
  _TestSessionService? sessionService,
}) => ReviewSessionController(
  deck: BaseDeck('deck-1', 'Deck', '', language: Language.en),
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

    controller.advance();
    expect(controller.currentCard.species.id, 'b');
    expect(controller.isOnLastCard, isTrue);

    // Running out of cards is the page's decision — the controller holds.
    controller.advance();
    expect(controller.currentCard.species.id, 'b');
  });

  test('a requeued card extends the session past its former last card', () async {
    final controller = _controller(
      data: _sessionData(reviewableCards: [_card('a'), _card('b')]),
    );
    await controller.load();
    controller.advance();
    expect(controller.isOnLastCard, isTrue);

    controller.requeueCurrentCard();

    expect(controller.isOnLastCard, isFalse);
    controller.advance();
    expect(controller.currentCard.species.id, 'b');
  });

  test('removing the last card leaves the index on a card that exists', () async {
    final service = _TestSessionService(
      data: _sessionData(reviewableCards: [_card('a'), _card('b')]),
    );
    final controller = _controller(data: _sessionData(), sessionService: service);
    await controller.load();
    controller.advance();

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

    controller.showAwaitingCardsWithoutImages();

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
          deckNamePool: const ['Name a', 'Name b'],
        ),
      );

      await controller.load();

      expect(controller.options, isEmpty);
      expect(controller.effectiveReviewMode, ReviewMode.flip);
    },
  );

  test('notifies its listeners when the current card changes', () async {
    final controller = _controller(
      data: _sessionData(reviewableCards: [_card('a'), _card('b')]),
    );
    await controller.load();

    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.advance();

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
