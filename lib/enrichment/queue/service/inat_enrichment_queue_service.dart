import 'dart:async';

import 'package:discere/enrichment/pipeline/repository/deck_enrichment_projection_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_maintenance_repository.dart';
import 'package:discere/enrichment/pipeline/service/base_worker.dart';
import 'package:discere/enrichment/pipeline/service/inat_worker.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_info.dart';
import 'package:discere/enrichment/queue/model/inat_enrichment_status.dart';
import 'package:discere/enrichment/queue/presentation/deck_enrichment_state_presenter.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/cover_job_runner.dart';
import 'package:discere/enrichment/queue/service/deck_enrichment_priority.dart';
import 'package:discere/enrichment/queue/service/deck_enrichment_status_store.dart';
import 'package:discere/enrichment/queue/service/enrichment_background_presence.dart';
import 'package:discere/enrichment/queue/service/enrichment_background_scheduler.dart';
import 'package:discere/enrichment/queue/service/enrichment_lifecycle_coordinator.dart';
import 'package:discere/enrichment/queue/service/enrichment_progress_status.dart';
import 'package:discere/enrichment/queue/service/foreground_enrichment_runner.dart';
import 'package:discere/enrichment/queue/service/pause_visibility_scheduler.dart';
import 'package:discere/enrichment/util/ordered_unique_strings.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/service/foreground_service_keeper.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class INatEnrichmentQueueService extends ChangeNotifier {
  static final _log = Logger.forType(INatEnrichmentQueueService);
  final EnrichmentJobRepository _jobRepository;
  final EnrichmentOwnershipRepository _ownershipRepository;
  final EnrichmentWorkMaintenanceRepository _maintenanceRepository;
  final DeckEnrichmentProjectionRepository _projectionRepository;
  late final DeckEnrichmentStatusStore _store;
  late final ForegroundEnrichmentRunner _runner;
  late final EnrichmentLifecycleCoordinator _lifecycle;
  late final PauseVisibilityScheduler _pauseVisibility;
  late final EnrichmentBackgroundPresence _backgroundPresence;
  final EnrichmentBackgroundScheduler _backgroundScheduler;
  final NetworkAvailability _networkAvailability;
  final DeckSpeciesSnapshotPort _deckSpeciesSnapshotPort;
  final AllDeckIdsPort? _allDeckIdsPort;
  final HostCooldownTracker _hostCooldownTracker;
  final String _foregroundOwner;
  final bool _processJobs;

  Future<void>? _initializationFuture;
  Future<void>? _refreshStateFuture;
  int _interactiveHoldCount = 0;
  bool _restartForegroundRunnerWhenIdle = false;
  bool _refreshStateQueued = false;
  bool _disposed = false;

  INatEnrichmentQueueService({
    // The three queue consumers arrive built: assembling them needs eight
    // collaborators this service otherwise has no use for, and building
    // collaborators is the composition root's job (ARCH-09).
    required CoverJobRunner coverRunner,
    required BaseWorker baseWorker,
    required INatWorker iNatWorker,
    required DeckSpeciesSnapshotPort deckSpeciesSnapshotPort,
    AllDeckIdsPort? allDeckIdsPort,
    required EnrichmentJobRepository jobRepository,
    required EnrichmentOwnershipRepository ownershipRepository,
    required EnrichmentWorkMaintenanceRepository maintenanceRepository,
    required DeckEnrichmentProjectionRepository projectionRepository,
    required HostCooldownTracker hostCooldownTracker,
    // Null-object defaults: platform integrations that legitimately do
    // nothing in tests. Real implementations are wired in the bootstrap.
    EnrichmentBackgroundScheduler? backgroundScheduler,
    ForegroundServiceKeeper? foregroundServiceKeeper,
    NetworkAvailability? networkAvailability,
    bool autoInitialize = true,
    bool processJobs = true,
  }) : _jobRepository = jobRepository,
       _ownershipRepository = ownershipRepository,
       _maintenanceRepository = maintenanceRepository,
       _projectionRepository = projectionRepository,
       _backgroundScheduler =
           backgroundScheduler ?? const NoopEnrichmentBackgroundScheduler(),
       _networkAvailability =
           networkAvailability ?? const AlwaysOnlineNetworkAvailability(),
       _deckSpeciesSnapshotPort = deckSpeciesSnapshotPort,
       _allDeckIdsPort = allDeckIdsPort,
       _hostCooldownTracker = hostCooldownTracker,
       _processJobs = processJobs,
       _foregroundOwner =
           'foreground-${DateTime.now().microsecondsSinceEpoch}' {
    _store = DeckEnrichmentStatusStore(
      jobRepository: _jobRepository,
      projectionRepository: _projectionRepository,
    );
    _runner = ForegroundEnrichmentRunner(
      coverRunner: coverRunner,
      baseWorker: baseWorker,
      iNatWorker: iNatWorker,
      owner: _foregroundOwner,
      shouldStop: () =>
          _disposed || _interactiveHoldCount > 0 || !_networkAvailability.isOnline,
      onProgress: _requestRefresh,
      onPassFinished: _handleRunnerPassFinished,
    );
    _backgroundPresence = EnrichmentBackgroundPresence(
      keeper: foregroundServiceKeeper ?? const NoopForegroundServiceKeeper(),
      networkAvailability: _networkAvailability,
      enabled: _processJobs,
    );
    _pauseVisibility = PauseVisibilityScheduler(
      onBecameVisible: _requestRefresh,
    );
    _lifecycle = EnrichmentLifecycleCoordinator(
      networkAvailability: _networkAvailability,
      onEnterForeground: _onResumed,
      onLeaveForeground: _onBackgrounded,
      onNetworkOnline: _ensureForegroundRunner,
    );
    if (autoInitialize) {
      unawaited(initialize());
    }
    _hostCooldownTracker.addListener(_handleHostCooldownChanged);
  }

  INatEnrichmentStatus get status => _store.status;

  /// The currently-active host cooldown (e.g. iNaturalist rate limiting), if
  /// any — surfaced for the diagnostics page.
  HostCooldownSnapshot? get activeCooldown =>
      _hostCooldownTracker.activeCooldown;

  /// Whether the Android keepalive foreground service is currently running
  /// — surfaced for the diagnostics page. Always resolves to `false` on
  /// non-Android platforms.
  Future<bool> get isForegroundServiceRunning =>
      _backgroundPresence.isRunning;

  DeckEnrichmentInfo deckInfo(String deckId) => _store.deckInfo(deckId);

  /// Species from [speciesIds] whose common-name enrichment hasn't reached a
  /// terminal state yet — the primary name a flashcard currently shows for
  /// them could still change once it does. A one-off snapshot, not a live
  /// subscription: callers re-fetch it whenever they'd reload the species
  /// list anyway (e.g. after [deckInfo] reports a new completion).
  Future<Set<String>> pendingCommonNameSpeciesIds(Set<String> speciesIds) {
    return _projectionRepository.getPendingCommonNameSpeciesIds(speciesIds);
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
    await _pauseOwnedJobs();
    await _refreshState();
  }

  /// Runs [operation], tolerating the user database being closed underneath
  /// it.
  ///
  /// Everything this service does can be in flight when the app is torn down
  /// — or, in integration tests, when the next test's teardown deletes the
  /// database out from under an unawaited call. There is nothing left to act
  /// on either way, so the work is dropped rather than thrown.
  ///
  /// Returns false when it was dropped, so a caller that would follow up
  /// (refresh state, wake the runner) can skip that too.
  Future<bool> _whileDatabaseLives(Future<void> Function() operation) async {
    try {
      await operation();
      return true;
    } on DatabaseException {
      return false;
    }
  }

  Future<void> _pauseOwnedJobs() async {
    await _whileDatabaseLives(
      () => _jobRepository.pauseJobsOwnedBy(_foregroundOwner),
    );
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

    await _whileDatabaseLives(
      () => _scheduleDeckEnrichmentUnguarded(
        normalizedDeckIds,
        includeINatPhotos: includeINatPhotos,
        includeCommonNames: includeCommonNames,
        coverImageUrlsByDeckId: coverImageUrlsByDeckId,
        unresolvedNamesByDeckId: unresolvedNamesByDeckId,
        waitForForegroundIdle: waitForForegroundIdle,
      ),
    );
  }


  Future<void> _scheduleDeckEnrichmentUnguarded(
    List<String> normalizedDeckIds, {
    required bool includeINatPhotos,
    required bool includeCommonNames,
    required Map<String, String?> coverImageUrlsByDeckId,
    required Map<String, List<String>> unresolvedNamesByDeckId,
    required bool waitForForegroundIdle,
  }) async {
    final speciesIdsByDeckId = <String, Set<String>>{};
    for (final deckId in normalizedDeckIds) {
      speciesIdsByDeckId[deckId] = await _deckSpeciesSnapshotPort
          .loadSpeciesIdsForDecks({deckId});
    }
    final newDeckPriorityOrder = prioritizeDecksBySharedSpecies(
      normalizedDeckIds,
      speciesIdsByDeckId,
    );

    // Include already-tracked decks at lower priority. Without this,
    // assignSpeciesOwners would re-assign overlapping species to the new
    // deck even though another deck's work for them is still in flight.
    final newDeckIdSet = normalizedDeckIds.toSet();
    final existingDeckSpecies = await _ownershipRepository
        .loadAllDeckSpeciesSnapshots();
    final activeOnlyDeckIds = <String>[];
    for (final entry in existingDeckSpecies.entries) {
      if (newDeckIdSet.contains(entry.key) || entry.value.isEmpty) continue;
      speciesIdsByDeckId[entry.key] = entry.value;
      activeOnlyDeckIds.add(entry.key);
    }
    final prioritizedDeckIds = <String>[
      ...newDeckPriorityOrder,
      ...activeOnlyDeckIds,
    ];

    final assignedSpeciesIdsByDeckId = await _ownershipRepository
        .assignSpeciesOwners(
          speciesIdsByDeckId: speciesIdsByDeckId,
          prioritizedDeckIds: prioritizedDeckIds,
          // Every deck in prioritizedDeckIds must have an entry here, not
          // just the decks this call is actually scheduling — assignSpecies
          // Owners defaults an absent deck to "consents" (documented
          // convenience for callers that don't track consent at all), which
          // would silently grant iNat consent on behalf of a carried-forward
          // activeOnlyDeckId this call knows nothing new about. Explicit
          // `false` here is safe: assignSpeciesOwners ORs it against the
          // deck's already-persisted consent, so a genuinely-consenting
          // active deck keeps its consent — this only prevents a *new*
          // upgrade this call has no business granting.
          includeInatPhotosByDeckId: {
            for (final deckId in newDeckPriorityOrder)
              deckId: includeINatPhotos,
            for (final deckId in activeOnlyDeckIds) deckId: false,
          },
          includeCommonNamesByDeckId: {
            for (final deckId in newDeckPriorityOrder)
              deckId: includeCommonNames,
            for (final deckId in activeOnlyDeckIds) deckId: false,
          },
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
        coverImageUrl: coverImageUrlsByDeckId[deckId],
      );
      final unresolvedNames = unresolvedNamesByDeckId[deckId] ?? const [];
      if (unresolvedNames.isNotEmpty) {
        await _ownershipRepository.seedUnresolvedNames(
          deckId,
          unresolvedNames,
          wantsInatPhotos: includeINatPhotos,
          wantsCommonNames: includeCommonNames,
        );
      }
    }

    if (_processJobs &&
        !_lifecycle.isInForeground &&
        (await _jobRepository.hasPendingWork() ||
            await _projectionRepository.hasPendingWork())) {
      await _backgroundPresence.ensureStarted();
    }
    await _refreshState();
    _ensureForegroundRunner();
    if (waitForForegroundIdle && _processJobs) {
      await _awaitForegroundIdle();
    }
  }

  /// Species (across every deck) whose `base` image predates the
  /// currently-installed reference-DB version — used to decide whether the
  /// post-reference-DB-update prompt should appear, and to render the count
  /// in its copy. Zero if no reference DB has ever been installed.
  Future<int> countStaleBaseSpeciesGlobally() async {
    final version = await ReferenceDatabaseProvisioner.currentVersion();
    if (version == null) return 0;
    return _maintenanceRepository.countStaleBaseSpecies(
      currentReferenceDbVersion: version,
    );
  }

  /// Manually resets [deckId]'s stale `base` capability rows (species whose
  /// reference image was resolved against an older reference-DB version than
  /// the one currently installed) back to `pending`, then wakes the
  /// foreground runner so `BaseWorker` reclaims them immediately.
  /// User-triggered only — see `ManualINatEnrichmentSection`'s stale-images
  /// hint on the Edit Deck page.
  Future<void> refreshStaleBaseImages(String deckId) async {
    final version = await ReferenceDatabaseProvisioner.currentVersion();
    if (version == null) return;
    final applied = await _whileDatabaseLives(
      () => _maintenanceRepository.resetStaleBaseCapability(
        deckId: deckId,
        currentReferenceDbVersion: version,
      ),
    );
    if (!applied) return;
    await _refreshState();
    _ensureForegroundRunner();
  }

  /// Same as [refreshStaleBaseImages], but across every deck at once —
  /// offered once, right after a reference-DB update finishes installing
  /// (see the main-screen update dialog).
  Future<void> refreshAllStaleBaseImages() async {
    final version = await ReferenceDatabaseProvisioner.currentVersion();
    if (version == null) return;
    final applied = await _whileDatabaseLives(
      () => _maintenanceRepository.resetStaleBaseCapability(
        currentReferenceDbVersion: version,
      ),
    );
    if (!applied) return;
    await _refreshState();
    _ensureForegroundRunner();
  }

  /// Resets every terminal `base` capability row for [deckId]'s species back
  /// to `pending`, unconditionally (no reference-DB staleness check, unlike
  /// [refreshStaleBaseImages]) — so an explicit manual retrigger from Edit
  /// Deck ("Erneut anreichern"/"Jetzt anreichern") genuinely re-verifies
  /// every species against the local image cache instead of silently no-op'ing
  /// for species whose `base` capability was already terminal. Callers are
  /// expected to follow this with [scheduleDeckEnrichment] for the chosen
  /// consent (base-only vs. full) — this call only resets `base`; it doesn't
  /// itself wake the foreground runner or touch iNat consent.
  Future<void> retriggerBaseEnrichment(String deckId) async {
    // The caller follows this with scheduleDeckEnrichment, which guards
    // itself, so nothing here depends on whether the reset landed.
    await _whileDatabaseLives(
      () => _maintenanceRepository.resetBaseCapabilityForRetrigger(deckId),
    );
  }

  void cancelDeckEnrichment(String deckId) {
    _log.debug('Cancel enrichment requested deck=$deckId');
    unawaited(_cancelDeckEnrichment(deckId));
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle.dispose();
    _hostCooldownTracker.removeListener(_handleHostCooldownChanged);
    _pauseVisibility.dispose();
    _log.debug('Dispose queue service foregroundOwner=$_foregroundOwner');
    unawaited(_pauseOwnedJobs());
    unawaited(_backgroundPresence.stop());
    super.dispose();
  }

  Future<void> _initialize() async {
    _log.debug('Initialize queue service foregroundOwner=$_foregroundOwner');
    await _backgroundScheduler.initialize();
    await _backgroundPresence.initialize();
    await _networkAvailability.initialize();
    if (_disposed) return;
    await _recoverInterruptedWork();
    if (_disposed) return;
    await _pruneOrphanedWork();
    if (_disposed) return;
    _lifecycle.watchNetwork();
    await _refreshState();
    if (_disposed) return;
    _lifecycle.watchAppLifecycle();
    _ensureForegroundRunner();
  }

  /// Startup crash recovery for [_ownershipRepository]'s queue tables: any row
  /// left `running` by a process that died mid-claim (app kill, crash)
  /// would otherwise be invisible to both `claimBaseWorkBatch` and
  /// `claimNextINatWorkItem` (they only select `pending`/`retryScheduled`),
  /// permanently stranding that species. Cheap no-op when nothing was
  /// interrupted.
  Future<void> _recoverInterruptedWork() async {
    try {
      await _maintenanceRepository.recoverInterruptedWork();
    } catch (error) {
      _log.warn('Recovering interrupted enrichment work failed: $error');
    }
  }

  /// One-time sweep for job/species-work rows left behind by decks deleted
  /// before [deleteDeckJob]/[releaseDeck] replaced the old soft-cancel
  /// behavior. Cheap no-op on every run after the first, since new deletions
  /// no longer leave orphans.
  Future<void> _pruneOrphanedWork() async {
    final port = _allDeckIdsPort;
    if (port == null) return;
    try {
      final validDeckIds = await port.loadAllDeckIds();
      await _jobRepository.pruneJobsNotIn(validDeckIds);
      final trackedDeckIds = await _ownershipRepository
          .loadAllDeckSpeciesSnapshots();
      for (final deckId in trackedDeckIds.keys) {
        if (validDeckIds.contains(deckId)) continue;
        await _ownershipRepository.releaseDeck(deckId);
      }
    } catch (error) {
      _log.warn('Pruning orphaned enrichment work failed: $error');
    }
  }

  Future<void> _cancelDeckEnrichment(String deckId) async {
    try {
      await _jobRepository.deleteDeckJob(deckId);
      await _ownershipRepository.releaseDeck(deckId);
      await _backgroundScheduler.cancelProcessingForDeck(deckId);
      // The delta-loading refresh only picks up rows whose updated_at moved
      // forward — a deletion never shows up that way, so it has to be
      // dropped from in-memory state explicitly here.
      _store.forget(deckId);
      await _refreshState();
    } catch (error) {
      _log.warn('Cancel enrichment failed for deleted deck $deckId: $error');
    }
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
    if (_runner.isRunning) {
      // The three consumers drain independently inside one Future.wait, so
      // one of them can have found nothing claimable and returned while
      // another is still busy. Work meant for the already-idle one would
      // otherwise wait for some unrelated trigger — an app resume, a network
      // change, another schedule call — to notice it.
      _log.debug('Foreground runner already active, will restart when idle');
      _restartForegroundRunnerWhenIdle = true;
      return;
    }
    _runner.start();
  }

  Future<void> _handleRunnerPassFinished() async {
    if (_disposed) return;
    await _refreshState();
    if (_interactiveHoldCount == 0 && _restartForegroundRunnerWhenIdle) {
      _restartForegroundRunnerWhenIdle = false;
      _ensureForegroundRunner();
    }
  }

  /// Something happened that the deck cards may need to reflect: a worker
  /// finished an item, or a pause crossed the threshold at which it becomes
  /// visible. Deck progress moves live during a long batch this way, instead
  /// of jumping only once the whole foreground-runner pass finishes.
  ///
  /// Unawaited and safe to call at high frequency: `_refreshState` coalesces
  /// concurrent calls into a single drain loop and only notifies listeners
  /// when something actually changed.
  void _requestRefresh() {
    if (_disposed) return;
    unawaited(_refreshState());
  }

  Future<void> _awaitForegroundIdle() => _runner.awaitIdle();

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
    if (!await _store.pullChanges()) return;
    if (_disposed) return;

    final snapshots = _store.snapshots();
    final nextStatus = _store.deriveStatus(
      snapshots,
      hasActiveHostCooldown: _hostCooldownTracker.hasActiveCooldown,
      preferBackgroundMessaging: !_lifecycle.isInForeground,
    );
    // The cooldown timestamp follows the *derived* flag rather than the
    // tracker: with nothing pending the derivation reports no cooldown at
    // all, and the per-deck states have to agree with what the status says.
    _pauseVisibility.syncCooldown(nextStatus.hasActiveHostCooldown);
    _pauseVisibility.syncDeckPauses(snapshots);
    final hasVisibleChange = _commitToStore(snapshots, nextStatus);
    if (!hasVisibleChange) return;

    _log.debug(
      'Refresh queue state decks=${snapshots.length} '
      'immediatePending=${snapshots.where((d) => d.hasImmediatePendingWork).length} '
      'pending=${snapshots.where((d) => d.hasPendingWork).length}',
    );
    await _syncBackgroundPresence();
    // Re-checked here (not just at entry) because this function is reached
    // via several await points — dispose() (e.g. a test's tearDown racing a
    // still-in-flight onProgress-triggered refresh) can land in any of them,
    // and ChangeNotifier asserts in debug mode if notifyListeners is called
    // after dispose.
    if (_disposed) return;
    notifyListeners();
  }

  bool _commitToStore(
    List<DeckWorkSnapshot> snapshots,
    INatEnrichmentStatus status,
  ) => _store.commit(
    snapshots,
    status,
    hasActiveHostCooldown: status.hasActiveHostCooldown,
    cooldownActiveSince: _pauseVisibility.cooldownActiveSince,
    cooldownDisplayThreshold: cooldownVisibleAfter,
    pauseDisplayThreshold: pauseVisibleAfter,
  );

  Future<void> _syncBackgroundPresence() => _backgroundPresence.sync(
    isInForeground: _lifecycle.isInForeground,
    status: _store.status,
  );

  void _handleHostCooldownChanged() {
    unawaited(_syncCooldownStatus());
  }

  Future<void> _syncCooldownStatus() async {
    if (_disposed) return;
    final hasActiveHostCooldown = _hostCooldownTracker.hasActiveCooldown;
    final cooldownJustCleared =
        _store.status.hasActiveHostCooldown && !hasActiveHostCooldown;
    _pauseVisibility.syncCooldown(hasActiveHostCooldown);
    final nextStatus = _store.status.copyWith(
      hasActiveHostCooldown: hasActiveHostCooldown,
    );
    if (!_commitToStore(_store.snapshots(), nextStatus)) return;
    await _syncBackgroundPresence();
    // See the matching check in _refreshStateNow for why this is re-checked
    // here rather than trusting the entry check at the top of this function.
    if (_disposed) return;
    notifyListeners();
    // When the cooldown clears, retryScheduled jobs/work can run again.
    // Reset their next_attempt_at so the workers pick them up immediately,
    // then restart the foreground runner.
    if (cooldownJustCleared) {
      final cleared = await _whileDatabaseLives(() async {
        await _jobRepository.clearRetryAttemptForRetryScheduledJobs();
        await _maintenanceRepository.clearRetryAttemptForRetryScheduledWorkItems();
      });
      if (!cleared) return;
      await _refreshState();
      _ensureForegroundRunner();
    }
  }
}
