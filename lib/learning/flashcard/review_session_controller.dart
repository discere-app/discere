import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/learning/flashcard/answer_options_presenter.dart';
import 'package:discere/learning/flashcard/deck_session_presenter.dart';
import 'package:discere/learning/flashcard/flashcard_species_presenter.dart';
import 'package:discere/learning/flashcard/multiple_choice_option.dart';
import 'package:discere/learning/flashcard/service/deck_session_service.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/flashcard/service/taxonomy_distractor_pools.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:flutter/foundation.dart';

/// Where a review session is in its load cycle. [DeckPage] renders one of
/// three bodies from it, rather than reading an `AsyncSnapshot`.
enum ReviewSessionStatus { loading, ready, failed }

/// The state of one review session: which cards it holds, which one is
/// showing, the answer options and interval previews that belong to it, and
/// the deck configuration all three are derived from.
///
/// It exists so the page never has to mirror session state out of a
/// `FutureBuilder` snapshot during `build()` — the cards live here, `build()`
/// only reads them, and a change arrives as a notification instead of as a
/// rebuilt future.
///
/// Anything needing a `BuildContext` stays with `DeckPageState`: dialogs,
/// localized notification copy, the tutorial. This class only performs
/// session work that a test can drive without pumping a widget.
class ReviewSessionController extends ChangeNotifier {
  final BaseDeck _deck;
  final FlashcardService _flashcardService;
  final DeckSessionService _sessionService;
  final DeckSessionPresenter _sessionPresenter;
  final AnswerOptionsPresenter _answerOptionsPresenter;
  final FlashcardSpeciesPresenter _speciesPresenter;

  ReviewSessionController({
    required BaseDeck deck,
    required FlashcardService flashcardService,
    required DeckSessionService sessionService,
    DeckSessionPresenter sessionPresenter = const DeckSessionPresenter(),
    AnswerOptionsPresenter answerOptionsPresenter =
        const AnswerOptionsPresenter(),
    FlashcardSpeciesPresenter speciesPresenter =
        const FlashcardSpeciesPresenter(),
  }) : _deck = deck,
       _config = DeckConfig(deckId: deck.id!),
       _flashcardService = flashcardService,
       _sessionService = sessionService,
       _sessionPresenter = sessionPresenter,
       _answerOptionsPresenter = answerOptionsPresenter,
       _speciesPresenter = speciesPresenter;

  ReviewSessionStatus _status = ReviewSessionStatus.loading;
  Object? _error;
  List<SpeciesWithLocalImages> _cards = [];
  int _currentIndex = 0;
  List<MultipleChoiceOption> _options = [];
  Map<ReviewGrade, String> _previews = {};
  /// The configuration this session runs on, read once in [load] and handed
  /// to every call that needs it, so no two parts of the session can be
  /// working from different reads of it. Defaults until the first load, for
  /// the same reason the cards start out empty.
  DeckConfig _config;
  TaxonomyDistractorPools? _distractorPools;
  List<SpeciesWithLocalImages> _awaitingImageCards = [];
  bool _isWaitingForImages = false;
  Set<String> _pendingCommonNameSpeciesIds = {};
  bool _isDisposed = false;

  ReviewSessionStatus get status => _status;

  /// What the session was configured with — what a caller hands back to
  /// [DeckSessionService] for an operation on this same session.
  DeckConfig get config => _config;
  Object? get error => _error;
  List<SpeciesWithLocalImages> get cards => _cards;
  int get currentIndex => _currentIndex;
  List<MultipleChoiceOption> get options => _options;
  Map<ReviewGrade, String> get previews => _previews;
  LearningMode get learningMode => _config.learningMode;
  NameType get nameType => _config.nameType;
  bool get hasCards => _cards.isNotEmpty;
  SpeciesWithLocalImages get currentCard => _cards[_currentIndex];
  bool get isOnLastCard => _currentIndex >= _cards.length - 1;

  /// Cards due for review whose species has no local image yet, held back by
  /// [DeckSessionPresenter.filterReviewableCards] while the deck's
  /// image-loading enrichment stages are still in flight. Never shown as-is
  /// — they drive on-demand image fetching, and reach [cards] only through
  /// [showAwaitingCardsWithoutImages].
  List<SpeciesWithLocalImages> get awaitingImageCards => _awaitingImageCards;

  /// Whether every due card is currently held back for a missing image.
  bool get isWaitingForImages => _isWaitingForImages;

  /// Whether the async work of a caller that awaited something is still
  /// worth finishing — the counterpart to `State.mounted` for the loops
  /// driving this controller from outside.
  bool get isDisposed => _isDisposed;

  /// The review mode used for the CURRENT card: multiple choice falls back
  /// to flip for a single card whose name pool yielded too few distinct
  /// distractors, leaving the rest of the session untouched.
  ReviewMode get effectiveReviewMode => _sessionPresenter.effectiveReviewMode(
    reviewMode: _config.reviewMode,
    hasOptions: _options.isNotEmpty,
  );

  /// Whether [species] is one whose common-name enrichment hasn't reached a
  /// terminal state yet, so the primary name a card shows for it could still
  /// change. A snapshot taken alongside the cards themselves, not a live
  /// subscription, and only populated for the one mode combination whose
  /// primary name comes from species-level common-name enrichment.
  bool namesMayStillRefine(Species species) =>
      _pendingCommonNameSpeciesIds.contains(species.id);

  String primaryNameFor(Species species) => _speciesPresenter
      .present(
        species,
        _deck.language,
        learningMode: _config.learningMode,
        nameType: _config.nameType,
      )
      .identity
      .primaryName;

  /// Loads the deck configuration and everything a session derives from it,
  /// replacing whatever this controller held before. Also the reload path:
  /// the deck's cards change whenever enrichment, a removal or a new batch
  /// lands.
  Future<void> load() async {
    _status = ReviewSessionStatus.loading;
    _error = null;
    _currentIndex = 0;
    _previews = {};
    _notify();

    try {
      _config = await _flashcardService.getDeckConfig(_deck.id!);

      final data = await _sessionService.loadSessionData(
        deck: _deck,
        config: _config,
      );
      _cards = data.reviewableCards;
      _distractorPools = data.distractorPools;
      _isWaitingForImages = data.isWaitingForImages;
      _awaitingImageCards = data.awaitingImageCards;
      _pendingCommonNameSpeciesIds = data.pendingCommonNameSpeciesIds;
      _options = _cards.isEmpty ? [] : await _optionsFor(_cards.first);
      _status = ReviewSessionStatus.ready;
    } catch (error) {
      _error = error;
      _status = ReviewSessionStatus.failed;
    }
    _notify();
  }

  /// Moves to the next card. No-op on the last one — running out of cards is
  /// the page's decision to make (offer a new batch, or end the session).
  ///
  /// The next index is read before the card's options are computed and
  /// committed together with them, so two taps arriving while a pool is still
  /// loading both land on the same card instead of skipping one.
  Future<void> advance() async {
    if (isOnLastCard) return;
    final next = _currentIndex + 1;
    final options = await _optionsFor(_cards[next]);
    if (_isDisposed) return;
    _currentIndex = next;
    _options = options;
    _notify();
  }

  /// Grades the current card and requeues it when it is still in short-term
  /// learning or relearning. Owns the whole step, so the page does not have to
  /// hand the session's configuration and current card back to the service and
  /// then act on the result itself.
  Future<void> gradeCurrentCard(ReviewGrade grade) async {
    final result = await _sessionService.gradeCard(
      speciesId: currentCard.species.id,
      deckId: _deck.id!,
      config: _config,
      grade: grade,
    );
    if (_isDisposed) return;
    if (result.shouldRequeue) requeueCurrentCard();
  }

  /// Re-adds the current card to the end of the queue, for a card still in
  /// short-term learning or relearning. Nothing on screen changes yet, so
  /// this doesn't notify — the card the user sees is still the same one
  /// until [advance].
  void requeueCurrentCard() {
    _cards = [..._cards, currentCard];
  }

  /// Activates the next batch of new cards for this deck, on this session's
  /// configuration. Here rather than on the page, so no caller has to hand the
  /// session's own configuration back to the service for it.
  Future<void> initializeNextBatch({int batchSize = 10}) =>
      _sessionService.initializeNextBatch(
        _deck.id!,
        _config,
        batchSize: batchSize,
      );

  Future<void> loadPreviews() async {
    if (_cards.isEmpty) return;
    final previews = await _sessionService.getPreviewIntervals(
      currentCard.species.id,
      _deck.id!,
      _config,
    );
    if (_isDisposed) return;
    _previews = previews;
    _notify();
  }

  /// Removes [speciesId] from the deck and from this session — its cards and
  /// the names its distractors are drawn from — keeping the current index on
  /// a card that still exists.
  Future<void> removeSpecies(String speciesId) async {
    await _sessionService.removeSpeciesFromDeck(_deck.id!, speciesId);
    if (_isDisposed) return;
    _distractorPools = _distractorPools?.withoutSpecies(speciesId);

    final remaining = _cards
        .where((card) => card.species.id != speciesId)
        .toList();
    final index = _currentIndex < remaining.length
        ? _currentIndex
        : (remaining.isEmpty ? 0 : remaining.length - 1);
    final options = remaining.isEmpty
        ? <MultipleChoiceOption>[]
        : await _optionsFor(remaining[index]);
    if (_isDisposed) return;

    _cards = remaining;
    _currentIndex = index;
    _options = options;
    _notify();
  }

  /// Swaps in a card whose species just gained a local image.
  void replaceCard(SpeciesWithLocalImages updated) {
    final index = _cards.indexWhere(
      (card) => card.species.id == updated.species.id,
    );
    if (index == -1) return;
    _cards = [..._cards]..[index] = updated;
    _notify();
  }

  /// Gives up on finding images for the held-back cards and shows them as
  /// they are, rather than leaving the session on a spinner indefinitely.
  Future<void> showAwaitingCardsWithoutImages() async {
    if (_awaitingImageCards.isEmpty) return;
    final cards = _awaitingImageCards;
    final options = await _optionsFor(cards.first);
    if (_isDisposed) return;

    _cards = cards;
    _isWaitingForImages = false;
    _currentIndex = 0;
    _options = options;
    _notify();
  }

  /// The answer options for [card], awaiting its distractor pool — which a
  /// session builds per taxonomic scope on first use. An empty result is
  /// meaningful: it is what makes [effectiveReviewMode] fall back to flip for
  /// that one card.
  ///
  /// Pure: it computes options without touching session state, so every caller
  /// can decide which card is on screen and set its options in the same step,
  /// and no card is ever shown with another card's options.
  Future<List<MultipleChoiceOption>> _optionsFor(
    SpeciesWithLocalImages card,
  ) async {
    final pools = _distractorPools;
    if (pools == null || _config.reviewMode != ReviewMode.multipleChoice) {
      return [];
    }
    final species = card.species;
    final namePool = await pools.poolFor(species);
    return _answerOptionsPresenter.buildOptions(
          correctLabel: primaryNameFor(species),
          namePool: namePool,
        ) ??
        [];
  }

  void _notify() {
    if (_isDisposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
