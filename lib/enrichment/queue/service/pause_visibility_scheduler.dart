import 'dart:async';

import 'package:discere/enrichment/queue/presentation/deck_enrichment_state_presenter.dart';
import 'package:discere/enrichment/queue/service/enrichment_progress_status.dart';

/// Holds a pause or a host cooldown back from the UI until it has lasted long
/// enough to be worth showing, and wakes the UI at the moment it becomes
/// showable.
///
/// The thresholds themselves ([cooldownVisibleAfter], [pauseVisibleAfter])
/// are compared by `computeDeckEnrichmentState`; what this adds is the part
/// that comparison cannot do on its own. A deck state is only recomputed when
/// something changes, and time passing is not a change — without a timer, a
/// cooldown that crosses the 30-second mark while nothing else happens would
/// stay invisible until the next unrelated refresh.
///
/// So the scheduler answers two things: since when has the current cooldown
/// been active (the comparison needs it), and when is the next moment at
/// which a recompute would produce a different answer.
class PauseVisibilityScheduler {
  /// Asked to recompute, because a pause or cooldown has just crossed its
  /// threshold. Called at most once per timer.
  final void Function() _onBecameVisible;

  DateTime? _cooldownActiveSince;
  Timer? _cooldownTimer;
  final Map<String, Timer> _deckPauseTimers = <String, Timer>{};
  bool _disposed = false;

  PauseVisibilityScheduler({required void Function() onBecameVisible})
    : _onBecameVisible = onBecameVisible;

  /// Wall-clock time at which the host cooldown last went from inactive to
  /// active, or null when none is active.
  DateTime? get cooldownActiveSince => _cooldownActiveSince;

  /// Follows the *derived* cooldown flag, not the tracker's: with nothing
  /// pending the derivation reports no cooldown at all, and the per-deck
  /// states have to agree with what the status says.
  void syncCooldown(bool hasActiveHostCooldown) {
    if (_disposed) return;
    final wasActive = _cooldownActiveSince != null;
    if (hasActiveHostCooldown && !wasActive) {
      _cooldownActiveSince = DateTime.now();
      _scheduleCooldownWakeup();
    } else if (!hasActiveHostCooldown && wasActive) {
      _cooldownActiveSince = null;
      _cooldownTimer?.cancel();
      _cooldownTimer = null;
    }
  }

  /// One timer per deck whose retry is still far enough out that it does not
  /// yet read as paused, firing when it starts to.
  ///
  /// Decks that no longer need one lose it here rather than when their timer
  /// fires — a deck that resumed, was cancelled or had its retry pulled
  /// forward would otherwise keep a timer alive for a state it left.
  void syncDeckPauses(Iterable<DeckWorkSnapshot> snapshots) {
    if (_disposed) return;
    final now = DateTime.now();
    final stillWanted = <String>{};

    for (final snapshot in snapshots) {
      final nextAttemptAt = earliestDeckRetryAt(
        snapshot.coverJob,
        snapshot.projection,
      );
      if (nextAttemptAt == null) continue;
      final untilRetry = nextAttemptAt.difference(now);
      if (untilRetry <= pauseVisibleAfter) continue;

      stillWanted.add(snapshot.deckId);
      if (_deckPauseTimers.containsKey(snapshot.deckId)) continue;
      _deckPauseTimers[snapshot.deckId] = Timer(
        untilRetry - pauseVisibleAfter,
        () {
          _deckPauseTimers.remove(snapshot.deckId);
          _fire();
        },
      );
    }

    for (final deckId in _deckPauseTimers.keys.toList(growable: false)) {
      if (stillWanted.contains(deckId)) continue;
      _deckPauseTimers.remove(deckId)?.cancel();
    }
  }

  void dispose() {
    _disposed = true;
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    for (final timer in _deckPauseTimers.values) {
      timer.cancel();
    }
    _deckPauseTimers.clear();
  }

  void _scheduleCooldownWakeup() {
    _cooldownTimer?.cancel();
    final startedAt = _cooldownActiveSince;
    if (startedAt == null) return;
    final remaining =
        cooldownVisibleAfter - DateTime.now().difference(startedAt);
    // Already past the threshold: the next recompute will show it anyway,
    // and a zero-delay timer would only fire a redundant one.
    if (remaining <= Duration.zero) return;
    _cooldownTimer = Timer(remaining, () {
      _cooldownTimer = null;
      _fire();
    });
  }

  void _fire() {
    if (_disposed) return;
    _onBecameVisible();
  }
}
