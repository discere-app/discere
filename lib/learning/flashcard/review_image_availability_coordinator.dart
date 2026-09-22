import 'package:discere/learning/flashcard/review_session_controller.dart';
import 'package:discere/learning/flashcard/service/deck_session_service.dart';

/// How an attempt to get *any* image for a session full of held-back cards
/// ended.
enum AwaitingImageOutcome {
  /// One species gained an image — the session has to be reloaded so its
  /// card can appear.
  imageFound,

  /// No attempt succeeded; the held-back cards are now shown without
  /// images.
  shownWithoutImages,

  /// Nothing to attempt, or an attempt was already running.
  none,
}

/// Fetches species images on demand for a running review session.
///
/// Separate from [ReviewSessionController] because the two only meet at
/// "replace card n": the session decides which card is showing, this decides
/// whether an image for it is worth asking for, remembers which species have
/// already been asked about, and keeps the fetches serial so a card advance
/// never races an in-flight download.
class ReviewImageAvailabilityCoordinator {
  /// How many species to try before showing the held-back cards without
  /// images.
  ///
  /// Bounded to avoid a long serial stall (e.g. offline) on decks with many
  /// species. The background enrichment queue — paused for the duration of
  /// this session by interactive priority mode — fills in the rest once the
  /// session ends. Its own give-up mechanism can't help while it is paused,
  /// which is why the spinner has to end here.
  static const _maxAwaitingImageFetchAttempts = 10;

  final DeckSessionService _sessionService;
  final ReviewSessionController _session;

  ReviewImageAvailabilityCoordinator({
    required DeckSessionService sessionService,
    required ReviewSessionController session,
  }) : _sessionService = sessionService,
       _session = session;

  /// Species already asked about in this session. One attempt each: a
  /// species the on-demand fetch couldn't resolve won't resolve on the next
  /// card advance either.
  final Set<String> _attemptedSpeciesIds = <String>{};

  bool _isFetchInFlight = false;

  /// Forgets which species have been attempted, for a session that is being
  /// loaded from scratch.
  void forgetAttempts() => _attemptedSpeciesIds.clear();

  /// Fetches an image for the card currently on screen, if it has none.
  ///
  /// Re-checks afterwards rather than returning: by the time a download
  /// finishes the user may have moved on, and the card now showing is the
  /// one whose image matters.
  Future<void> ensureImageForCurrentCard() async {
    if (_isFetchInFlight || !_session.hasCards) return;

    final card = _session.currentCard;
    if (card.localPictures.isNotEmpty) return;

    final speciesId = card.species.id;
    if (!_attemptedSpeciesIds.add(speciesId)) return;

    _isFetchInFlight = true;
    try {
      final updated = await _sessionService.ensureSingleImageForSpecies(
        speciesId,
      );
      if (_session.isDisposed) return;
      if (updated != null) _session.replaceCard(updated);
    } finally {
      _isFetchInFlight = false;
    }
    if (_session.isDisposed) return;
    await ensureImageForCurrentCard();
  }

  /// Every due card is held back because none of them has an image yet.
  /// Fetches one species at a time until one succeeds.
  Future<AwaitingImageOutcome> ensureAnyImageAvailable() async {
    if (_isFetchInFlight) return AwaitingImageOutcome.none;

    final candidates = _session.awaitingImageCards.take(
      _maxAwaitingImageFetchAttempts,
    );
    for (final card in candidates) {
      if (_session.isDisposed) return AwaitingImageOutcome.none;
      final speciesId = card.species.id;
      if (!_attemptedSpeciesIds.add(speciesId)) continue;

      _isFetchInFlight = true;
      try {
        final updated = await _sessionService.ensureSingleImageForSpecies(
          speciesId,
        );
        if (_session.isDisposed) return AwaitingImageOutcome.none;
        if (updated != null && updated.localPictures.isNotEmpty) {
          return AwaitingImageOutcome.imageFound;
        }
      } finally {
        _isFetchInFlight = false;
      }
    }

    if (_session.isDisposed || _session.awaitingImageCards.isEmpty) {
      return AwaitingImageOutcome.none;
    }
    _session.showAwaitingCardsWithoutImages();
    return AwaitingImageOutcome.shownWithoutImages;
  }
}
