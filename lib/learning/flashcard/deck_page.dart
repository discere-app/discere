import 'dart:async';

import 'package:discere/catalog/model/species.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_info.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_state.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/decks/deck_download_choice_dialog.dart';
import 'package:discere/learning/flashcard/activate_more_cards_dialog.dart';
import 'package:discere/learning/flashcard/answer_options_presenter.dart';
import 'package:discere/learning/flashcard/deck_session_presenter.dart';
import 'package:discere/learning/flashcard/flashcard_buttons.dart';
import 'package:discere/learning/flashcard/flashcard_species_presenter.dart';
import 'package:discere/learning/flashcard/flashcard_tutorial.dart';
import 'package:discere/learning/flashcard/flashcard_widget.dart';
import 'package:discere/learning/flashcard/flip_swipe_detector.dart';
import 'package:discere/learning/flashcard/multiple_choice_option.dart';
import 'package:discere/learning/flashcard/no_data_downloaded_dialog.dart';
import 'package:discere/learning/flashcard/no_photo_gaps_dialog.dart';
import 'package:discere/learning/flashcard/service/deck_session_service.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:discere/shared/ui/notification_permission_dialog.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
  late final INatEnrichmentQueueService _enrichmentQueueService;
  late final DeckSessionService _sessionService;
  late Future<List<SpeciesWithLocalImages>> _flashCardsFuture;
  late DeckEnrichmentInfo _lastEnrichmentInfo;
  late List<SpeciesWithLocalImages> _flashCards;
  // Cards due for review whose species has no local image yet, hidden from
  // the session by _sessionPresenter.filterReviewableCards while the deck's
  // image-loading enrichment stages are still in flight. Kept around only to
  // drive _ensureAnyImageAvailable — not shown.
  List<SpeciesWithLocalImages> _awaitingImageCards = [];
  bool _isWaitingForImages = false;
  // Species among the current _flashCards whose common-name enrichment
  // hasn't reached a terminal state yet — a snapshot taken alongside
  // _flashCards itself (see _loadFlashcards), not a live subscription. Only
  // populated for LearningMode.species + NameType.commonName, since that's
  // the only combination where FlashcardSpeciesPresenter's primary name
  // actually comes from species-level common-name enrichment.
  Set<String> _pendingCommonNameSpeciesIds = {};
  LearningMode _learningMode = LearningMode.species;
  NameType _nameType = NameType.commonName;
  ReviewMode _reviewMode = ReviewMode.flip;
  List<String> _deckNamePool = [];
  // Taxonomically-scoped distractor pools, keyed by the ancestor id relevant
  // to _learningMode (genusId for species mode, familyId for genus mode,
  // orderId for family mode). Precomputed once per _loadFlashcards() call
  // (one entry per distinct scope actually present in the deck) so
  // _updateCurrentOptions() can stay a synchronous map lookup on the
  // card-advance hot path. _deckNamePool is the fallback when a card's
  // scope isn't in this map (e.g. missing classification ids).
  Map<String, List<String>> _taxonomyPoolByScopeId = {};
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
  final GlobalKey _optionsKey = GlobalKey();

  /// The current card's flip controller, handed up via
  /// FlashcardWidget.onFlipControllerReady — lets the rating-button rail
  /// (owned here, not by FlashcardWidget) drive the same tap/drag-to-flip
  /// as the card itself, since in landscape the card's own swipeable area
  /// (the hints column) can be narrow. Re-registered on every card change;
  /// [_railFlipController] reads it lazily so the button rail's own
  /// gesture detector never has to be rebuilt when it changes.
  FlashcardFlipController? _flipController;

  FlashcardFlipController get _railFlipController => FlashcardFlipController(
    onTap: () => _flipController?.onTap(),
    onDragStart: (axis) => _flipController?.onDragStart(axis),
    onDragUpdate: (axis, delta) => _flipController?.onDragUpdate(axis, delta),
    onDragEnd: () => _flipController?.onDragEnd(),
  );

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
    _enrichmentQueueService = Provider.of<INatEnrichmentQueueService>(
      context,
      listen: false,
    );
    _sessionService = Provider.of<DeckSessionService>(context, listen: false);
    _lastEnrichmentInfo = _enrichmentQueueService.deckInfo(widget.deck.id!);
    _enrichmentQueueService.addListener(_handleEnrichmentQueueChanged);
    unawaited(_enrichmentQueueService.enterInteractivePriorityMode());
    unawaited(
      Provider.of<NotificationService>(
        context,
        listen: false,
      ).requestPermissions(),
    );
    // Lift the app-wide portrait lock (see main.dart) so the review flow can
    // use a landscape layout — restored on dispose.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _initializeFlashcards();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
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
              _sessionService.initializeNextBatch(widget.deck.id!).then((_) {
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

    final sessionData = await _sessionService.loadSessionData(
      deck: widget.deck,
      config: config,
    );
    _deckNamePool = sessionData.deckNamePool;
    _taxonomyPoolByScopeId = sessionData.taxonomyPoolByScopeId;
    _isWaitingForImages = sessionData.isWaitingForImages;
    _awaitingImageCards = sessionData.awaitingImageCards;
    _pendingCommonNameSpeciesIds = sessionData.pendingCommonNameSpeciesIds;

    return sessionData.reviewableCards;
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
    final species = getCurrentFlashcard().species;
    final scopeId = _sessionService.scopeIdFor(_learningMode, species);
    final namePool = scopeId != null
        ? (_taxonomyPoolByScopeId[scopeId] ?? _deckNamePool)
        : _deckNamePool;
    _currentOptions =
        _answerOptionsPresenter.buildOptions(
          correctLabel: _primaryNameFor(species),
          namePool: namePool,
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

  /// Offers a photo-gap resolution once the deck's image enrichment stages
  /// are complete (see [FlashcardService.getUnacknowledgedPhotoGaps]'s doc
  /// for why cache-only resolution is safe at that point). Guarded by
  /// [_hasCheckedPhotoGaps] so this only ever runs once per DeckPage
  /// instance.
  ///
  /// Three cases, depending on what was ever downloaded for this deck:
  /// - nothing at all ([DeckEnrichmentState.hidden]) — checking individual
  ///   species would be pointless since none of them have anything; offer to
  ///   start the download instead ([showNoDataDownloadedDialog]).
  /// - base data only — [showNoPhotoGapsDialog] additionally offers to run
  ///   iNaturalist enrichment for the whole deck, since a missing photo here
  ///   doesn't mean none exists.
  /// - iNaturalist was already tried — unchanged: offer only to remove gap
  ///   species, and permanently acknowledge whichever ones are kept.
  Future<void> _maybeCheckPhotoGaps() async {
    if (_hasCheckedPhotoGaps) return;
    final info = _enrichmentQueueService.deckInfo(widget.deck.id!);

    if (info.state == DeckEnrichmentState.hidden) {
      _hasCheckedPhotoGaps = true;
      final startDownload = await showNoDataDownloadedDialog(context);
      if (!mounted || !startDownload) return;
      final choice = await showDeckDownloadChoiceDialog(context);
      if (!mounted) return;
      await applyDeckDownloadChoice(
        context,
        _enrichmentQueueService,
        widget.deck.id!,
        choice,
      );
      return;
    }

    if (!info.imageStagesComplete) return;
    _hasCheckedPhotoGaps = true;

    final gaps = await _sessionService.getUnacknowledgedPhotoGaps(
      widget.deck.id!,
    );
    if (!mounted || gaps.isEmpty) return;

    final offerEnrichment = !info.includesINatPhotos;
    final outcome = await showNoPhotoGapsDialog(
      context,
      gaps
          .map(
            (card) => NoPhotoGapSpecies(
              speciesId: card.species.id,
              displayName: _primaryNameFor(card.species),
            ),
          )
          .toList(),
      offerEnrichment: offerEnrichment,
    );
    if (!mounted) return;

    switch (outcome.action) {
      case NoPhotoGapsAction.enrichDeck:
        await ensureNotificationPermission(context);
        if (!mounted) return;
        await _enrichmentQueueService.scheduleDeckEnrichment(
          [widget.deck.id!],
          includeINatPhotos: true,
          includeCommonNames: true,
        );
      case NoPhotoGapsAction.removeSelected:
        final toAcknowledge = offerEnrichment
            ? const <String>{}
            : gaps
                  .map((card) => card.species.id)
                  .toSet()
                  .difference(outcome.speciesToRemove);
        await _sessionService.removeSpeciesAndAcknowledgeGaps(
          deckId: widget.deck.id!,
          toRemove: outcome.speciesToRemove,
          toAcknowledge: toAcknowledge,
        );
        if (outcome.speciesToRemove.isNotEmpty && mounted) {
          _initializeFlashcards();
        }
      case NoPhotoGapsAction.skip:
        return;
    }
  }

  Future<void> _handleRemoveSpeciesFromCard(String speciesId) async {
    await _sessionService.removeSpeciesFromDeck(widget.deck.id!, speciesId);
    if (!mounted) return;

    _flashCards = _flashCards
        .where((card) => card.species.id != speciesId)
        .toList();
    if (_currentFlashcardIndex >= _flashCards.length) {
      _currentFlashcardIndex = _flashCards.isEmpty ? 0 : _flashCards.length - 1;
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
    final previews = await _sessionService.getPreviewIntervals(
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

    final result = await _sessionService.gradeCard(
      speciesId: getCurrentFlashcard().species.id,
      deckId: widget.deck.id!,
      grade: grade,
    );

    // Cards still in learning/relearning get re-added to the queue
    if (result.shouldRequeue) {
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
      final updated = await _sessionService.ensureSingleImageForSpecies(
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
        final updated = await _sessionService.ensureSingleImageForSpecies(
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
    final content = FutureBuilder<List<SpeciesWithLocalImages>>(
      future: _flashCardsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(
            child: Text(
              '${context.loc.error}: ${context.loc.describeError(snapshot.error)}',
            ),
          );
        } else {
          return _buildSessionBody(context, snapshot);
        }
      },
    );

    // A landscape phone screen has very little height to begin with
    // (~256dp of usable body height is typical) — a plain AppBar with no
    // title still reserves its full toolbar height, so landscape drops the
    // AppBar entirely and floats a small back button over the content
    // instead (same pattern as FullscreenImageViewer's close button).
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (isLandscape) {
      return Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: content),
              Positioned(
                top: AppSpacing.s8,
                left: AppSpacing.s8,
                child: _FloatingBackButton(),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.deck.name)),
      body: SafeArea(child: content),
    );
  }

  /// Broken out of build() (rather than left as a builder closure) because
  /// the landscape branch needs an explicit LayoutBuilder-derived box —
  /// nesting that inside the removed `Center` gave the Row's cross axis
  /// (height) only a loose bound, which let a Row child (the button rail)
  /// collapse to an under-sized height instead of filling the available
  /// space (Column doesn't have this problem: MainAxisSize.max already
  /// fills a loose bound along its own main axis).
  Widget _buildSessionBody(
    BuildContext context,
    AsyncSnapshot<List<SpeciesWithLocalImages>> snapshot,
  ) {
    _flashCards = snapshot.data ?? [];
    if (_flashCards.isNotEmpty &&
        _previews.isEmpty &&
        _effectiveReviewMode == ReviewMode.flip) {
      _loadPreviews();
    }

    final cardArea = _flashCards.isEmpty
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
                          context.loc.flashcardImagesDownloading,
                          key: const Key('images_downloading_empty_state_text'),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  : Text(
                      context.loc.commonNoFlashcardsAvailable,
                      key: const Key('no_flashcards_empty_state_text'),
                      textAlign: TextAlign.center,
                    ),
            ),
          )
        : FlashcardWidget(
            // A card can be re-appended to _flashCards for relearning as
            // the SAME object instance (deck_page.dart's
            // _gradeCurrentCard); keying by index (rather than relying on
            // FlashcardWidget's own object-equality check in
            // didUpdateWidget) guarantees a fresh state even when that
            // instance reappears at the very next position.
            // The value is spelled out rather than the bare index so a test
            // can wait for a specific card to be on screen: a bare int key
            // is indistinguishable from any other int-keyed widget.
            key: ValueKey('flashcard_$_currentFlashcardIndex'),
            speciesWithLocalImage: getCurrentFlashcard(),
            language: widget.deck.language,
            learningMode: _learningMode,
            nameType: _nameType,
            namesMayStillRefine: _pendingCommonNameSpeciesIds.contains(
              getCurrentFlashcard().species.id,
            ),
            reviewMode: _effectiveReviewMode,
            multipleChoiceOptions: _currentOptions,
            onMultipleChoiceAnswered: _onMultipleChoiceAnswered,
            onContinue: _onContinueTapped,
            onRemoveSpecies: _handleRemoveSpeciesFromCard,
            watchlistKey: _watchlistButtonKey,
            imageKey: _imageKey,
            optionsKey: _optionsKey,
            onFlipControllerReady: (controller) => _flipController = controller,
          );

    final showRatingButtons =
        _flashCards.isNotEmpty && _effectiveReviewMode == ReviewMode.flip;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    // Landscape moves the rating buttons into a vertical rail beside the
    // card instead of a row below it, so the card doesn't lose height to a
    // horizontal button strip (see FlashcardButtons.vertical). A bare Row
    // doesn't stretch to fill the available height on its own — its cross
    // axis just shrink-wraps to the tallest child — so the LayoutBuilder
    // here gives it an explicit, tight height to lay out against (Column
    // doesn't need this: MainAxisSize.max already fills a loose bound
    // along its own main/vertical axis).
    if (isLandscape) {
      return LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Row(
            children: [
              Expanded(child: cardArea),
              if (showRatingButtons)
                SizedBox(
                  width: 116,
                  child: FlipSwipeDetector(
                    controller: _railFlipController,
                    child: FlashcardButtons(
                      vertical: true,
                      onAgain: () => _onGrade(ReviewGrade.again),
                      onHard: () => _onGrade(ReviewGrade.hard),
                      onGood: () => _onGrade(ReviewGrade.good),
                      onEasy: () => _onGrade(ReviewGrade.easy),
                      againKey: _againKey,
                      hardKey: _hardKey,
                      goodKey: _goodKey,
                      easyKey: _easyKey,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(child: cardArea),
        if (showRatingButtons) ...[
          AppSpacing.heightS24,
          FlipSwipeDetector(
            controller: _railFlipController,
            child: FlashcardButtons(
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
          ),
        ],
      ],
    );
  }

  void _showMoreNewFlashcardsAvailable(BuildContext context) {
    showDialog(
      context: context,
      // The dialog cannot be dismissed while the next batch is being
      // written: leaving it open is what tells the user the tap was heard.
      barrierDismissible: false,
      builder: (context) => ActivateMoreCardsDialog(
        onActivate: () => _sessionService.initializeNextBatch(widget.deck.id!),
        onActivated: () {
          if (mounted) _initializeFlashcards();
        },
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
    final prefs = Provider.of<UserPreferencesService>(context, listen: false);
    final isMultipleChoice = _effectiveReviewMode == ReviewMode.multipleChoice;
    // Multiple-choice gets its own coach marks (targeting the option picker
    // instead of the FSRS rating buttons), tracked by a separate "seen" flag
    // — a user who already dismissed the flip-mode tour hasn't necessarily
    // seen this one, e.g. after switching an existing deck's review mode.
    if (isMultipleChoice) {
      if (prefs.hasSeenFlashcardTutorialMultipleChoice) return;
      prefs.hasSeenFlashcardTutorialMultipleChoice = true;
    } else {
      if (prefs.hasSeenFlashcardTutorial) return;
      prefs.hasSeenFlashcardTutorial = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        _showFlashcardTutorial();
      }
    });
  }

  void _showFlashcardTutorial() {
    FlashcardTutorial(
      learningMode: _learningMode,
      isMultipleChoice: _effectiveReviewMode == ReviewMode.multipleChoice,
      hasImage: getCurrentFlashcard().localPictures.isNotEmpty,
      imageKey: _imageKey,
      optionsKey: _optionsKey,
      againKey: _againKey,
      hardKey: _hardKey,
      goodKey: _goodKey,
      easyKey: _easyKey,
      watchlistButtonKey: _watchlistButtonKey,
    ).show(context);
  }
}

/// Landscape's stand-in for the AppBar's back button, floated over the
/// content — see [DeckPageState.build] for why landscape drops the AppBar
/// entirely instead of just its title.
class _FloatingBackButton extends StatelessWidget {
  const _FloatingBackButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}
