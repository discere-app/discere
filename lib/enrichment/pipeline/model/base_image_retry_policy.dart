import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/base_image_fallback_reason.dart';

/// How often, and how far apart, a species' reference image is attempted, and
/// when the species stops waiting for it and takes its pictures from
/// iNaturalist instead.
///
/// Two phases. The short one retries quickly, so a brief outage of the
/// reference-image host costs seconds rather than a day. When it runs out
/// the species falls back to iNaturalist — the user gets pictures now — and
/// the reference image is tried again in the long phase, once a day, until
/// it arrives or the budget is spent. An image the host does not have is
/// given up on at once instead: asking again returns the same answer.
///
/// The one place these numbers live: `BaseWorker` books failures by them,
/// the deck projection stops waiting on a row in the long phase, and the
/// maintenance repository leaves its retry time alone when a host cooldown
/// ends (the SQL form is `baseLongPhaseCondition` in
/// `enrichment_work_tables.dart`, derived from [shortPhaseAttempts]).
abstract final class BaseImageRetryPolicy {
  /// Attempts before the species falls back to iNaturalist.
  static const shortPhaseAttempts = 2;

  /// Attempts after the fallback, a day apart.
  static const longPhaseAttempts = 3;

  static const maxAttempts = shortPhaseAttempts + longPhaseAttempts;

  static const shortPhaseBackoff = Duration(seconds: 15);
  static const longPhaseBackoff = Duration(days: 1);

  /// The wait after each failed attempt, indexed by attempt count minus one
  /// and clamped to the last step, as the outcome repository reads it.
  static final backoffSteps = List<Duration>.unmodifiable([
    for (var attempt = 1; attempt < shortPhaseAttempts; attempt++)
      shortPhaseBackoff,
    longPhaseBackoff,
  ]);

  /// Whether a failure for [reason] is given up on at once rather than
  /// retried: only an image the host answered it does not have.
  static bool givesUpAtOnce(BaseImageFallbackReason reason) =>
      reason == BaseImageFallbackReason.imageMissing;

  /// How many failed attempts a row gets for [reason] before it becomes
  /// `permanentFailure`.
  static int attemptBudgetFor(BaseImageFallbackReason reason) =>
      givesUpAtOnce(reason) ? 1 : maxAttempts;

  /// Whether the failure that brought a row to [attemptCount] failed attempts
  /// is the one that sends the species to iNaturalist: the last short
  /// attempt, or giving up before reaching it. A failure in the long phase
  /// is not — the species fell back already.
  static bool fallsBackAt(int attemptCount, {required bool gaveUp}) =>
      attemptCount == shortPhaseAttempts ||
      (gaveUp && attemptCount < shortPhaseAttempts);

  /// Whether a `base` row in [state] after [attemptCount] failed attempts is
  /// in the long phase: still to be retried, but with the species already on
  /// its iNaturalist pictures.
  static bool isInLongPhase(EnrichmentWorkState state, int attemptCount) =>
      !state.isTerminal && attemptCount >= shortPhaseAttempts;
}
