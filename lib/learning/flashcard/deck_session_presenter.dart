import 'package:discere/enrichment/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/flashcard_stat.dart';

/// Pure derived-state helpers for DeckPageState (the flashcard review
/// session), kept free of BuildContext/widget state so they can be unit
/// tested directly, mirroring the presenter pattern used elsewhere.
class DeckSessionPresenter {
  const DeckSessionPresenter();

  /// The review mode actually used for the current card. Falls back to flip
  /// for just this card when multiple choice is selected but [hasOptions]
  /// is false (this card's name pool didn't yield enough distinct
  /// distractors) — other cards in the session are unaffected.
  ReviewMode effectiveReviewMode({
    required ReviewMode reviewMode,
    required bool hasOptions,
  }) {
    if (reviewMode == ReviewMode.multipleChoice && hasOptions) {
      return ReviewMode.multipleChoice;
    }
    return ReviewMode.flip;
  }

  /// Cards still in short-term learning/relearning steps get re-added to
  /// the review queue instead of being done for the session.
  bool shouldRequeue(CardState cardState) =>
      cardState == CardState.learning || cardState == CardState.relearning;

  /// Whether the flashcard list should be reloaded after the enrichment
  /// queue's state for this deck changes: either a new completion just
  /// landed, or a previously-active job just stopped (finished, cancelled,
  /// or paused) — both mean fresher images/names might now be available.
  bool shouldRefreshAfterEnrichmentChange({
    required DeckEnrichmentInfo previous,
    required DeckEnrichmentInfo next,
  }) {
    if (next.isActive) return false;
    final hasNewCompletion =
        next.lastCompletedAt != null &&
        next.lastCompletedAt != previous.lastCompletedAt;
    return hasNewCompletion || previous.isActive;
  }
}
