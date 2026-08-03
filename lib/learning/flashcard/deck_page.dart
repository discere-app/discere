import 'dart:async';

import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/flashcard/answer_options_presenter.dart';
import 'package:discere/learning/flashcard/deck_session_presenter.dart';
import 'package:discere/learning/flashcard/flashcard_buttons.dart';
import 'package:discere/learning/flashcard/flashcard_species_presenter.dart';
import 'package:discere/learning/flashcard/flashcard_widget.dart';
import 'package:discere/learning/flashcard/multiple_choice_option.dart';
import 'package:discere/learning/flashcard/no_photo_gaps_dialog.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/learning/service/fsrs_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

class DeckPage extends StatefulWidget {
  final BaseDeck deck;

  const DeckPage({required this.deck, super.key});

  @override
  DeckPageState createState() => DeckPageState();
}

class DeckPageState extends State<DeckPage> {
  static const AnswerOptionsPresenter _answerOptionsPresenter =
      AnswerOptionsPresenter();
  static const FlashcardSpeciesPresenter _speciesPresenter =
      FlashcardSpeciesPresenter();
  static const DeckSessionPresenter _sessionPresenter = DeckSessionPresenter();

  late final FlashcardService _flashcardService;
  late final DecksService _decksService;
  late final INatEnrichmentQueueService _enrichmentQueueService;
  late Future<List<SpeciesWithLocalImages>> _flashCardsFuture;
  late DeckEnrichmentInfo _lastEnrichmentInfo;
  late List<SpeciesWithLocalImages> _flashCards;
  // Cards due for review whose species has no local image yet, hidden from
  // the session by _sessionPresenter.filterReviewableCards while the deck's
  // image-loading enrichment stages are still in flight. Kept around only to
  // drive _ensureAnyImageAvailable — not shown.
  List<SpeciesWithLocalImages> _awaitingImageCards = [];
  bool _isWaitingForImages = false;
  LearningMode _learningMode = LearningMode.species;
  NameType _nameType = NameType.commonName;
  ReviewMode _reviewMode = ReviewMode.flip;
  List<String> _deckNamePool = [];
  List<MultipleChoiceOption> _currentOptions = [];

  /// The review mode actually used for the CURRENT card. Derived from
  /// [_reviewMode] and whether [_currentOptions] could be built for this
  /// specific card, so a single card without enough distinct distractors
  /// only falls back to flip mode for itself, not for the rest of the
  /// session (other cards may well have enough distractors).
  ReviewMode get _effectiveReviewMode => _sessionPresenter.effectiveReviewMode(
    reviewMode: _reviewMode,
    hasOptions: _currentOptions.isNotEmpty,
  );
  int _currentFlashcardIndex = 0;
  Map<ReviewGrade, String> _previews = {};
  final Set<String> _singleImageAttemptedSpeciesIds = <String>{};
  bool _isPrioritizedImageLoadInFlight = false;
  final GlobalKey _againKey = GlobalKey();
  final GlobalKey _hardKey = GlobalKey();
  final GlobalKey _goodKey = GlobalKey();
  final GlobalKey _easyKey = GlobalKey();
  final GlobalKey _watchlistButtonKey = GlobalKey();
  final GlobalKey _imageKey = GlobalKey();

  // Notification rescheduling is batched to session end (see dispose())
  // instead of running after every single card grade.
  bool _hasReviewedThisSession = false;
  String? _notificationTitle;
  String Function(int)? _notificationBodyBuilder;

  // Guards _maybeCheckPhotoGaps so the "no photo found" gaps dialog is
  // offered at most once per DeckPage instance — once the deck's image
  // stages are complete, that state never changes again for this session.
  bool _hasCheckedPhotoGaps = false;

  @override
  void initState() {
    super.initState();
    _flashcardService = Provider.of<FlashcardService>(context, listen: false);
    _decksService = Provider.of<DecksService>(context, listen: false);
    _enrichmentQueueService = Provider.of<INatEnrichmentQueueService>(
      context,
      listen: false,
    );
    _lastEnrichmentInfo = _enrichmentQueueService.deckInfo(widget.deck.id!);
    _enrichmentQueueService.addListener(_handleEnrichmentQueueChanged);
    unawaited(_enrichmentQueueService.enterInteractivePriorityMode());
    unawaited(_flashcardService.notificationService.requestPermissions());
    _initializeFlashcards();
  }

  @override
  void dispose() {
    _enrichmentQueueService.removeListener(_handleEnrichmentQueueChanged);
    unawaited(_enrichmentQueueService.leaveInteractivePriorityMode());
    if (_hasReviewedThisSession) {
      unawaited(
        _flashcardService.rescheduleNotifications(
          notificationTitle: _notificationTitle,
          notificationBodyBuilder: _notificationBodyBuilder,
        ),
      );
    }
    super.dispose();
  }

  void _initializeFlashcards() {
    final future = _loadFlashcards();
    setState(() {
      _flashCardsFuture = future;
      _currentFlashcardIndex = 0;
      _previews = {};
      _singleImageAttemptedSpeciesIds.clear();
    });

    future.then((cards) async {
      if (!mounted) return;
      _flashCards = cards;
      unawaited(_maybeCheckPhotoGaps());
      if (cards.isNotEmpty) {
        _updateCurrentOptions();
        unawaited(_ensureCurrentFlashcardImage(cards: cards, index: 0));
        _maybeShowFlashcardTutorial();
      }
      if (cards.isEmpty && _isWaitingForImages) {
        unawaited(_ensureAnyImageAvailable());
      } else if (cards.isEmpty) {
        final deckStat = await _flashcardService.getDeckStat(widget.deck.id!);
        if (!mounted) return;
        switch (_sessionPresenter.decideNewCardsAction(deckStat)) {
          case NewCardsAction.none:
            break;
          case NewCardsAction.autoInitialize:
            unawaited(
              _flashcardService.initializeNextBatch(widget.deck.id!).then((_) {
                if (mounted) _initializeFlashcards();
              }),
            );
          case NewCardsAction.promptUser:
            _showMoreNewFlashcardsAvailable(context);
        }
      }
    });
  }

  Future<List<SpeciesWithLocalImages>> _loadFlashcards() async {
    final config = await _flashcardService.getDeckConfig(widget.deck.id!);
    if (mounted &&
        (_learningMode != config.learningMode ||
            _nameType != config.nameType)) {
      setState(() {
        _learningMode = config.learningMode;
        _nameType = config.nameType;
      });
    } else {
      _learningMode = config.learningMode;
      _nameType = config.nameType;
    }
    _reviewMode = config.reviewMode;

    if (_reviewMode == ReviewMode.multipleChoice) {
      final deckSpecies = await _decksService.getSpeciesByDeckId(
        widget.deck.id!,
      );
      _deckNamePool = _answerOptionsPresenter.distinctPrimaryNames(
        deckSpecies,
        widget.deck.language,
        _learningMode,
        _nameType,
      );
    } else {
      _deckNamePool = [];
    }

    final rawCards = await _flashcardService.getFlashCardsForReview(
      widget.deck.id!,
    );
    final imageStagesComplete = _enrichmentQueueService
        .deckInfo(widget.deck.id!)
        .imageStagesComplete;
    final reviewableCards = _sessionPresenter.filterReviewableCards(
      rawCards,
      imageStagesComplete: imageStagesComplete,
    );
    _isWaitingForImages = rawCards.isNotEmpty && reviewableCards.isEmpty;
    _awaitingImageCards = _isWaitingForImages ? rawCards : const [];
    return reviewableCards;
  }

  String _primaryNameFor(Species species) => _speciesPresenter
      .present(
        species,
        widget.deck.language,
        learningMode: _learningMode,
        nameType: _nameType,
      )
      .identity
      .primaryName;

  /// (Re)computes [_currentOptions] for the current flashcard. If this card's
  /// name pool doesn't yield enough distinct distractors, [_currentOptions]
  /// ends up empty and [_effectiveReviewMode] falls back to flip mode for
  /// just this card — other cards are unaffected.
  void _updateCurrentOptions() {
    if (_reviewMode != ReviewMode.multipleChoice || _flashCards.isEmpty) {
      _currentOptions = [];
      return;
    }
    _currentOptions =
        _answerOptionsPresenter.buildOptions(
          correctLabel: _primaryNameFor(getCurrentFlashcard().species),
          namePool: _deckNamePool,
        ) ??
        [];
  }

  void _handleEnrichmentQueueChanged() {
    final nextInfo = _enrichmentQueueService.deckInfo(widget.deck.id!);
    final shouldRefresh = _sessionPresenter.shouldRefreshAfterEnrichmentChange(
      previous: _lastEnrichmentInfo,
      next: nextInfo,
    );

    _lastEnrichmentInfo = nextInfo;

    if (!mounted) return;
    unawaited(_maybeCheckPhotoGaps());
    if (!shouldRefresh) return;
    _initializeFlashcards();
  }

  /// Offers the "no photo found" gaps dialog once the deck's image
  /// enrichment stages are complete (see [FlashcardService
  /// .getUnacknowledgedPhotoGaps]'s doc for why cache-only resolution is safe
  /// at that point) and there are species the user hasn't already decided to
  /// keep. Guarded by [_hasCheckedPhotoGaps] so this only ever runs once per
  /// DeckPage instance.
  Future<void> _maybeCheckPhotoGaps() async {
    if (_hasCheckedPhotoGaps) return;
    if (!_enrichmentQueueService.deckInfo(widget.deck.id!).imageStagesComplete) {
      return;
    }
    _hasCheckedPhotoGaps = true;

    final deckSpecies = await _decksService.getSpeciesByDeckId(
      widget.deck.id!,
    );
    final gaps = await _flashcardService.getUnacknowledgedPhotoGaps(
      widget.deck.id!,
      deckSpecies.map((species) => species.id).toSet(),
    );
    if (!mounted || gaps.isEmpty) return;

    final checkedForRemoval = await showNoPhotoGapsDialog(
      context,
      gaps
          .map(
            (card) => NoPhotoGapSpecies(
              speciesId: card.species.id,
              displayName: _primaryNameFor(card.species),
            ),
          )
          .toList(),
    );
    if (!mounted) return;

    for (final speciesId in checkedForRemoval) {
      await _decksService.removeSpeciesFromDeck(widget.deck.id!, speciesId);
    }
    final toKeep = gaps
        .map((card) => card.species.id)
        .toSet()
        .difference(checkedForRemoval);
    if (toKeep.isNotEmpty) {
      await _flashcardService.acknowledgePhotoGaps(widget.deck.id!, toKeep);
    }
    if (checkedForRemoval.isNotEmpty && mounted) {
      _initializeFlashcards();
    }
  }

  Future<void> _handleRemoveSpeciesFromCard(String speciesId) async {
    await _decksService.removeSpeciesFromDeck(widget.deck.id!, speciesId);
    if (!mounted) return;

    _flashCards = _flashCards
        .where((card) => card.species.id != speciesId)
        .toList();
    if (_currentFlashcardIndex >= _flashCards.length) {
      _currentFlashcardIndex = _flashCards.isEmpty
          ? 0
          : _flashCards.length - 1;
    }
    setState(() {
      _flashCardsFuture = Future.value(_flashCards);
      _updateCurrentOptions();
    });
    if (_flashCards.isEmpty) return;
    unawaited(_ensureCurrentFlashcardImage());
    if (_effectiveReviewMode == ReviewMode.flip) {
      unawaited(_loadPreviews());
    }
  }

  SpeciesWithLocalImages getCurrentFlashcard() =>
      _flashCards[_currentFlashcardIndex];

  Future<void> _loadPreviews() async {
    if (_flashCards.isEmpty) return;
    final card = getCurrentFlashcard();
    final previews = await _flashcardService.getPreviewIntervals(
      card.species.id,
      widget.deck.id!,
    );
    if (mounted) setState(() => _previews = previews);
  }

  Future<void> _gradeCurrentCard(ReviewGrade grade) async {
    // Notification rescheduling is deferred to dispose() so a review
    // session reschedules once instead of once per graded card. Capture
    // the localized strings now, before the `await` below, since dispose()
    // can't safely resolve them from context.
    final loc = context.loc;
    _hasReviewedThisSession = true;
    _notificationTitle = loc.notificationDailyTitle;
    _notificationBodyBuilder = loc.notificationDailyBody;

    final stat = await _flashcardService.reviewCard(
      getCurrentFlashcard().species.id,
      widget.deck.id!,
      grade,
    );

    // Cards still in learning/relearning get re-added to the queue
    if (_sessionPresenter.shouldRequeue(stat.cardState)) {
      _flashCards.add(getCurrentFlashcard());
    }
  }

  Future<void> _onGrade(ReviewGrade grade) async {
    await _gradeCurrentCard(grade);
    await _showNextFlashcard();
  }

  /// Called as soon as the user taps an option in multiple-choice mode —
  /// grading happens immediately on tap, independent of the later "Continue"
  /// tap that advances to the next card (see [_onContinueTapped]).
  Future<void> _onMultipleChoiceAnswered(bool isCorrect) =>
      _gradeCurrentCard(isCorrect ? ReviewGrade.good : ReviewGrade.again);

  void _onContinueTapped() => _showNextFlashcard();

  Future<void> _showNextFlashcard() async {
    if (_currentFlashcardIndex < _flashCards.length - 1) {
      setState(() {
        _currentFlashcardIndex++;
        _updateCurrentOptions();
      });
      unawaited(_ensureCurrentFlashcardImage());
      if (_effectiveReviewMode == ReviewMode.flip) {
        unawaited(_loadPreviews());
      }
    } else {
      final deckStat = await _flashcardService.getDeckStat(widget.deck.id!);

      if (!mounted) return;

      if (deckStat.uninitializedCount > 0) {
        _showMoreNewFlashcardsAvailable(context);
      } else {
        _showNoMoreFlashcardsAvailableWithNoCards(context);
      }
    }
  }

  Future<void> _ensureCurrentFlashcardImage({
    List<SpeciesWithLocalImages>? cards,
    int? index,
  }) async {
    if (_isPrioritizedImageLoadInFlight) return;
    final targetCards = cards ?? _flashCards;
    if (targetCards.isEmpty) return;

    final targetIndex = index ?? _currentFlashcardIndex;
    if (targetIndex < 0 || targetIndex >= targetCards.length) return;

    final flashcard = targetCards[targetIndex];
    if (flashcard.localPictures.isNotEmpty) return;

    final speciesId = flashcard.species.id;
    if (_singleImageAttemptedSpeciesIds.contains(speciesId)) {
      return;
    }

    _singleImageAttemptedSpeciesIds.add(speciesId);
    _isPrioritizedImageLoadInFlight = true;
    try {
      final updated = await _flashcardService.ensureSingleImageForSpecies(
        speciesId,
      );
      if (!mounted || updated == null) return;

      final latestCards = List<SpeciesWithLocalImages>.from(
        cards ?? _flashCards,
      );
      final latestIndex = latestCards.indexWhere(
        (card) => card.species.id == speciesId,
      );
      if (latestIndex == -1) return;

      latestCards[latestIndex] = updated;
      setState(() {
        _flashCards = latestCards;
        _flashCardsFuture = Future.value(latestCards);
      });
    } finally {
      _isPrioritizedImageLoadInFlight = false;
      if (mounted) {
        unawaited(_ensureCurrentFlashcardImage());
      }
    }
  }

  /// Every card due for review is hidden (see [_isWaitingForImages]) because
  /// none of them has a local image yet. Fetches images one species at a
  /// time — reusing the same on-demand primitive as
  /// [_ensureCurrentFlashcardImage] — until one succeeds, then reloads the
  /// session so that card can appear. Bounded to avoid a long serial stall
  /// (e.g. offline) on decks with many species; the background enrichment
  /// queue (paused for the duration of this session, see
  /// [INatEnrichmentQueueService.enterInteractivePriorityMode]) continues
  /// filling in the rest once the session ends.
  ///
  /// If every attempted species still comes up without an image, the queue's
  /// own give-up mechanism (`BaseWorker`/`INatWorker`'s `_maxAttempts`) can't
  /// help within this session — it's paused for as long as interactive
  /// priority mode holds, and normally needs several throttled retries to
  /// converge. Rather than leaving the spinner up indefinitely, the raw cards
  /// are shown without images once attempts are exhausted.
  static const _maxAwaitingImageFetchAttempts = 10;

  Future<void> _ensureAnyImageAvailable() async {
    if (_isPrioritizedImageLoadInFlight) return;
    final candidates = _awaitingImageCards.take(_maxAwaitingImageFetchAttempts);
    for (final card in candidates) {
      if (!mounted) return;
      final speciesId = card.species.id;
      if (_singleImageAttemptedSpeciesIds.contains(speciesId)) continue;

      _singleImageAttemptedSpeciesIds.add(speciesId);
      _isPrioritizedImageLoadInFlight = true;
      try {
        final updated = await _flashcardService.ensureSingleImageForSpecies(
          speciesId,
        );
        if (!mounted) return;
        if (updated != null && updated.localPictures.isNotEmpty) {
          _initializeFlashcards();
          return;
        }
      } finally {
        _isPrioritizedImageLoadInFlight = false;
      }
    }
    if (!mounted || _awaitingImageCards.isEmpty) return;
    final cardsWithoutImages = _awaitingImageCards;
    setState(() {
      _flashCards = cardsWithoutImages;
      _flashCardsFuture = Future.value(cardsWithoutImages);
      _isWaitingForImages = false;
      _currentFlashcardIndex = 0;
      _updateCurrentOptions();
    });
    if (_effectiveReviewMode == ReviewMode.flip) {
      unawaited(_loadPreviews());
    }
    _maybeShowFlashcardTutorial();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.deck.name)),
      body: SafeArea(
        child: Center(
          child: FutureBuilder<List<SpeciesWithLocalImages>>(
            future: _flashCardsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              } else if (snapshot.hasError) {
                return Text('${context.loc.error}: ${snapshot.error}');
              } else {
                _flashCards = snapshot.data ?? [];
                if (_flashCards.isNotEmpty &&
                    _previews.isEmpty &&
                    _effectiveReviewMode == ReviewMode.flip) {
                  _loadPreviews();
                }
                return Column(
                  children: [
                    Expanded(
                      child: _flashCards.isEmpty
                          ? Padding(
                              padding: AppSpacing.emptyStatePaddingAll,
                              child: Center(
                                child: _isWaitingForImages
                                    ? Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const CircularProgressIndicator(),
                                          AppSpacing.heightS24,
                                          Text(
                                            context
                                                .loc
                                                .flashcardImagesDownloading,
                                            key: const Key(
                                              'images_downloading_empty_state_text',
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      )
                                    : Text(
                                        context.loc.commonNoFlashcardsAvailable,
                                        key: const Key(
                                          'no_flashcards_empty_state_text',
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                              ),
                            )
                          : FlashcardWidget(
                              // A card can be re-appended to _flashCards for
                              // relearning as the SAME object instance
                              // (deck_page.dart's _gradeCurrentCard); keying
                              // by index (rather than relying on
                              // FlashcardWidget's own object-equality check
                              // in didUpdateWidget) guarantees a fresh state
                              // even when that instance reappears at the
                              // very next position.
                              key: ValueKey(_currentFlashcardIndex),
                              speciesWithLocalImage: getCurrentFlashcard(),
                              language: widget.deck.language,
                              learningMode: _learningMode,
                              nameType: _nameType,
                              reviewMode: _effectiveReviewMode,
                              multipleChoiceOptions: _currentOptions,
                              onMultipleChoiceAnswered:
                                  _onMultipleChoiceAnswered,
                              onContinue: _onContinueTapped,
                              onRemoveSpecies: _handleRemoveSpeciesFromCard,
                              watchlistKey: _watchlistButtonKey,
                              imageKey: _imageKey,
                            ),
                    ),
                    if (_flashCards.isNotEmpty &&
                        _effectiveReviewMode == ReviewMode.flip) ...[
                      AppSpacing.heightS24,
                      FlashcardButtons(
                        onAgain: () => _onGrade(ReviewGrade.again),
                        onHard: () => _onGrade(ReviewGrade.hard),
                        onGood: () => _onGrade(ReviewGrade.good),
                        onEasy: () => _onGrade(ReviewGrade.easy),
                        timeAgain: _previews[ReviewGrade.again] ?? '',
                        timeHard: _previews[ReviewGrade.hard] ?? '',
                        timeGood: _previews[ReviewGrade.good] ?? '',
                        timeEasy: _previews[ReviewGrade.easy] ?? '',
                        againKey: _againKey,
                        hardKey: _hardKey,
                        goodKey: _goodKey,
                        easyKey: _easyKey,
                      ),
                    ],
                  ],
                );
              }
            },
          ),
        ),
      ),
    );
  }

  void _showMoreNewFlashcardsAvailable(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.loc.flashcardActivateMoreCardsTitle,
          key: const Key('activation_dialog_title'),
        ),
        content: Text(context.loc.flashcardActivateMoreCardsDescription),
        actions: [
          TextButton(
            key: const Key('activation_dialog_yes_button'),
            child: Text(context.loc.commonYes),
            onPressed: () {
              _flashcardService.initializeNextBatch(widget.deck.id!).then((_) {
                if (mounted) _initializeFlashcards();
              });
              Navigator.of(context).pop();
            },
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(context.loc.commonNo),
          ),
        ],
      ),
    );
  }

  void _showNoMoreFlashcardsAvailableWithNoCards(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.loc.flashcardNoMoreCardsToLearnTitle,
          key: const Key('no_more_cards_dialog_title'),
        ),
        content: Text(context.loc.flashcardNoMoreCardsToLearnDescription),
        actions: [
          TextButton(
            key: const Key('no_more_cards_ok_button'),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Zurück zur Startseite
            },
            child: Text(context.loc.commonOk),
          ),
        ],
      ),
    );
  }

  void _maybeShowFlashcardTutorial() {
    // The coach marks target the 4 FSRS rating buttons, which aren't shown
    // in multiple-choice mode. A dedicated MCQ tutorial is a follow-up.
    if (_effectiveReviewMode != ReviewMode.flip) return;
    final prefs = Provider.of<UserPreferencesService>(context, listen: false);
    if (prefs.hasSeenFlashcardTutorial) return;
    prefs.hasSeenFlashcardTutorial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _showFlashcardTutorial();
    });
  }

  void _showFlashcardTutorial() {
    final loc = context.loc;
    final hasImage = getCurrentFlashcard().localPictures.isNotEmpty;
    TutorialCoachMark(
      targets: [
        // No real widget is highlighted here — a zero-size target centered
        // on screen just gives the overlay text to show without a focus
        // ring, so the tour visibly announces itself as a tour instead of
        // silently pointing at the first button (testers mistook that for
        // an accidental tap/bug).
        TargetFocus(
          identify: 'intro',
          targetPosition: TargetPosition(
            Size.zero,
            Offset(
              MediaQuery.sizeOf(context).width / 2,
              MediaQuery.sizeOf(context).height * 0.4,
            ),
          ),
          paddingFocus: 0,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              child: _buildCoachMarkContent(
                loc.tutorialIntroTitle,
                loc.tutorialFlashcardIntroDescription,
              ),
            ),
          ],
        ),
        if (hasImage)
          TargetFocus(
            identify: 'image',
            keyTarget: _imageKey,
            shape: ShapeLightFocus.RRect,
            contents: [
              TargetContent(
                align: ContentAlign.bottom,
                child: _buildCoachMarkContent(
                  loc.tutorialFlashcardImageTitle,
                  loc.tutorialFlashcardImageDescription,
                ),
              ),
            ],
          ),
        TargetFocus(
          identify: 'again',
          keyTarget: _againKey,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              child: _buildCoachMarkContent(
                loc.flashcardButtonAgain,
                loc.tutorialFlashcardAgainDescription,
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'hard',
          keyTarget: _hardKey,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              child: _buildCoachMarkContent(
                loc.flashcardButtonHard,
                loc.tutorialFlashcardHardDescription,
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'good',
          keyTarget: _goodKey,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              child: _buildCoachMarkContent(
                loc.flashcardButtonGood,
                loc.tutorialFlashcardGoodDescription,
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'easy',
          keyTarget: _easyKey,
          shape: ShapeLightFocus.RRect,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              child: _buildCoachMarkContent(
                loc.flashcardButtonEasy,
                loc.tutorialFlashcardEasyDescription,
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'watchlist',
          keyTarget: _watchlistButtonKey,
          shape: ShapeLightFocus.Circle,
          paddingFocus: 8,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              child: _buildCoachMarkContent(
                loc.tutorialFlashcardWatchlistTitle,
                loc.tutorialFlashcardWatchlistDescription,
              ),
            ),
          ],
        ),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      paddingFocus: 8,
      textSkip: loc.tutorialSkip,
      // Every step's content sits in the lower half of the card (rating
      // buttons, image caption), so the default bottom-right skip button
      // would sit on top of the Easy button — move it to the top instead.
      alignSkip: Alignment.topRight,
      onSkip: () => true,
    ).show(context: context);
  }

  Widget _buildCoachMarkContent(String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}
