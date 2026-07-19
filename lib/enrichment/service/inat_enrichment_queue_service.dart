import 'dart:async';
import 'dart:ui';

import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/enrichment/model/deck_enrichment_state.dart';
import 'package:discere/enrichment/presentation/enrichment_status_presenter.dart';
import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/service/enrichment_background_scheduler.dart';
import 'package:discere/enrichment/service/enrichment_foreground_service_keeper.dart';
import 'package:discere/enrichment/service/enrichment_job_executor.dart';
import 'package:discere/enrichment/service/enrichment_job_ports.dart';
import 'package:discere/enrichment/service/enrichment_progress_status.dart';
import 'package:discere/enrichment/service/enrichment_service.dart';
import 'package:discere/enrichment/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/enrichment/util/ordered_unique_strings.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

export 'package:discere/enrichment/model/deck_enrichment_state.dart';

export 'enrichment_progress_status.dart';

/// UI-facing snapshot of a deck's enrichment job. Deliberately limited to
/// what the deck-card hint and the edit-deck section actually render —
/// internals like error text, retry timing, or session failure flags stay
/// inside the service and only surface through the derived [state].
class DeckEnrichmentInfo {
  final EnrichmentJobStatus status;
  final DeckEnrichmentState state;
  final DateTime? lastCompletedAt;
  final DateTime? lastAttemptedAt;
  final INatEnrichmentPhase? currentPhase;
  final bool includesINatPhotos;
  final bool includesCommonNames;
  final int progressCompleted;
  final int progressTotal;
  final bool isReady;
  final bool hasActiveHostCooldown;

  /// True once every species in the deck has reached a terminal state
  /// (downloaded image or explicit no-result marker) for both image-loading
  /// stages — i.e. [EnrichmentJobRecord.everySpeciesHasImage]. Defaults to
  /// true for the "no job known yet" fallback instance, since there is
  /// nothing to wait for in that case.
  final bool imageStagesComplete;

  const DeckEnrichmentInfo({
    required this.status,
    this.state = DeckEnrichmentState.hidden,
    required this.lastCompletedAt,
    required this.lastAttemptedAt,
    this.currentPhase,
    this.includesINatPhotos = false,
    this.includesCommonNames = false,
    this.progressCompleted = 0,
    this.progressTotal = 0,
    this.isReady = false,
    this.hasActiveHostCooldown = false,
    this.imageStagesComplete = true,
  });

  bool get includesINatEnrichment => includesINatPhotos || includesCommonNames;

  bool get hasCompletedINatEnrichment =>
      includesINatEnrichment && lastCompletedAt != null;

  bool get isActive =>
      status == EnrichmentJobStatus.runningForeground ||
      status == EnrichmentJobStatus.runningBackground;

  bool get hasPendingWork => switch (status) {
    EnrichmentJobStatus.queued ||
    EnrichmentJobStatus.runningForeground ||
    EnrichmentJobStatus.runningBackground ||
    EnrichmentJobStatus.pausedBySystem ||
    EnrichmentJobStatus.retryScheduled ||
    EnrichmentJobStatus.failedTemporary => true,
    _ => false,
  };

  bool get hasFailedAttempt =>
      status == EnrichmentJobStatus.failedTemporary ||
      status == EnrichmentJobStatus.failedPermanent;

  @override
  bool operator ==(Object other) {
    return other is DeckEnrichmentInfo &&
        other.status == status &&
        other.state == state &&
        other.lastCompletedAt == lastCompletedAt &&
        other.lastAttemptedAt == lastAttemptedAt &&
        other.currentPhase == currentPhase &&
        other.includesINatPhotos == includesINatPhotos &&
        other.includesCommonNames == includesCommonNames &&
        other.progressCompleted == progressCompleted &&
        other.progressTotal == progressTotal &&
        other.isReady == isReady &&
        other.hasActiveHostCooldown == hasActiveHostCooldown &&
        other.imageStagesComplete == imageStagesComplete;
  }

  @override
  int get hashCode => Object.hash(
    status,
    state,
    lastCompletedAt,
    lastAttemptedAt,
    currentPhase,
    includesINatPhotos,
    includesCommonNames,
    progressCompleted,
    progressTotal,
    isReady,
    hasActiveHostCooldown,
    imageStagesComplete,
  );
}

class INatEnrichmentQueueService extends ChangeNotifier {
  static final _log = Logger.forType(INatEnrichmentQueueService);
  final EnrichmentJobRepository _jobRepository;
  final EnrichmentWorkRepository _workRepository;
  late final EnrichmentJobExecutor _executor;
  final EnrichmentBackgroundScheduler _backgroundScheduler;
  final EnrichmentForegroundServiceKeeper _foregroundServiceKeeper;
  final NetworkAvailability _networkAvailability;
  final DeckSpeciesSnapshotPort _deckSpeciesSnapshotPort;
  final AllDeckIdsPort? _allDeckIdsPort;
  final HostCooldownTracker _hostCooldownTracker;
  final String _foregroundOwner;
  final bool _processJobs;

  final Map<String, EnrichmentJobRecord> _jobsByDeckId =
      <String, EnrichmentJobRecord>{};
  final Map<String, DeckEnrichmentInfo> _deckInfoByDeckId =
      <String, DeckEnrichmentInfo>{};
  final Set<String> _sessionFailedDeckIds = {};

  /// High-water mark of `enrichment_jobs.updated_at` already merged into
  /// [_jobsByDeckId]. Starting at epoch means the first refresh naturally
  /// loads everything, same as the old unconditional full reload did.
  DateTime _jobsSyncedThrough = DateTime.fromMillisecondsSinceEpoch(0);

  INatEnrichmentStatus _status = INatEnrichmentStatus.idle;
  Future<void>? _foregroundRunner;
  Future<void>? _initializationFuture;
  Future<void>? _refreshStateFuture;
  Future<void> _lifecycleTransition = Future.value();
  _QueueLifecycleObserver? _lifecycleObserver;
  StreamSubscription<bool>? _networkSubscription;
  bool _isInForeground = true;
  bool _targetForeground = true;
  int _interactiveHoldCount = 0;
  bool _restartForegroundRunnerWhenIdle = false;
  bool _refreshStateQueued = false;
  bool _disposed = false;
  bool _keeperWanted = false;

  /// Wall-clock time at which the host cooldown last transitioned from
  /// inactive to active. `null` when no cooldown is active. Used to surface
  /// [DeckEnrichmentState.cooldown] only once the cooldown has lasted longer
  /// than the display threshold.
  DateTime? _cooldownActiveSince;
  Timer? _cooldownDisplayTimer;
  final Map<String, Timer> _pauseDisplayTimers = <String, Timer>{};

  static const Duration cooldownDisplayThreshold = Duration(seconds: 30);
  static const Duration pauseDisplayThreshold = Duration(minutes: 2);

  INatEnrichmentQueueService(
    EnrichmentService enrichmentService, {
    required TaxonomyCommonNameEnrichmentService taxonomyEnrichmentService,
    required DeckSpeciesSnapshotPort deckSpeciesSnapshotPort,
    required DeckCoverStorePort deckCoverStore,
    required ImageService imageService,
    ScientificNameResolutionPort? nameResolutionPort,
    DeckSpeciesMutationPort? deckSpeciesMutationPort,
    UnresolvedNamesObserverPort? unresolvedNamesObserver,
    AllDeckIdsPort? allDeckIdsPort,
    required EnrichmentJobRepository jobRepository,
    required EnrichmentWorkRepository workRepository,
    required HostCooldownTracker hostCooldownTracker,
    required LocalDiagnostics diagnostics,
    // Null-object defaults: platform integrations that legitimately do
    // nothing in tests. Real implementations are wired in the bootstrap.
    EnrichmentBackgroundScheduler? backgroundScheduler,
    EnrichmentForegroundServiceKeeper? foregroundServiceKeeper,
    NetworkAvailability? networkAvailability,
    bool autoInitialize = true,
    bool processJobs = true,
  }) : _jobRepository = jobRepository,
       _workRepository = workRepository,
       _backgroundScheduler =
           backgroundScheduler ?? const NoopEnrichmentBackgroundScheduler(),
       _foregroundServiceKeeper =
           foregroundServiceKeeper ??
           const NoopEnrichmentForegroundServiceKeeper(),
       _networkAvailability =
           networkAvailability ?? const AlwaysOnlineNetworkAvailability(),
       _deckSpeciesSnapshotPort = deckSpeciesSnapshotPort,
       _allDeckIdsPort = allDeckIdsPort,
       _hostCooldownTracker = hostCooldownTracker,
       _processJobs = processJobs,
       _foregroundOwner =
           'foreground-${DateTime.now().microsecondsSinceEpoch}' {
    _executor = EnrichmentJobExecutor(
      enrichmentService,
      _jobRepository,
      taxonomyEnrichmentService: taxonomyEnrichmentService,
      deckCoverStore: deckCoverStore,
      imageService: imageService,
      nameResolutionPort: nameResolutionPort,
      deckSpeciesMutationPort: deckSpeciesMutationPort,
      unresolvedNamesObserver: unresolvedNamesObserver,
      onStateChanged: _refreshState,
      workRepository: _workRepository,
      diagnostics: diagnostics,
    );
    if (autoInitialize) {
      unawaited(initialize());
    }
    _hostCooldownTracker.addListener(_handleHostCooldownChanged);
  }

  INatEnrichmentStatus get status => _status;

  DeckEnrichmentInfo deckInfo(String deckId) {
    return _deckInfoByDeckId[deckId] ??
        const DeckEnrichmentInfo(
          status: EnrichmentJobStatus.completed,
          state: DeckEnrichmentState.hidden,
          lastCompletedAt: null,
          lastAttemptedAt: null,
        );
  }

  Future<void> initialize() {
    return _initializationFuture ??= _initialize();
  }

  Future<void> enterInteractivePriorityMode() async {
    _interactiveHoldCount++;
    _log.debug('Enter interactive priority mode holds=$_interactiveHoldCount');
    if (_interactiveHoldCount > 1) {
      return;
    }
    _restartForegroundRunnerWhenIdle = false;
    await _jobRepository.pauseJobsOwnedBy(_foregroundOwner);
    await _refreshState();
  }

  Future<void> leaveInteractivePriorityMode() async {
    if (_interactiveHoldCount == 0) return;
    _interactiveHoldCount--;
    _log.debug('Leave interactive priority mode holds=$_interactiveHoldCount');
    if (_interactiveHoldCount > 0 || _disposed) {
      return;
    }
    await _refreshState();
    _ensureForegroundRunner();
  }

  Future<void> scheduleDeckEnrichment(
    List<String> deckIds, {
    bool includeINatPhotos = true,
    bool includeCommonNames = true,
    Map<String, String?> coverImageUrlsByDeckId = const {},
    Map<String, List<String>> unresolvedNamesByDeckId = const {},
    bool waitForForegroundIdle = false,
  }) async {
    final normalizedDeckIds = orderedUniqueStrings(deckIds);
    if (normalizedDeckIds.isEmpty) return;

    final speciesIdsByDeckId = <String, Set<String>>{};
    final speciesDeckFrequency = <String, int>{};
    final deckOrderById = <String, int>{
      for (var index = 0; index < normalizedDeckIds.length; index++)
        normalizedDeckIds[index]: index,
    };

    for (final deckId in normalizedDeckIds) {
      final speciesIds = await _deckSpeciesSnapshotPort.loadSpeciesIdsForDecks({
        deckId,
      });
      speciesIdsByDeckId[deckId] = speciesIds;
      for (final speciesId in speciesIds) {
        speciesDeckFrequency.update(
          speciesId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    final newDeckPriorityOrder = normalizedDeckIds.toList(growable: false)
      ..sort((left, right) {
        int deckScore(String deckId) {
          final speciesIds = speciesIdsByDeckId[deckId] ?? const <String>{};
          return speciesIds.fold<int>(
            0,
            (score, speciesId) =>
                score + (speciesDeckFrequency[speciesId] ?? 0),
          );
        }

        final scoreComparison = deckScore(right).compareTo(deckScore(left));
        if (scoreComparison != 0) {
          return scoreComparison;
        }
        return (deckOrderById[left] ?? 0).compareTo(deckOrderById[right] ?? 0);
      });

    // Include already-running jobs at lower priority. Without this,
    // assignSpeciesOwners would re-assign overlapping species to the new
    // deck — but the active deck's job payload still contains them, so both
    // executors would process the same species independently.
    final newDeckIdSet = normalizedDeckIds.toSet();
    final activeJobs = await _jobRepository.loadAllJobs();
    final activeOnlyDeckIds = <String>[];
    for (final job in activeJobs) {
      if (newDeckIdSet.contains(job.deckId)) continue;
      if (!job.hasPendingWork) continue;
      final activeSpeciesIds = job.payload.speciesIds.toSet();
      if (activeSpeciesIds.isEmpty) continue;
      speciesIdsByDeckId[job.deckId] = activeSpeciesIds;
      activeOnlyDeckIds.add(job.deckId);
    }
    final prioritizedDeckIds = <String>[
      ...newDeckPriorityOrder,
      ...activeOnlyDeckIds,
    ];

    final assignedSpeciesIdsByDeckId = await _workRepository
        .assignSpeciesOwners(
          speciesIdsByDeckId: speciesIdsByDeckId,
          prioritizedDeckIds: prioritizedDeckIds,
        );

    for (final deckId in newDeckPriorityOrder) {
      final speciesIds = speciesIdsByDeckId[deckId] ?? const <String>{};
      final assignedSpeciesIds =
          assignedSpeciesIdsByDeckId[deckId] ?? const <String>[];
      _log.debug(
        'Schedule deck enrichment deck=$deckId '
        'assignedSpecies=${assignedSpeciesIds.length}/${speciesIds.length}',
      );
      await _jobRepository.scheduleDeckJob(
        deckId: deckId,
        speciesIds: assignedSpeciesIds,
        includeINatPhotos: includeINatPhotos,
        includeCommonNames: includeCommonNames,
        coverImageUrl: coverImageUrlsByDeckId[deckId],
        unresolvedSpeciesNames: unresolvedNamesByDeckId[deckId] ?? const [],
      );
    }

    if (_processJobs &&
        !_isInForeground &&
        await _jobRepository.hasPendingWork()) {
      await _foregroundServiceKeeper.startKeepingAlive();
      _keeperWanted = true;
    }
    await _refreshState();
    _ensureForegroundRunner();
    if (waitForForegroundIdle && _processJobs) {
      await _awaitForegroundIdle();
    }
  }

  void cancelDeckEnrichment(String deckId) {
    _log.debug('Cancel enrichment requested deck=$deckId');
    unawaited(_cancelDeckEnrichment(deckId));
  }

  @override
  void dispose() {
    _disposed = true;
    _detachLifecycleObserver();
    _networkSubscription?.cancel();
    _hostCooldownTracker.removeListener(_handleHostCooldownChanged);
    _cooldownDisplayTimer?.cancel();
    _cooldownDisplayTimer = null;
    for (final timer in _pauseDisplayTimers.values) {
      timer.cancel();
    }
    _pauseDisplayTimers.clear();
    _log.debug('Dispose queue service foregroundOwner=$_foregroundOwner');
    unawaited(_jobRepository.pauseJobsOwnedBy(_foregroundOwner));
    if (_keeperWanted) {
      _keeperWanted = false;
      unawaited(_foregroundServiceKeeper.stopKeepingAlive());
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    _log.debug('Initialize queue service foregroundOwner=$_foregroundOwner');
    await _backgroundScheduler.initialize();
    await _foregroundServiceKeeper.initialize();
    await _networkAvailability.initialize();
    if (_disposed) return;
    await _pruneOrphanedJobs();
    if (_disposed) return;
    _networkSubscription = _networkAvailability.onlineStatusChanges.listen(
      _handleNetworkStatusChanged,
    );
    await _refreshState();
    if (_disposed) return;
    _attachLifecycleObserver();
    _ensureForegroundRunner();
  }

  /// One-time sweep for job/stage rows left behind by decks deleted before
  /// [deleteDeckJob] replaced the old soft-cancel behavior. Cheap no-op on
  /// every run after the first, since new deletions no longer leave orphans.
  Future<void> _pruneOrphanedJobs() async {
    final port = _allDeckIdsPort;
    if (port == null) return;
    try {
      final validDeckIds = await port.loadAllDeckIds();
      await _jobRepository.pruneJobsNotIn(validDeckIds);
    } catch (error) {
      _log.warn('Pruning orphaned enrichment jobs failed: $error');
    }
  }

  Future<void> _cancelDeckEnrichment(String deckId) async {
    try {
      await _jobRepository.deleteDeckJob(deckId);
      await _workRepository.releaseDeck(deckId);
      await _backgroundScheduler.cancelProcessingForDeck(deckId);
      // The delta-loading refresh only picks up rows whose updated_at moved
      // forward — a deletion never shows up that way, so it has to be
      // dropped from in-memory state explicitly here.
      _jobsByDeckId.remove(deckId);
      _deckInfoByDeckId.remove(deckId);
      await _refreshState();
    } catch (error) {
      _log.warn('Cancel enrichment failed for deleted deck $deckId: $error');
    }
  }

  void _handleAppLifecycleState(AppLifecycleState state) {
    _log.debug('Lifecycle state changed: $state');
    switch (state) {
      case AppLifecycleState.resumed:
        _scheduleLifecycleTransition(true);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _scheduleLifecycleTransition(false);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _scheduleLifecycleTransition(bool foreground) {
    _targetForeground = foreground;
    _lifecycleTransition = _lifecycleTransition
        .catchError((Object error, StackTrace stackTrace) {
          _log.warn('Lifecycle transition failed: $error');
        })
        .then((_) async {
          if (_disposed) return;

          final nextForeground = _targetForeground;
          if (nextForeground == _isInForeground) {
            return;
          }

          _isInForeground = nextForeground;
          if (nextForeground) {
            await _onResumed();
          } else {
            await _onBackgrounded();
          }
        });
  }

  Future<void> _onResumed() async {
    _log.debug('Queue resumed');
    await _refreshState();
    _ensureForegroundRunner();
  }

  Future<void> _onBackgrounded() async {
    _log.debug('Queue backgrounded');
    // Keep the foreground runner going in the UI isolate. The keeper drives a
    // foreground-service notification so the OS does not reap the process.
    // No Workmanager handoff here — that path spawns a second isolate which
    // would race the UI isolate for the user-DB writer lock.
    await _refreshState();
  }

  void _ensureForegroundRunner() {
    if (!_processJobs) return;
    if (_interactiveHoldCount > 0) {
      _log.debug(
        'Skip foreground runner start because interactive priority is active',
      );
      return;
    }
    if (!_networkAvailability.isOnline) {
      _log.debug('Skip foreground runner start because device is offline');
      return;
    }
    if (_foregroundRunner != null) {
      _log.debug('Foreground runner already active');
      return;
    }
    _log.debug('Start foreground runner');
    _foregroundRunner = _runForegroundJobs();
  }

  Future<void> _runForegroundJobs() async {
    try {
      _log.debug('Foreground runner enter owner=$_foregroundOwner');
      await _executor.processUntilIdle(
        owner: _foregroundOwner,
        runnerKind: EnrichmentRunnerKind.foreground,
        shouldStop: () =>
            _disposed ||
            _interactiveHoldCount > 0 ||
            !_networkAvailability.isOnline,
      );
    } finally {
      _foregroundRunner = null;
      _log.debug('Foreground runner exit owner=$_foregroundOwner');
      if (!_disposed) {
        await _refreshState();
        if (_interactiveHoldCount == 0 &&
            _restartForegroundRunnerWhenIdle) {
          _restartForegroundRunnerWhenIdle = false;
          _ensureForegroundRunner();
        }
      }
    }
  }

  Future<void> _awaitForegroundIdle() async {
    while (_foregroundRunner != null) {
      await _foregroundRunner;
    }
  }

  Future<void> _refreshState() async {
    if (_disposed) return;
    _refreshStateQueued = true;
    if (_refreshStateFuture != null) {
      await _refreshStateFuture;
      return;
    }
    _refreshStateFuture = _drainQueuedRefreshStates();
    try {
      await _refreshStateFuture;
    } finally {
      _refreshStateFuture = null;
    }
  }

  Future<void> _drainQueuedRefreshStates() async {
    while (_refreshStateQueued && !_disposed) {
      _refreshStateQueued = false;
      await _refreshStateNow();
    }
  }

  Future<void> _refreshStateNow() async {
    // Only (re-)load jobs whose row actually changed since the last poll —
    // completed/cancelled jobs from long-finished decks never change again,
    // so re-reading and re-parsing the full history on every checkpoint
    // would only get more expensive the longer the app is used. Changed rows
    // are merged into the existing in-memory map rather than replacing it.
    final changedJobs = await _jobRepository.loadJobsUpdatedSince(
      _jobsSyncedThrough,
    );
    if (_disposed) return;
    for (final job in changedJobs) {
      if (job.status == EnrichmentJobStatus.failedPermanent) {
        final prev = _jobsByDeckId[job.deckId];
        if (prev != null && prev.status != EnrichmentJobStatus.failedPermanent) {
          _sessionFailedDeckIds.add(job.deckId);
        }
      }
      _jobsByDeckId[job.deckId] = job;
      if (job.updatedAt.isAfter(_jobsSyncedThrough)) {
        _jobsSyncedThrough = job.updatedAt;
      }
    }
    final jobs = _jobsByDeckId.values.toList(growable: false);
    final nextStatus = _deriveStatus(jobs);
    _syncCooldownActiveSince(nextStatus.hasActiveHostCooldown);
    _syncPauseDisplayTimers(jobs);
    final nextDeckInfoByDeckId = _deriveDeckInfoByDeckId(
      jobs,
      hasActiveHostCooldown: nextStatus.hasActiveHostCooldown,
    );
    final hasVisibleChange =
        nextStatus != _status ||
        !_deckInfoMapEquals(_deckInfoByDeckId, nextDeckInfoByDeckId);

    _deckInfoByDeckId
      ..clear()
      ..addAll(nextDeckInfoByDeckId);
    _status = nextStatus;

    if (!hasVisibleChange) {
      return;
    }

    _log.debug(
      'Refresh queue state jobs=${jobs.length} '
      'running=${jobs.where((job) => job.status == EnrichmentJobStatus.runningForeground || job.status == EnrichmentJobStatus.runningBackground).length} '
      'pending=${jobs.where((job) => job.hasPendingWork).length}',
    );
    await _syncForegroundServiceKeeper();
    await _syncBackgroundNotificationContent();
    notifyListeners();
  }

  void _handleNetworkStatusChanged(bool isOnline) {
    if (_disposed) return;
    _log.debug('Network status changed: ${isOnline ? 'online' : 'offline'}');
    if (isOnline) {
      _ensureForegroundRunner();
    }
    // When going offline the running executor's shouldStop will return true
    // at its next loop iteration, stopping the runner without explicit action.
  }

  /// Whether the background keepalive service (and its notification) should
  /// stay up. Includes an active host cooldown alongside active work so a
  /// short rate-limit pause doesn't tear the notification down only to bring
  /// it straight back once the cooldown clears — it just switches its text
  /// to the cooldown message instead. This also keeps the process alive
  /// through the cooldown so the queue can actually resume automatically
  /// once it's over.
  bool get _shouldKeepBackgroundPresenceAlive =>
      _status.hasActiveWork || _status.hasActiveHostCooldown;

  Future<void> _syncForegroundServiceKeeper() async {
    if (!_processJobs) return;
    final shouldRun =
        !_isInForeground &&
        _shouldKeepBackgroundPresenceAlive &&
        _networkAvailability.isOnline;
    if (shouldRun == _keeperWanted) return;
    _keeperWanted = shouldRun;
    if (shouldRun) {
      await _foregroundServiceKeeper.startKeepingAlive();
    } else {
      await _foregroundServiceKeeper.stopKeepingAlive();
    }
  }

  INatEnrichmentStatus _deriveStatus(List<EnrichmentJobRecord> jobs) {
    return deriveEnrichmentStatus(
      jobs,
      hasActiveHostCooldown: _hostCooldownTracker.hasActiveCooldown,
      preferBackgroundMessaging: !_isInForeground,
    );
  }

  INatEnrichmentPhase? _phaseForStage(EnrichmentStage? stage) {
    return phaseForEnrichmentStage(stage);
  }

  Map<String, DeckEnrichmentInfo> _deriveDeckInfoByDeckId(
    Iterable<EnrichmentJobRecord> jobs, {
    required bool hasActiveHostCooldown,
  }) {
    return {
      for (final job in jobs)
        job.deckId: _buildDeckInfo(
          job,
          hasActiveHostCooldown: hasActiveHostCooldown,
        ),
    };
  }

  DeckEnrichmentInfo _buildDeckInfo(
    EnrichmentJobRecord job, {
    required bool hasActiveHostCooldown,
  }) {
    final activeStage =
        job.currentStage ?? _jobRepository.nextRunnableStage(job);
    final progress = deriveDisplayedProgress(job, stage: activeStage);
    final hasTransientPermanentFailure =
        _sessionFailedDeckIds.contains(job.deckId);
    final state = computeDeckEnrichmentState(
      job: job,
      hasActiveHostCooldown: hasActiveHostCooldown,
      cooldownActiveSince: _cooldownActiveSince,
      hasTransientPermanentFailure: hasTransientPermanentFailure,
      cooldownDisplayThreshold: cooldownDisplayThreshold,
      pauseDisplayThreshold: pauseDisplayThreshold,
    );
    return DeckEnrichmentInfo(
      status: job.status,
      state: state,
      lastCompletedAt: job.completedAt,
      lastAttemptedAt: job.attemptedAt,
      currentPhase: _phaseForStage(activeStage),
      includesINatPhotos: job.payload.includeINatPhotos,
      includesCommonNames: job.payload.includeCommonNames,
      progressCompleted: progress.completed,
      progressTotal: progress.total,
      isReady: isReadyForJob(job),
      hasActiveHostCooldown: hasActiveHostCooldown,
      imageStagesComplete: job.everySpeciesHasImage,
    );
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

  void _attachLifecycleObserver() {
    try {
      final observer = _QueueLifecycleObserver(this);
      WidgetsBinding.instance.addObserver(observer);
      _lifecycleObserver = observer;
    } catch (_) {
      _lifecycleObserver = null;
    }
  }

  void _detachLifecycleObserver() {
    final observer = _lifecycleObserver;
    if (observer == null) return;
    try {
      WidgetsBinding.instance.removeObserver(observer);
    } catch (_) {
      // Ignore if binding is already gone.
    }
    _lifecycleObserver = null;
  }

  /// Folds live progress into the foreground-service keepalive notification
  /// instead of showing a second, separate system notification. Only
  /// relevant while backgrounded — in the foreground the in-app banner
  /// already communicates progress, so no system notification is needed.
  Future<void> _syncBackgroundNotificationContent() async {
    if (_isInForeground) return;
    if (!_shouldKeepBackgroundPresenceAlive) return;
    final loc = _localizationsForCurrentLocale();
    await _foregroundServiceKeeper.updateNotificationContent(
      title: _status.preferBackgroundMessaging
          ? loc.inatBackgroundBannerTitleBackground
          : loc.inatBackgroundBannerTitle,
      text: formatDeckPendingStatusLabel(
        loc,
        hasActiveHostCooldown: _status.hasActiveHostCooldown,
        progressCompleted: _status.completed,
        progressTotal: _status.total,
      ),
    );
  }

  /// Notifications fire outside the widget tree, so this looks up the
  /// device locale directly instead of relying on a BuildContext.
  AppLocalizations _localizationsForCurrentLocale() {
    final locale = PlatformDispatcher.instance.locale;
    return lookupAppLocalizations(
      locale.languageCode == 'de' ? const Locale('de') : const Locale('en'),
    );
  }

  void _handleHostCooldownChanged() {
    unawaited(_syncCooldownStatus());
  }

  Future<void> _syncCooldownStatus() async {
    if (_disposed) return;
    final hasActiveHostCooldown = _hostCooldownTracker.hasActiveCooldown;
    final cooldownJustCleared =
        _status.hasActiveHostCooldown && !hasActiveHostCooldown;
    _syncCooldownActiveSince(hasActiveHostCooldown);
    final nextStatus = _status.copyWith(
      hasActiveHostCooldown: hasActiveHostCooldown,
    );
    final nextDeckInfoByDeckId = _deriveDeckInfoByDeckId(
      _jobsByDeckId.values,
      hasActiveHostCooldown: hasActiveHostCooldown,
    );
    final hasVisibleChange =
        nextStatus != _status ||
        !_deckInfoMapEquals(_deckInfoByDeckId, nextDeckInfoByDeckId);
    if (!hasVisibleChange) {
      return;
    }
    _status = nextStatus;
    _deckInfoByDeckId
      ..clear()
      ..addAll(nextDeckInfoByDeckId);
    await _syncForegroundServiceKeeper();
    await _syncBackgroundNotificationContent();
    notifyListeners();
    // When the cooldown clears, retryScheduled jobs can run again. Reset
    // their next_attempt_at so claimNextJob picks them up immediately, then
    // restart the foreground runner.
    if (cooldownJustCleared) {
      await _jobRepository.clearRetryAttemptForRetryScheduledJobs();
      await _refreshState();
      _ensureForegroundRunner();
    }
  }

  void _syncCooldownActiveSince(bool hasActiveHostCooldown) {
    final wasActive = _cooldownActiveSince != null;
    if (hasActiveHostCooldown && !wasActive) {
      _cooldownActiveSince = DateTime.now();
      _scheduleCooldownDisplayTimer();
    } else if (!hasActiveHostCooldown && wasActive) {
      _cooldownActiveSince = null;
      _cooldownDisplayTimer?.cancel();
      _cooldownDisplayTimer = null;
    }
  }

  void _scheduleCooldownDisplayTimer() {
    _cooldownDisplayTimer?.cancel();
    final startedAt = _cooldownActiveSince;
    if (startedAt == null) return;
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = cooldownDisplayThreshold - elapsed;
    if (remaining <= Duration.zero) return;
    _cooldownDisplayTimer = Timer(remaining, () {
      _cooldownDisplayTimer = null;
      if (_disposed) return;
      unawaited(_refreshState());
    });
  }

  void _syncPauseDisplayTimers(Iterable<EnrichmentJobRecord> jobs) {
    final now = DateTime.now();
    final wantedDeckIds = <String>{};
    for (final job in jobs) {
      if (job.status != EnrichmentJobStatus.retryScheduled) continue;
      final nextAttemptAt = job.nextAttemptAt;
      if (nextAttemptAt == null) continue;
      final delta = nextAttemptAt.difference(now);
      if (delta <= pauseDisplayThreshold) continue;
      wantedDeckIds.add(job.deckId);
      if (_pauseDisplayTimers.containsKey(job.deckId)) continue;
      final fireDelay = delta - pauseDisplayThreshold;
      _pauseDisplayTimers[job.deckId] = Timer(fireDelay, () {
        _pauseDisplayTimers.remove(job.deckId);
        if (_disposed) return;
        unawaited(_refreshState());
      });
    }
    final toRemove = _pauseDisplayTimers.keys
        .where((deckId) => !wantedDeckIds.contains(deckId))
        .toList(growable: false);
    for (final deckId in toRemove) {
      _pauseDisplayTimers.remove(deckId)?.cancel();
    }
  }
}

class _QueueLifecycleObserver with WidgetsBindingObserver {
  final INatEnrichmentQueueService _service;

  _QueueLifecycleObserver(this._service);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _service._handleAppLifecycleState(state);
  }
}
