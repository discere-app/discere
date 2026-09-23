import 'dart:async';

import 'package:discere/enrichment/queue/model/deck_enrichment_info.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_state.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/decks/deck_download_choice_dialog.dart';
import 'package:discere/learning/flashcard/activate_more_cards_dialog.dart';
import 'package:discere/learning/flashcard/deck_session_presenter.dart';
import 'package:discere/learning/flashcard/flashcard_tutorial.dart';
import 'package:discere/learning/flashcard/flashcard_widget.dart';
import 'package:discere/learning/flashcard/flip_swipe_detector.dart';
import 'package:discere/learning/flashcard/no_data_downloaded_dialog.dart';
import 'package:discere/learning/flashcard/no_more_cards_dialog.dart';
import 'package:discere/learning/flashcard/no_photo_gaps_dialog.dart';
import 'package:discere/learning/flashcard/review_image_availability_coordinator.dart';
import 'package:discere/learning/flashcard/review_layout.dart';
import 'package:discere/learning/flashcard/review_session_controller.dart';
import 'package:discere/learning/flashcard/service/deck_session_service.dart';
import 'package:discere/learning/flashcard/service/fsrs_service.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/review_mode.dart';
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
  static const DeckSessionPresenter _sessionPresenter = DeckSessionPresenter();

  late final FlashcardService _flashcardService;
  late final INatEnrichmentQueueService _enrichmentQueueService;
  late final DeckSessionService _sessionService;
  late final ReviewSessionController _session;
  late final ReviewImageAvailabilityCoordinator _imageAvailability;
  late DeckEnrichmentInfo _lastEnrichmentInfo;

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
    _session = ReviewSessionController(
      deck: widget.deck,
      flashcardService: _flashcardService,
      sessionService: _sessionService,
    );
    _imageAvailability = ReviewImageAvailabilityCoordinator(
      sessionService: _sessionService,
      session: _session,
    );
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
    _startSession();
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
    _session.dispose();
    super.dispose();
  }

  void _startSession() => unawaited(_loadSession());

  /// Loads (or reloads) the session and does whatever its outcome calls for:
  /// start the first card, fetch an image for a session that has none, or
  /// deal with a deck that has nothing due.
  Future<void> _loadSession() async {
    _imageAvailability.forgetAttempts();
    await _session.load();
    if (!mounted) return;

    unawaited(_maybeCheckPhotoGaps());

    if (_session.hasCards) {
      unawaited(_imageAvailability.ensureImageForCurrentCard());
      _loadPreviewsIfFlipMode();
      _maybeShowFlashcardTutorial();
      return;
    }
    if (_session.isWaitingForImages) {
      unawaited(_fetchImageForHeldBackCards());
      return;
    }
    await _handleDeckWithNothingDue();
  }

  Future<void> _fetchImageForHeldBackCards() async {
    final outcome = await _imageAvailability.ensureAnyImageAvailable();
    if (!mounted) return;
    switch (outcome) {
      case AwaitingImageOutcome.imageFound:
        _startSession();
      case AwaitingImageOutcome.shownWithoutImages:
        _loadPreviewsIfFlipMode();
        _maybeShowFlashcardTutorial();
      case AwaitingImageOutcome.none:
        break;
    }
  }

  Future<void> _handleDeckWithNothingDue() async {
    final deckStat = await _flashcardService.getDeckStat(widget.deck.id!);
    if (!mounted) return;
    switch (_sessionPresenter.decideNewCardsAction(deckStat)) {
      case NewCardsAction.none:
        break;
      case NewCardsAction.autoInitialize:
        unawaited(
          _sessionService.initializeNextBatch(widget.deck.id!).then((_) {
            if (mounted) _startSession();
          }),
        );
      case NewCardsAction.promptUser:
        _showMoreNewFlashcardsAvailable(context);
    }
  }

  /// Interval previews sit under the rating buttons, which only flip mode
  /// shows — multiple choice has no use for them.
  void _loadPreviewsIfFlipMode() {
    if (_session.effectiveReviewMode != ReviewMode.flip) return;
    unawaited(_session.loadPreviews());
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
    _startSession();
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
              displayName: _session.primaryNameFor(card.species),
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
          _startSession();
        }
      case NoPhotoGapsAction.skip:
        return;
    }
  }

  Future<void> _handleRemoveSpeciesFromCard(String speciesId) async {
    await _session.removeSpecies(speciesId);
    if (!mounted || !_session.hasCards) return;
    unawaited(_imageAvailability.ensureImageForCurrentCard());
    _loadPreviewsIfFlipMode();
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
      speciesId: _session.currentCard.species.id,
      deckId: widget.deck.id!,
      grade: grade,
    );

    // Cards still in learning/relearning get re-added to the queue
    if (result.shouldRequeue) {
      _session.requeueCurrentCard();
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
    if (!_session.isOnLastCard) {
      _session.advance();
      unawaited(_imageAvailability.ensureImageForCurrentCard());
      _loadPreviewsIfFlipMode();
      return;
    }

    final deckStat = await _flashcardService.getDeckStat(widget.deck.id!);
    if (!mounted) return;

    if (deckStat.uninitializedCount > 0) {
      _showMoreNewFlashcardsAvailable(context);
      return;
    }
    await showNoMoreCardsDialog(context);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final content = ListenableBuilder(
      listenable: _session,
      builder: (context, _) => switch (_session.status) {
        ReviewSessionStatus.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        ReviewSessionStatus.failed => Center(
          child: Text(
            '${context.loc.error}: ${context.loc.describeError(_session.error)}',
          ),
        ),
        ReviewSessionStatus.ready => _buildSessionBody(context),
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

  Widget _buildSessionBody(BuildContext context) {
    return ReviewLayout(
      cardArea: _session.hasCards
          ? _buildCard()
          : _EmptySessionState(isWaitingForImages: _session.isWaitingForImages),
      showRatingButtons:
          _session.hasCards && _session.effectiveReviewMode == ReviewMode.flip,
      flipController: _railFlipController,
      previews: _session.previews,
      onGrade: _onGrade,
      againKey: _againKey,
      hardKey: _hardKey,
      goodKey: _goodKey,
      easyKey: _easyKey,
    );
  }

  Widget _buildCard() {
    final card = _session.currentCard;
    return FlashcardWidget(
      // A card can be re-appended to the session for relearning as the SAME
      // object instance (see ReviewSessionController.requeueCurrentCard);
      // keying by index (rather than relying on FlashcardWidget's own
      // object-equality check in didUpdateWidget) guarantees a fresh state
      // even when that instance reappears at the very next position.
      // The index is spelled into the value so that a test can name the card
      // it is waiting for. Keying by the bare int would work identically
      // here — this is purely so the key reads as what it identifies at both
      // ends.
      key: ValueKey('flashcard_${_session.currentIndex}'),
      speciesWithLocalImage: card,
      language: widget.deck.language,
      learningMode: _session.learningMode,
      nameType: _session.nameType,
      namesMayStillRefine: _session.namesMayStillRefine(card.species),
      reviewMode: _session.effectiveReviewMode,
      multipleChoiceOptions: _session.options,
      onMultipleChoiceAnswered: _onMultipleChoiceAnswered,
      onContinue: _onContinueTapped,
      onRemoveSpecies: _handleRemoveSpeciesFromCard,
      watchlistKey: _watchlistButtonKey,
      imageKey: _imageKey,
      optionsKey: _optionsKey,
      onFlipControllerReady: (controller) => _flipController = controller,
    );
  }

  void _showMoreNewFlashcardsAvailable(BuildContext context) {
    showDialog(
      context: context,
      // A tap outside never dismisses this dialog: while the batch is being
      // written, the dialog staying up is what tells the user the tap was
      // heard, and before that there is nothing to dismiss it for. The
      // Android back gesture still closes it — the batch then finishes and
      // the deck refreshes anyway.
      barrierDismissible: false,
      builder: (context) => ActivateMoreCardsDialog(
        onActivate: () => _sessionService.initializeNextBatch(widget.deck.id!),
        onActivated: () {
          if (mounted) _startSession();
        },
      ),
    );
  }

  void _maybeShowFlashcardTutorial() {
    final prefs = Provider.of<UserPreferencesService>(context, listen: false);
    final isMultipleChoice =
        _session.effectiveReviewMode == ReviewMode.multipleChoice;
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
      learningMode: _session.learningMode,
      isMultipleChoice:
          _session.effectiveReviewMode == ReviewMode.multipleChoice,
      hasImage: _session.currentCard.localPictures.isNotEmpty,
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

/// What a session shows instead of a card: a spinner while images for the
/// due cards are still being fetched, and otherwise the plain "nothing to
/// review" message.
class _EmptySessionState extends StatelessWidget {
  final bool isWaitingForImages;

  const _EmptySessionState({required this.isWaitingForImages});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.emptyStatePaddingAll,
      child: Center(
        child: isWaitingForImages
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
    );
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
