import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/learning/flashcard/answer_options_presenter.dart';
import 'package:discere/learning/flashcard/deck_session_presenter.dart';
import 'package:discere/learning/flashcard/flashcard_species_presenter.dart';
import 'package:discere/learning/flashcard/multiple_choice_option.dart';
import 'package:discere/learning/flashcard/service/deck_session_service.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/model/base_deck.dart';
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
  LearningMode _learningMode = LearningMode.species;
  NameType _nameType = NameType.commonName;
  ReviewMode _reviewMode = ReviewMode.flip;
  List<String> _deckNamePool = [];
  Map<String, List<String>> _taxonomyPoolByScopeId = {};
  List<SpeciesWithLocalImages> _awaitingImageCards = [];
  bool _isWaitingForImages = false;
  Set<String> _pendingCommonNameSpeciesIds = {};
  bool _isDisposed = false;

  ReviewSessionStatus get status => _status;
  Object? get error => _error;
  List<SpeciesWithLocalImages> get cards => _cards;
  int get currentIndex => _currentIndex;
  List<MultipleChoiceOption> get options => _options;
  Map<ReviewGrade, String> get previews => _previews;
  LearningMode get learningMode => _learningMode;
  NameType get nameType => _nameType;
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
    reviewMode: _reviewMode,
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
        learningMode: _learningMode,
        nameType: _nameType,
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
      final config = await _flashcardService.getDeckConfig(_deck.id!);
      _learningMode = config.learningMode;
      _nameType = config.nameType;
      _reviewMode = config.reviewMode;

      final data = await _sessionService.loadSessionData(
        deck: _deck,
        config: config,
      );
      _cards = data.reviewableCards;
      _deckNamePool = data.deckNamePool;
      _taxonomyPoolByScopeId = data.taxonomyPoolByScopeId;
      _isWaitingForImages = data.isWaitingForImages;
      _awaitingImageCards = data.awaitingImageCards;
      _pendingCommonNameSpeciesIds = data.pendingCommonNameSpeciesIds;
      _updateOptions();
      _status = ReviewSessionStatus.ready;
    } catch (error) {
      _error = error;
      _status = ReviewSessionStatus.failed;
    }
    _notify();
  }

  /// Moves to the next card. No-op on the last one — running out of cards is
  /// the page's decision to make (offer a new batch, or end the session).
  void advance() {
    if (isOnLastCard) return;
    _currentIndex++;
    _updateOptions();
    _notify();
  }

  /// Re-adds the current card to the end of the queue, for a card still in
  /// short-term learning or relearning. Nothing on screen changes yet, so
  /// this doesn't notify — the card the user sees is still the same one
  /// until [advance].
  void requeueCurrentCard() {
    _cards = [..._cards, currentCard];
  }

  Future<void> loadPreviews() async {
    if (_cards.isEmpty) return;
    final previews = await _sessionService.getPreviewIntervals(
      currentCard.species.id,
      _deck.id!,
    );
    if (_isDisposed) return;
    _previews = previews;
    _notify();
  }

  /// Removes [speciesId] from the deck and from this session, keeping the
  /// current index on a card that still exists.
  Future<void> removeSpecies(String speciesId) async {
    await _sessionService.removeSpeciesFromDeck(_deck.id!, speciesId);
    if (_isDisposed) return;
    _cards = _cards.where((card) => card.species.id != speciesId).toList();
    if (_currentIndex >= _cards.length) {
      _currentIndex = _cards.isEmpty ? 0 : _cards.length - 1;
    }
    _updateOptions();
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
  void showAwaitingCardsWithoutImages() {
    if (_awaitingImageCards.isEmpty) return;
    _cards = _awaitingImageCards;
    _isWaitingForImages = false;
    _currentIndex = 0;
    _updateOptions();
    _notify();
  }

  /// (Re)computes the answer options for the current card. An empty result
  /// is meaningful: it is what makes [effectiveReviewMode] fall back to flip
  /// for this one card.
  void _updateOptions() {
    if (_reviewMode != ReviewMode.multipleChoice || _cards.isEmpty) {
      _options = [];
      return;
    }
    final species = currentCard.species;
    final scopeId = _sessionService.scopeIdFor(_learningMode, species);
    final namePool = scopeId != null
        ? (_taxonomyPoolByScopeId[scopeId] ?? _deckNamePool)
        : _deckNamePool;
    _options =
        _answerOptionsPresenter.buildOptions(
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
