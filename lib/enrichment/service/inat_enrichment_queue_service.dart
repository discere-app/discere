import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/service/enrichment_progress_status.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/util/logger.dart';

import 'enrichment_background_scheduler.dart';
import 'enrichment_job_executor.dart';
import 'enrichment_job_ports.dart';
import 'enrichment_service.dart';
export 'enrichment_progress_status.dart';

class DeckEnrichmentInfo {
  final EnrichmentJobStatus status;
  final DateTime? lastCompletedAt;
  final DateTime? lastAttemptedAt;
  final INatEnrichmentPhase? currentPhase;
  final String? lastError;
  final EnrichmentFailureKind? failureKind;
  final List<String> stillUnresolvedNames;
  final bool includesINatPhotos;
  final bool includesCommonNames;
  final int progressCompleted;
  final int progressTotal;
  final bool isQuickPassReady;
  final bool hasActiveHostCooldown;

  const DeckEnrichmentInfo({
    required this.status,
    required this.lastCompletedAt,
    required this.lastAttemptedAt,
    this.currentPhase,
    this.lastError,
    this.failureKind,
    this.stillUnresolvedNames = const [],
    this.includesINatPhotos = false,
    this.includesCommonNames = false,
    this.progressCompleted = 0,
    this.progressTotal = 0,
    this.isQuickPassReady = false,
    this.hasActiveHostCooldown = false,
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
        other.lastCompletedAt == lastCompletedAt &&
        other.lastAttemptedAt == lastAttemptedAt &&
        other.currentPhase == currentPhase &&
        other.lastError == lastError &&
        other.failureKind == failureKind &&
        listEquals(other.stillUnresolvedNames, stillUnresolvedNames) &&
        other.includesINatPhotos == includesINatPhotos &&
        other.includesCommonNames == includesCommonNames &&
        other.progressCompleted == progressCompleted &&
        other.progressTotal == progressTotal &&
        other.isQuickPassReady == isQuickPassReady &&
        other.hasActiveHostCooldown == hasActiveHostCooldown;
  }

  @override
  int get hashCode => Object.hash(
    status,
    lastCompletedAt,
    lastAttemptedAt,
    currentPhase,
    lastError,
    failureKind,
    Object.hashAll(stillUnresolvedNames),
    includesINatPhotos,
    includesCommonNames,
    progressCompleted,
    progressTotal,
    isQuickPassReady,
    hasActiveHostCooldown,
  );
}

class INatEnrichmentQueueService extends ChangeNotifier {
  static final _log = Logger.forType(INatEnrichmentQueueService);
  final EnrichmentJobRepository _jobRepository;
  late final EnrichmentJobExecutor _executor;
  final EnrichmentBackgroundScheduler _backgroundScheduler;
  final DeckSpeciesSnapshotPort _deckSpeciesSnapshotPort;
  final NotificationService? _notificationService;
  final HostCooldownTracker _hostCooldownTracker;
  final String _foregroundOwner;
  final bool _processJobs;

  final Map<String, EnrichmentJobRecord> _jobsByDeckId =
      <String, EnrichmentJobRecord>{};

  INatEnrichmentStatus _status = INatEnrichmentStatus.idle;
  Future<void>? _foregroundRunner;
  Future<void>? _initializationFuture;
  Future<void> _lifecycleTransition = Future.value();
  _QueueLifecycleObserver? _lifecycleObserver;
  bool _isInForeground = true;
  bool _targetForeground = true;
  int _interactiveHoldCount = 0;
  bool _restartForegroundRunnerWhenIdle = false;
  bool _disposed = false;

  INatEnrichmentQueueService(
    EnrichmentService enrichmentService, {
    required DeckSpeciesSnapshotPort deckSpeciesSnapshotPort,
    required DeckCoverStorePort deckCoverStore,
    required ImageService imageService,
    ScientificNameResolutionPort? nameResolutionPort,
    DeckSpeciesMutationPort? deckSpeciesMutationPort,
    UnresolvedNamesObserverPort? unresolvedNamesObserver,
    NotificationService? notificationService,
    EnrichmentJobRepository? jobRepository,
    EnrichmentBackgroundScheduler? backgroundScheduler,
    HostCooldownTracker? hostCooldownTracker,
    bool autoInitialize = true,
    bool processJobs = true,
  }) : _jobRepository = jobRepository ?? EnrichmentJobRepository(),
       _backgroundScheduler =
           backgroundScheduler ?? const NoopEnrichmentBackgroundScheduler(),
       _deckSpeciesSnapshotPort = deckSpeciesSnapshotPort,
       _notificationService = notificationService,
       _hostCooldownTracker =
           hostCooldownTracker ?? HostCooldownTracker.instance,
       _processJobs = processJobs,
       _foregroundOwner =
           'foreground-${DateTime.now().microsecondsSinceEpoch}' {
    _executor = EnrichmentJobExecutor(
      enrichmentService,
      _jobRepository,
      deckCoverStore: deckCoverStore,
      imageService: imageService,
      nameResolutionPort: nameResolutionPort,
      deckSpeciesMutationPort: deckSpeciesMutationPort,
      unresolvedNamesObserver: unresolvedNamesObserver,
      onStateChanged: _refreshState,
    );
    if (autoInitialize) {
      unawaited(initialize());
    }
    _hostCooldownTracker.addListener(_handleHostCooldownChanged);
  }

  INatEnrichmentStatus get status => _status;

  DeckEnrichmentInfo deckInfo(String deckId) {
    final job = _jobsByDeckId[deckId];
    if (job == null) {
      return const DeckEnrichmentInfo(
        status: EnrichmentJobStatus.completed,
        lastCompletedAt: null,
        lastAttemptedAt: null,
      );
    }

    return DeckEnrichmentInfo(
      status: job.status,
      lastCompletedAt: job.completedAt,
      lastAttemptedAt: job.attemptedAt,
      currentPhase: _phaseForStage(
        job.currentStage ?? _jobRepository.nextRunnableStage(job),
      ),
      lastError: job.lastError,
      failureKind: switch (job.failureKind) {
        'temporary' => EnrichmentFailureKind.temporary,
        'permanent' => EnrichmentFailureKind.permanent,
        _ => null,
      },
      stillUnresolvedNames: job.payload.stillUnresolvedNames,
      includesINatPhotos: job.payload.includeINatPhotos,
      includesCommonNames: job.payload.includeCommonNames,
      progressCompleted: job.progressCompleted,
      progressTotal: job.progressTotal,
      isQuickPassReady: isQuickPassReadyForJob(job),
      hasActiveHostCooldown: _hostCooldownTracker.hasActiveCooldown,
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
    final normalizedDeckIds = deckIds
        .map((deckId) => deckId.trim())
        .where((deckId) => deckId.isNotEmpty)
        .toSet();
    if (normalizedDeckIds.isEmpty) return;

    for (final deckId in normalizedDeckIds) {
      final speciesIds = await _deckSpeciesSnapshotPort.loadSpeciesIdsForDecks({
        deckId,
      });
      await _jobRepository.scheduleDeckJob(
        deckId: deckId,
        speciesIds: speciesIds,
        includeINatPhotos: includeINatPhotos,
        includeCommonNames: includeCommonNames,
        coverImageUrl: coverImageUrlsByDeckId[deckId],
        unresolvedSpeciesNames: unresolvedNamesByDeckId[deckId] ?? const [],
      );
    }

    if (_processJobs &&
        !_isInForeground &&
        await _jobRepository.hasPendingWork()) {
      await _backgroundScheduler.scheduleProcessing(expedited: true);
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
    _hostCooldownTracker.removeListener(_handleHostCooldownChanged);
    _log.debug('Dispose queue service foregroundOwner=$_foregroundOwner');
    unawaited(_jobRepository.pauseJobsOwnedBy(_foregroundOwner));
    super.dispose();
  }

  Future<void> _initialize() async {
    _log.debug('Initialize queue service foregroundOwner=$_foregroundOwner');
    await _backgroundScheduler.initialize();
    if (_disposed) return;
    await _refreshState();
    if (_disposed) return;
    _attachLifecycleObserver();
    _ensureForegroundRunner();
  }

  Future<void> _cancelDeckEnrichment(String deckId) async {
    try {
      await _jobRepository.cancelDeckJob(deckId);
      await _backgroundScheduler.cancelProcessingForDeck(deckId);
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
    if (_foregroundRunner != null) {
      _restartForegroundRunnerWhenIdle = true;
      return;
    }
    _ensureForegroundRunner();
  }

  Future<void> _onBackgrounded() async {
    _log.debug('Queue backgrounded');
    _restartForegroundRunnerWhenIdle = false;
    await _jobRepository.pauseJobsOwnedBy(_foregroundOwner);
    if (_processJobs && await _jobRepository.hasPendingWork()) {
      await _backgroundScheduler.scheduleProcessing(expedited: true);
    }
    await _refreshState();
  }

  void _ensureForegroundRunner() {
    if (!_processJobs) return;
    if (!_isInForeground) return;
    if (_interactiveHoldCount > 0) {
      _log.debug(
        'Skip foreground runner start because interactive priority is active',
      );
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
            _disposed || !_isInForeground || _interactiveHoldCount > 0,
      );
    } finally {
      _foregroundRunner = null;
      _log.debug('Foreground runner exit owner=$_foregroundOwner');
      if (!_disposed) {
        await _refreshState();
        if (_isInForeground &&
            _interactiveHoldCount == 0 &&
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
    final jobs = await _jobRepository.loadAllJobs();
    if (_disposed) return;
    _jobsByDeckId
      ..clear()
      ..addEntries(jobs.map((job) => MapEntry(job.deckId, job)));
    _status = _deriveStatus(jobs);
    _log.debug(
      'Refresh queue state jobs=${jobs.length} '
      'running=${jobs.where((job) => job.status == EnrichmentJobStatus.runningForeground || job.status == EnrichmentJobStatus.runningBackground).length} '
      'pending=${jobs.where((job) => job.hasPendingWork).length}',
    );
    await _syncProgressNotification();
    notifyListeners();
  }

  INatEnrichmentStatus _deriveStatus(List<EnrichmentJobRecord> jobs) {
    return deriveEnrichmentStatus(
      jobs,
      hasActiveHostCooldown: _hostCooldownTracker.hasActiveCooldown,
    );
  }

  INatEnrichmentPhase? _phaseForStage(EnrichmentStage? stage) {
    return phaseForEnrichmentStage(stage);
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

  Future<void> _syncProgressNotification() async {
    final service = _notificationService;
    if (service == null) return;
    if (_status.hasPendingWork) {
      await service.showEnrichmentProgress(_status);
    } else {
      await service.cancelEnrichmentProgress();
    }
  }

  void _handleHostCooldownChanged() {
    unawaited(_syncCooldownStatus());
  }

  Future<void> _syncCooldownStatus() async {
    if (_disposed) return;
    final hasActiveHostCooldown = _hostCooldownTracker.hasActiveCooldown;
    if (_status.hasActiveHostCooldown == hasActiveHostCooldown) {
      return;
    }
    _status = _status.copyWith(hasActiveHostCooldown: hasActiveHostCooldown);
    await _syncProgressNotification();
    notifyListeners();
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
