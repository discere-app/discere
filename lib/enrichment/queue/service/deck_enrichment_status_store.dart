/// Everything the queue service knows about deck-level enrichment progress,
/// and the derivation of what the UI is told about it.
///
/// Rows are pulled in as deltas: a deck with no new activity never changes
/// again, so re-reading the full history on every checkpoint would only get
/// more expensive the longer the app runs. Changed rows are merged into the
/// maps rather than replacing them.
///
/// Deriving and committing are separate steps on purpose. The status is
/// derived first because the caller needs its cooldown flag before it can
/// decide the cooldown timestamp that the per-deck states are then built
/// from — and that flag is not simply the tracker's: with nothing pending,
/// the derivation returns [INatEnrichmentStatus.idle], which reports no
/// cooldown whatever the tracker says.
library;

import 'dart:async';

import 'package:discere/enrichment/model/deck_enrichment_projection.dart';
import 'package:discere/enrichment/pipeline/repository/deck_enrichment_projection_repository.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_info.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_state.dart';
import 'package:discere/enrichment/queue/model/enrichment_job.dart';
import 'package:discere/enrichment/queue/model/inat_enrichment_status.dart';
import 'package:discere/enrichment/queue/presentation/deck_enrichment_state_presenter.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/enrichment_progress_status.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:sqflite/sqflite.dart';

class DeckEnrichmentStatusStore {
  final EnrichmentJobRepository _jobRepository;
  final DeckEnrichmentProjectionRepository _projectionRepository;

  DeckEnrichmentStatusStore({
    required EnrichmentJobRepository jobRepository,
    required DeckEnrichmentProjectionRepository projectionRepository,
  }) : _jobRepository = jobRepository,
       _projectionRepository = projectionRepository;

  final Map<String, EnrichmentJobRecord> _jobsByDeckId =
      <String, EnrichmentJobRecord>{};
  final Map<String, DeckEnrichmentProjection> _projectionsByDeckId =
      <String, DeckEnrichmentProjection>{};
  final Map<String, DeckEnrichmentInfo> _deckInfoByDeckId =
      <String, DeckEnrichmentInfo>{};

  /// First-seen/first-completed timestamps for decks whose cover job never
  /// existed (no cover URL was ever scheduled for them) — the only signal
  /// [DeckEnrichmentInfo.lastAttemptedAt]/[lastCompletedAt] can fall back on
  /// in that case, since species/taxonomy work has no equivalent single
  /// "this deck's job" timestamp column anymore. Session-scoped by
  /// necessity (same trade-off the old code already made for permanent-
  /// failure tracking); a deck with a real cover job uses its durable
  /// `attemptedAt`/`completedAt` instead.
  final Map<String, DateTime> _sessionAttemptedAtByDeckId = {};
  final Map<String, DateTime> _sessionCompletedAtByDeckId = {};

  /// This instance's construction time — used only to decide whether a
  /// deck's (durable) [_resolveLastCompletedAt] value happened during the
  /// *current* app session, for [DeckEnrichmentInfo.sessionCompletedAt].
  /// Comparing against a real timestamp (rather than e.g. stamping
  /// `DateTime.now()` the first time a deck reads as done) is what makes
  /// this correct even on the very first refresh after a restart: a deck
  /// that was already fully enriched before this session started has a
  /// `completedAt` from before [_sessionStartedAt], so it's correctly
  /// treated as not-completed-this-session instead of appearing to have
  /// "just now" finished.
  final DateTime _sessionStartedAt = DateTime.now();

  /// High-water mark of `enrichment_jobs.updated_at` already merged into
  /// [_jobsByDeckId]. Starting at epoch means the first refresh naturally
  /// loads everything, same as the old unconditional full reload did.
  DateTime _jobsSyncedThrough = DateTime.fromMillisecondsSinceEpoch(0);

  /// Same high-water-mark pattern as [_jobsSyncedThrough], for the
  /// species/taxonomy/unresolved-name queue tables backing
  /// [_projectionsByDeckId]. Captured *before* each poll (not after) so a
  /// write landing mid-poll is never silently skipped — it just gets
  /// re-checked, harmlessly, on the next cycle.
  DateTime _workSyncedThrough = DateTime.fromMillisecondsSinceEpoch(0);

  INatEnrichmentStatus _status = INatEnrichmentStatus.idle;

  INatEnrichmentStatus get status => _status;

  /// Shared fallback for any deck not (yet) tracked. Carries no per-deck data,
  /// so a single memoized instance avoids reallocating it on every Consumer
  /// rebuild that queries an unknown deck.
  late final DeckEnrichmentInfo _hiddenDeckInfo = DeckEnrichmentInfo(
    // Derived the same way every other DeckEnrichmentInfo's status is
    // (_statusForState), rather than a separately hardcoded value that could
    // silently drift from what _statusForState maps `hidden` to.
    status: statusForDeckEnrichmentState(DeckEnrichmentState.hidden),
    state: DeckEnrichmentState.hidden,
    lastCompletedAt: null,
    lastAttemptedAt: null,
  );

  DeckEnrichmentInfo deckInfo(String deckId) =>
      _deckInfoByDeckId[deckId] ?? _hiddenDeckInfo;

  /// Drops everything remembered about a deck. A deletion never moves an
  /// `updated_at` forward, so the delta pull cannot see it — it has to be
  /// removed explicitly.
  void forget(String deckId) {
    _jobsByDeckId.remove(deckId);
    _projectionsByDeckId.remove(deckId);
    _deckInfoByDeckId.remove(deckId);
    _sessionAttemptedAtByDeckId.remove(deckId);
    _sessionCompletedAtByDeckId.remove(deckId);
  }

  /// Merges rows changed since the last pull. Returns false when the cycle
  /// was abandoned because the database went away underneath it, in which
  /// case nothing was committed and the cursors stay put.
  Future<bool> pullChanges() async {
    final List<EnrichmentJobRecord> changedJobs;
    final Set<String> changedWorkDeckIds;
    final DateTime workQueryStartedAt;
    try {
      changedJobs = await _jobRepository.loadJobsUpdatedSince(
        _jobsSyncedThrough,
      );
      workQueryStartedAt = DateTime.now();
      changedWorkDeckIds = await _projectionRepository.loadDeckIdsUpdatedSince(
        _workSyncedThrough.millisecondsSinceEpoch,
      );
    } on DatabaseException {
      // The user DB was closed mid-flight (app shutdown, or a test's
      // teardown deleting it out from under a still-running refresh).
      return false;
    } on TimeoutException {
      // The open itself timed out (DatabaseHelper._openTimeout, guarding a
      // wedged native handle) rather than an already-open DB being closed —
      // same "nothing to sync against" outcome, different failure point.
      return false;
    }

    for (final job in changedJobs) {
      _jobsByDeckId[job.deckId] = job;
      if (job.updatedAt.isAfter(_jobsSyncedThrough)) {
        _jobsSyncedThrough = job.updatedAt;
      }
    }
    final currentReferenceDbVersion =
        await ReferenceDatabaseProvisioner.currentVersion();
    for (final deckId in changedWorkDeckIds) {
      try {
        _projectionsByDeckId[deckId] = await _projectionRepository.loadDeckProjection(
          deckId,
          currentReferenceDbVersion: currentReferenceDbVersion,
        );
      } on DatabaseException {
        return false;
      } on TimeoutException {
        return false;
      }
    }
    // The work cursor advances only once every changed deck's projection has
    // actually been reloaded. It was captured before the delta query, so a
    // write landing mid-poll is re-checked next cycle rather than skipped;
    // and if a reload above bailed out, the cursor stays put so the next
    // poll retries those decks instead of stranding them below it.
    _workSyncedThrough = workQueryStartedAt;
    return true;
  }

  List<DeckWorkSnapshot> snapshots() {
    final allDeckIds = {..._jobsByDeckId.keys, ..._projectionsByDeckId.keys};
    return [for (final deckId in allDeckIds) _snapshotFor(deckId)];
  }

  INatEnrichmentStatus deriveStatus(
    List<DeckWorkSnapshot> snapshots, {
    required bool hasActiveHostCooldown,
    required bool preferBackgroundMessaging,
  }) => deriveEnrichmentStatus(
    snapshots,
    hasActiveHostCooldown: hasActiveHostCooldown,
    preferBackgroundMessaging: preferBackgroundMessaging,
  );

  /// Adopts [status] and the per-deck states derived from [snapshots].
  /// Returns whether any of it differs from what the UI was last told.
  bool commit(
    List<DeckWorkSnapshot> snapshots,
    INatEnrichmentStatus status, {
    required bool hasActiveHostCooldown,
    required DateTime? cooldownActiveSince,
    required Duration cooldownDisplayThreshold,
    required Duration pauseDisplayThreshold,
  }) {
    final nextDeckInfoByDeckId = _deriveDeckInfoByDeckId(
      snapshots,
      hasActiveHostCooldown: hasActiveHostCooldown,
      cooldownActiveSince: cooldownActiveSince,
      cooldownDisplayThreshold: cooldownDisplayThreshold,
      pauseDisplayThreshold: pauseDisplayThreshold,
    );
    final hasVisibleChange =
        status != _status ||
        !_deckInfoMapEquals(_deckInfoByDeckId, nextDeckInfoByDeckId);

    _status = status;
    _deckInfoByDeckId
      ..clear()
      ..addAll(nextDeckInfoByDeckId);
    return hasVisibleChange;
  }

  DeckWorkSnapshot _snapshotFor(String deckId) {
    return DeckWorkSnapshot(
      deckId: deckId,
      coverJob: _jobsByDeckId[deckId],
      projection:
          _projectionsByDeckId[deckId] ??
          DeckEnrichmentProjection.empty(deckId),
    );
  }
  Map<String, DeckEnrichmentInfo> _deriveDeckInfoByDeckId(
    Iterable<DeckWorkSnapshot> snapshots, {
    required bool hasActiveHostCooldown,
    required DateTime? cooldownActiveSince,
    required Duration cooldownDisplayThreshold,
    required Duration pauseDisplayThreshold,
  }) {
    return {
      for (final snapshot in snapshots)
        snapshot.deckId: _buildDeckInfo(
          snapshot,
          hasActiveHostCooldown: hasActiveHostCooldown,
          cooldownActiveSince: cooldownActiveSince,
          cooldownDisplayThreshold: cooldownDisplayThreshold,
          pauseDisplayThreshold: pauseDisplayThreshold,
        ),
    };
  }
  DeckEnrichmentInfo _buildDeckInfo(
    DeckWorkSnapshot snapshot, {
    required bool hasActiveHostCooldown,
    required DateTime? cooldownActiveSince,
    required Duration cooldownDisplayThreshold,
    required Duration pauseDisplayThreshold,
  }) {
    final state = computeDeckEnrichmentState(
      coverJob: snapshot.coverJob,
      projection: snapshot.projection,
      hasActiveHostCooldown: hasActiveHostCooldown,
      cooldownActiveSince: cooldownActiveSince,
      cooldownDisplayThreshold: cooldownDisplayThreshold,
      pauseDisplayThreshold: pauseDisplayThreshold,
    );
    final progress = deriveDisplayedProgress(snapshot);
    return DeckEnrichmentInfo(
      status: statusForDeckEnrichmentState(state),
      state: state,
      lastCompletedAt: _resolveLastCompletedAt(snapshot, state),
      lastAttemptedAt: _resolveLastAttemptedAt(snapshot, state),
      sessionCompletedAt: _resolveSessionCompletedAt(snapshot, state),
      includesINatPhotos: snapshot.projection.wantsInatPhotosSpeciesCount > 0,
      includesCommonNames: snapshot.projection.wantsCommonNamesSpeciesCount > 0,
      progressCompleted: progress.completed,
      progressTotal: progress.total,
      isReady: isReadyForDeck(snapshot.projection),
      hasActiveHostCooldown: hasActiveHostCooldown,
      imageStagesComplete: snapshot.projection.imageStagesComplete,
      staleBaseSpeciesCount: snapshot.projection.staleBaseSpeciesCount,
    );
  }
  DateTime? _resolveLastAttemptedAt(
    DeckWorkSnapshot snapshot,
    DeckEnrichmentState state,
  ) {
    final coverAttemptedAt = snapshot.coverJob?.attemptedAt;
    if (coverAttemptedAt != null) return coverAttemptedAt;
    if (state == DeckEnrichmentState.hidden) return null;
    return _sessionAttemptedAtByDeckId.putIfAbsent(
      snapshot.deckId,
      () => DateTime.now(),
    );
  }
  DateTime? _resolveLastCompletedAt(
    DeckWorkSnapshot snapshot,
    DeckEnrichmentState state,
  ) {
    final coverCompletedAt = snapshot.coverJob?.completedAt;
    if (coverCompletedAt != null) return coverCompletedAt;
    if (state == DeckEnrichmentState.done ||
        state == DeckEnrichmentState.doneWithGaps) {
      return _sessionCompletedAtByDeckId.putIfAbsent(
        snapshot.deckId,
        () => DateTime.now(),
      );
    }
    return _sessionCompletedAtByDeckId[snapshot.deckId];
  }
  DateTime? _resolveSessionCompletedAt(
    DeckWorkSnapshot snapshot,
    DeckEnrichmentState state,
  ) {
    final completedAt = _resolveLastCompletedAt(snapshot, state);
    if (completedAt == null) return null;
    return completedAt.isAfter(_sessionStartedAt) ? completedAt : null;
  }
  bool _deckInfoMapEquals(
    Map<String, DeckEnrichmentInfo> current,
    Map<String, DeckEnrichmentInfo> next,
  ) {
    if (identical(current, next)) return true;
    if (current.length != next.length) return false;
    for (final entry in current.entries) {
      if (next[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
