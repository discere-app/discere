import 'dart:async';
import 'dart:ui';

import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/enrichment/pipeline/service/base_image_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/base_worker.dart';
import 'package:discere/enrichment/pipeline/service/inat_photo_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/inat_worker.dart';
import 'package:discere/enrichment/pipeline/service/species_common_name_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_projection.dart';
import 'package:discere/enrichment/queue/model/deck_enrichment_state.dart';
import 'package:discere/enrichment/queue/presentation/enrichment_status_presenter.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/cover_job_runner.dart';
import 'package:discere/enrichment/queue/service/enrichment_background_scheduler.dart';
import 'package:discere/enrichment/queue/service/enrichment_foreground_service_keeper.dart';
import 'package:discere/enrichment/queue/service/enrichment_progress_status.dart';
import 'package:discere/enrichment/util/ordered_unique_strings.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

export 'package:discere/enrichment/queue/model/deck_enrichment_state.dart';

export 'enrichment_progress_status.dart';

/// UI-facing snapshot of a deck's enrichment work. Deliberately limited to
/// what the deck-card hint and the edit-deck section actually render —
/// internals like error text or retry timing stay inside the service and
/// only surface through the derived [state].
class DeckEnrichmentInfo {
  final EnrichmentJobStatus status;
  final DeckEnrichmentState state;
  final DateTime? lastCompletedAt;
  final DateTime? lastAttemptedAt;
  final bool includesINatPhotos;
  final bool includesCommonNames;
  final int progressCompleted;
  final int progressTotal;
  final bool isReady;
  final bool hasActiveHostCooldown;

  /// True once every species in the deck has reached a terminal state
  /// (downloaded image or explicit no-result marker) for both image-loading
  /// capabilities — i.e. [DeckEnrichmentProjection.imageStagesComplete].
  /// Defaults to true for the "no work known yet" fallback instance, since
  /// there is nothing to wait for in that case.
  final bool imageStagesComplete;

  const DeckEnrichmentInfo({
    required this.status,
    this.state = DeckEnrichmentState.hidden,
    required this.lastCompletedAt,
    required this.lastAttemptedAt,
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
    includesINatPhotos,
    includesCommonNames,
    progressCompleted,
    progressTotal,
    isReady,
    hasActiveHostCooldown,
    imageStagesComplete,
  );
}

/// Maps a [DeckEnrichmentState] onto the coarser [EnrichmentJobStatus]
/// vocabulary [DeckEnrichmentInfo]'s derived getters (`isActive`,
/// `hasPendingWork`, `hasFailedAttempt`) already switch on. There is no
/// longer a single per-deck job status once species/taxonomy work is
/// reactive rather than one sequential stage ladder, so this is a display
/// convenience derived entirely from [state] — not read anywhere on its own.
EnrichmentJobStatus _statusForState(DeckEnrichmentState state) {
  return switch (state) {
    DeckEnrichmentState.hidden => EnrichmentJobStatus.cancelled,
    DeckEnrichmentState.pending => EnrichmentJobStatus.queued,
    DeckEnrichmentState.loadingBase || DeckEnrichmentState.loadingExtended =>
      EnrichmentJobStatus.runningForeground,
    DeckEnrichmentState.done ||
    DeckEnrichmentState.doneWithGaps => EnrichmentJobStatus.completed,
    DeckEnrichmentState.cooldown ||
    DeckEnrichmentState.paused => EnrichmentJobStatus.retryScheduled,
    DeckEnrichmentState.failed => EnrichmentJobStatus.failedPermanent,
  };
}

class INatEnrichmentQueueService extends ChangeNotifier {
  static final _log = Logger.forType(INatEnrichmentQueueService);
  final EnrichmentJobRepository _jobRepository;
  final EnrichmentWorkRepository _workRepository;
  late final CoverJobRunner _coverRunner;
  late final BaseWorker _baseWorker;
  late final INatWorker _iNatWorker;
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

  /// Deck ids that need their projection reloaded regardless of what
  /// [_workSyncedThrough]'s delta query finds — populated by
  /// [_handleDecksNeedForcedReload] whenever `INatWorker` reports that a
  /// deck's last tracked species was just pruned from
  /// `enrichment_species_deck_membership`. The delta query joins through
  /// that same table, so once the row is gone that deck can never again be
  /// detected as "changed" via the normal poll — without this, its cached
  /// projection would freeze at whatever it was the instant before the
  /// prune, forever (e.g. showing `loadingExtended` for a deck that has
  /// actually finished).
  final Set<String> _forcedProjectionReloadDeckIds = <String>{};

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

  INatEnrichmentQueueService({
    required BaseImageEnrichmentService baseImageEnrichmentService,
    required INatPhotoEnrichmentService photoEnrichmentService,
    required SpeciesCommonNameEnrichmentService commonNameEnrichmentService,
    required TaxonomyCommonNameEnrichmentService taxonomyEnrichmentService,
    required SpeciesRepository speciesRepository,
    required INatPhotoCacheRepository photoCacheRepository,
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
    _coverRunner = CoverJobRunner(
      _jobRepository,
      deckCoverStore,
      imageService,
      diagnostics: diagnostics,
    );
    _baseWorker = BaseWorker(
      baseImageEnrichmentService,
      _workRepository,
      speciesRepository,
      diagnostics: diagnostics,
    );
    _iNatWorker = INatWorker(
      photoEnrichmentService,
      commonNameEnrichmentService,
      taxonomyEnrichmentService,
      _workRepository,
      photoCacheRepository,
      diagnostics: diagnostics,
      nameResolutionPort: nameResolutionPort,
      deckSpeciesMutationPort: deckSpeciesMutationPort,
      unresolvedNamesObserver: unresolvedNamesObserver,
    );
    if (autoInitialize) {
      unawaited(initialize());
    }
    _hostCooldownTracker.addListener(_handleHostCooldownChanged);
  }

  INatEnrichmentStatus get status => _status;

  DeckEnrichmentInfo deckInfo(String deckId) {
    return _deckInfoByDeckId[deckId] ??
        DeckEnrichmentInfo(
          // Derived the same way every other DeckEnrichmentInfo's status is
          // (_statusForState), rather than a separately hardcoded value that
          // could silently drift from what _statusForState maps `hidden` to.
          status: _statusForState(DeckEnrichmentState.hidden),
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
    await _pauseOwnedJobs();
    await _refreshState();
  }

  /// Pauses this instance's jobs, tolerating the DB having already been
  /// closed mid-flight (app shutdown, or - in integration tests - the next
  /// test's teardown deleting it out from under an unawaited caller such as
  /// [dispose]).
  Future<void> _pauseOwnedJobs() async {
    try {
      await _jobRepository.pauseJobsOwnedBy(_foregroundOwner);
    } on DatabaseException {
      // Nothing left to pause.
    }
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

    try {
      await _scheduleDeckEnrichmentUnguarded(
        normalizedDeckIds,
        includeINatPhotos: includeINatPhotos,
        includeCommonNames: includeCommonNames,
        coverImageUrlsByDeckId: coverImageUrlsByDeckId,
        unresolvedNamesByDeckId: unresolvedNamesByDeckId,
        waitForForegroundIdle: waitForForegroundIdle,
      );
    } on DatabaseException {
      // The user DB was closed while this was in flight (app shutdown, or -
      // in integration tests - the next test's teardown deleting the DB out
      // from under a still-running schedule call). Nothing left to schedule
      // against, so drop it instead of throwing - matches the same
      // reasoning as the DatabaseException guard in _refreshStateNow.
    }
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

    // Include already-tracked decks at lower priority. Without this,
    // assignSpeciesOwners would re-assign overlapping species to the new
    // deck even though another deck's work for them is still in flight.
    final newDeckIdSet = normalizedDeckIds.toSet();
    final existingDeckSpecies = await _workRepository
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

    final assignedSpeciesIdsByDeckId = await _workRepository
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
        await _workRepository.seedUnresolvedNames(
          deckId,
          unresolvedNames,
          wantsInatPhotos: includeINatPhotos,
          wantsCommonNames: includeCommonNames,
        );
      }
    }

    if (_processJobs &&
        !_isInForeground &&
        (await _jobRepository.hasPendingWork() ||
            await _workRepository.hasPendingWork())) {
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
    unawaited(_pauseOwnedJobs());
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
    await _recoverInterruptedWork();
    if (_disposed) return;
    await _pruneOrphanedWork();
    if (_disposed) return;
    _networkSubscription = _networkAvailability.onlineStatusChanges.listen(
      _handleNetworkStatusChanged,
    );
    await _refreshState();
    if (_disposed) return;
    _attachLifecycleObserver();
    _ensureForegroundRunner();
  }

  /// Startup crash recovery for [_workRepository]'s queue tables: any row
  /// left `running` by a process that died mid-claim (app kill, crash)
  /// would otherwise be invisible to both `claimBaseWorkBatch` and
  /// `claimNextINatWorkItem` (they only select `pending`/`retryScheduled`),
  /// permanently stranding that species. Cheap no-op when nothing was
  /// interrupted.
  Future<void> _recoverInterruptedWork() async {
    try {
      await _workRepository.recoverInterruptedWork();
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
      final trackedDeckIds = await _workRepository
          .loadAllDeckSpeciesSnapshots();
      for (final deckId in trackedDeckIds.keys) {
        if (validDeckIds.contains(deckId)) continue;
        await _workRepository.releaseDeck(deckId);
      }
    } catch (error) {
      _log.warn('Pruning orphaned enrichment work failed: $error');
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
      _projectionsByDeckId.remove(deckId);
      _deckInfoByDeckId.remove(deckId);
      _sessionAttemptedAtByDeckId.remove(deckId);
      _sessionCompletedAtByDeckId.remove(deckId);
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
      // The three workers each drain their own queue independently inside
      // the current pass's Future.wait — one of them (e.g. INatWorker) may
      // have already found nothing claimable and returned while another is
      // still busy, so newly-scheduled work meant for the already-idle one
      // is not guaranteed to be picked up by this still-running pass. Flag
      // it to be picked up by a fresh pass as soon as the current one exits
      // instead of only relying on some unrelated future trigger (app
      // resume, network change, another schedule call) to notice it.
      _log.debug('Foreground runner already active, will restart when idle');
      _restartForegroundRunnerWhenIdle = true;
      return;
    }
    _log.debug('Start foreground runner');
    _foregroundRunner = _runForegroundJobs();
  }

  Future<void> _runForegroundJobs() async {
    try {
      _log.debug('Foreground runner enter owner=$_foregroundOwner');
      bool shouldStop() =>
          _disposed ||
          _interactiveHoldCount > 0 ||
          !_networkAvailability.isOnline;
      await Future.wait([
        _coverRunner.runUntilIdle(
          owner: _foregroundOwner,
          runnerKind: EnrichmentRunnerKind.foreground,
          shouldStop: shouldStop,
        ),
        _baseWorker.runUntilIdle(
          shouldStop: shouldStop,
          onProgress: _notifyProgress,
        ),
        _iNatWorker.runUntilIdle(
          shouldStop: shouldStop,
          onProgress: _notifyProgress,
          onDecksNeedForcedReload: _handleDecksNeedForcedReload,
        ),
      ]);
    } finally {
      _foregroundRunner = null;
      _log.debug('Foreground runner exit owner=$_foregroundOwner');
      if (!_disposed) {
        await _refreshState();
        if (_interactiveHoldCount == 0 && _restartForegroundRunnerWhenIdle) {
          _restartForegroundRunnerWhenIdle = false;
          _ensureForegroundRunner();
        }
      }
    }
  }

  /// Fired by `BaseWorker`/`INatWorker` after each single species/item they
  /// process, so deck-card progress moves live during a long batch instead
  /// of jumping only once the whole foreground-runner pass finishes.
  /// Unawaited and safe to call at high frequency: `_refreshState` already
  /// coalesces concurrent/overlapping calls into a single drain loop and
  /// only notifies listeners when something actually changed.
  void _notifyProgress() {
    if (_disposed) return;
    unawaited(_refreshState());
  }

  /// Fired by `INatWorker` with any deck ids whose last tracked species was
  /// just pruned (see [_forcedProjectionReloadDeckIds]'s doc comment for
  /// why this can't rely on the normal delta poll).
  void _handleDecksNeedForcedReload(Set<String> deckIds) {
    if (_disposed || deckIds.isEmpty) return;
    _forcedProjectionReloadDeckIds.addAll(deckIds);
    unawaited(_refreshState());
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
    // Only (re-)load rows that actually changed since the last poll —
    // decks with no new activity never change again, so re-reading and
    // re-parsing the full history on every checkpoint would only get more
    // expensive the longer the app is used. Changed rows are merged into
    // the existing in-memory maps rather than replacing them.
    // Snapshotted (not cleared) up front — only removed from the source set
    // once actually reloaded below, so a query failure below leaves them in
    // place for the next call to retry instead of silently dropping them.
    final forcedDeckIds = Set<String>.of(_forcedProjectionReloadDeckIds);

    final List<EnrichmentJobRecord> changedJobs;
    final Set<String> changedWorkDeckIds;
    try {
      changedJobs = await _jobRepository.loadJobsUpdatedSince(
        _jobsSyncedThrough,
      );
      final workQueryStartedAt = DateTime.now();
      changedWorkDeckIds = await _workRepository.loadDeckIdsUpdatedSince(
        _workSyncedThrough.millisecondsSinceEpoch,
      );
      _workSyncedThrough = workQueryStartedAt;
    } on DatabaseException {
      // The user DB was closed while this refresh was in flight (app
      // shutdown, or - in integration tests - the next test's teardown
      // deleting the DB out from under a still-running refresh). Nothing
      // to sync against anymore, so drop this cycle instead of throwing.
      return;
    } on TimeoutException {
      // The user DB open itself timed out (DatabaseHelper._openTimeout,
      // guarding against a wedged native handle) rather than a
      // already-open DB getting closed mid-flight — same "nothing to sync
      // against" outcome, just from a different failure point. Left
      // uncaught, this would abort _initialize() before it ever attaches
      // the lifecycle observer or starts the foreground runner.
      return;
    }
    if (_disposed) return;
    for (final job in changedJobs) {
      _jobsByDeckId[job.deckId] = job;
      if (job.updatedAt.isAfter(_jobsSyncedThrough)) {
        _jobsSyncedThrough = job.updatedAt;
      }
    }
    // Forced ids are unioned in here (not just appended to changedWorkDeckIds
    // above) so a deck already present in both sets is only reloaded once.
    final deckIdsToReload = {...changedWorkDeckIds, ...forcedDeckIds};
    for (final deckId in deckIdsToReload) {
      try {
        _projectionsByDeckId[deckId] = await _workRepository.loadDeckProjection(
          deckId,
        );
      } on DatabaseException {
        return;
      } on TimeoutException {
        return;
      }
    }
    _forcedProjectionReloadDeckIds.removeAll(forcedDeckIds);

    final allDeckIds = {..._jobsByDeckId.keys, ..._projectionsByDeckId.keys};
    final snapshots = [for (final deckId in allDeckIds) _snapshotFor(deckId)];
    final nextStatus = _deriveStatus(snapshots);
    _syncCooldownActiveSince(nextStatus.hasActiveHostCooldown);
    _syncPauseDisplayTimers(snapshots);
    final nextDeckInfoByDeckId = _deriveDeckInfoByDeckId(
      snapshots,
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
      'Refresh queue state decks=${snapshots.length} '
      'immediatePending=${snapshots.where((d) => d.hasImmediatePendingWork).length} '
      'pending=${snapshots.where((d) => d.hasPendingWork).length}',
    );
    await _syncForegroundServiceKeeper();
    await _syncBackgroundNotificationContent();
    // Re-checked here (not just at entry) because this function is reached
    // via several await points (the delta queries, the projection-reload
    // loop, the two syncs just above) — dispose() (e.g. a test's tearDown
    // racing a still-in-flight onProgress-triggered refresh) can land in any
    // of those gaps. ChangeNotifier asserts in debug mode if notifyListeners
    // is called after dispose, so this has to be the last check before it.
    if (_disposed) return;
    notifyListeners();
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

  void _handleNetworkStatusChanged(bool isOnline) {
    if (_disposed) return;
    _log.debug('Network status changed: ${isOnline ? 'online' : 'offline'}');
    if (isOnline) {
      _ensureForegroundRunner();
    }
    // When going offline the running workers' shouldStop will return true
    // at their next loop iteration, stopping them without explicit action.
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

  INatEnrichmentStatus _deriveStatus(List<DeckWorkSnapshot> snapshots) {
    return deriveEnrichmentStatus(
      snapshots,
      hasActiveHostCooldown: _hostCooldownTracker.hasActiveCooldown,
      preferBackgroundMessaging: !_isInForeground,
    );
  }

  Map<String, DeckEnrichmentInfo> _deriveDeckInfoByDeckId(
    Iterable<DeckWorkSnapshot> snapshots, {
    required bool hasActiveHostCooldown,
  }) {
    return {
      for (final snapshot in snapshots)
        snapshot.deckId: _buildDeckInfo(
          snapshot,
          hasActiveHostCooldown: hasActiveHostCooldown,
        ),
    };
  }

  DeckEnrichmentInfo _buildDeckInfo(
    DeckWorkSnapshot snapshot, {
    required bool hasActiveHostCooldown,
  }) {
    final state = computeDeckEnrichmentState(
      coverJob: snapshot.coverJob,
      projection: snapshot.projection,
      hasActiveHostCooldown: hasActiveHostCooldown,
      cooldownActiveSince: _cooldownActiveSince,
      cooldownDisplayThreshold: cooldownDisplayThreshold,
      pauseDisplayThreshold: pauseDisplayThreshold,
    );
    final progress = deriveDisplayedProgress(snapshot);
    return DeckEnrichmentInfo(
      status: _statusForState(state),
      state: state,
      lastCompletedAt: _resolveLastCompletedAt(snapshot, state),
      lastAttemptedAt: _resolveLastAttemptedAt(snapshot, state),
      includesINatPhotos: snapshot.projection.wantsInatPhotosSpeciesCount > 0,
      includesCommonNames: snapshot.projection.wantsCommonNamesSpeciesCount > 0,
      progressCompleted: progress.completed,
      progressTotal: progress.total,
      isReady: isReadyForDeck(snapshot.projection),
      hasActiveHostCooldown: hasActiveHostCooldown,
      imageStagesComplete: snapshot.projection.imageStagesComplete,
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
    final allDeckIds = {..._jobsByDeckId.keys, ..._projectionsByDeckId.keys};
    final snapshots = [for (final deckId in allDeckIds) _snapshotFor(deckId)];
    final nextDeckInfoByDeckId = _deriveDeckInfoByDeckId(
      snapshots,
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
    // See the matching check in _refreshStateNow for why this is re-checked
    // here rather than trusting the entry check at the top of this function.
    if (_disposed) return;
    notifyListeners();
    // When the cooldown clears, retryScheduled jobs/work can run again.
    // Reset their next_attempt_at so the workers pick them up immediately,
    // then restart the foreground runner.
    if (cooldownJustCleared) {
      try {
        await _jobRepository.clearRetryAttemptForRetryScheduledJobs();
        await _workRepository.clearRetryAttemptForRetryScheduledWorkItems();
      } on DatabaseException {
        // DB torn down mid-flight (this runs fire-and-forget off a cooldown
        // timer/network callback) - nothing left to clear.
        return;
      }
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

  void _syncPauseDisplayTimers(Iterable<DeckWorkSnapshot> snapshots) {
    final now = DateTime.now();
    final wantedDeckIds = <String>{};
    for (final snapshot in snapshots) {
      final nextAttemptAt = earliestDeckRetryAt(
        snapshot.coverJob,
        snapshot.projection,
      );
      if (nextAttemptAt == null) continue;
      final delta = nextAttemptAt.difference(now);
      if (delta <= pauseDisplayThreshold) continue;
      wantedDeckIds.add(snapshot.deckId);
      if (_pauseDisplayTimers.containsKey(snapshot.deckId)) continue;
      final fireDelay = delta - pauseDisplayThreshold;
      _pauseDisplayTimers[snapshot.deckId] = Timer(fireDelay, () {
        _pauseDisplayTimers.remove(snapshot.deckId);
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
