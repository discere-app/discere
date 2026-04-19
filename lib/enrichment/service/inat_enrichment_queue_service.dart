import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/util/logger.dart';

import 'enrichment_background_scheduler.dart';
import 'enrichment_job_executor.dart';
import 'enrichment_job_ports.dart';
import 'enrichment_service.dart';

enum INatEnrichmentPhase { idle, nameResolution, cover, base, inat, names }

class DeckEnrichmentInfo {
  final EnrichmentJobStatus status;
  final DateTime? lastCompletedAt;
  final DateTime? lastAttemptedAt;
  final INatEnrichmentPhase? currentPhase;
  final String? lastError;
  final EnrichmentFailureKind? failureKind;
  final List<String> stillUnresolvedNames;

  const DeckEnrichmentInfo({
    required this.status,
    required this.lastCompletedAt,
    required this.lastAttemptedAt,
    this.currentPhase,
    this.lastError,
    this.failureKind,
    this.stillUnresolvedNames = const [],
  });

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
        listEquals(other.stillUnresolvedNames, stillUnresolvedNames);
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
  );
}

class INatEnrichmentStatus {
  final bool isRunning;
  final INatEnrichmentPhase phase;
  final int completed;
  final int total;
  final int activeDeckCount;

  const INatEnrichmentStatus({
    required this.isRunning,
    required this.phase,
    required this.completed,
    required this.total,
    this.activeDeckCount = 0,
  });

  static const idle = INatEnrichmentStatus(
    isRunning: false,
    phase: INatEnrichmentPhase.idle,
    completed: 0,
    total: 0,
    activeDeckCount: 0,
  );

  @override
  bool operator ==(Object other) {
    return other is INatEnrichmentStatus &&
        other.isRunning == isRunning &&
        other.phase == phase &&
        other.completed == completed &&
        other.total == total &&
        other.activeDeckCount == activeDeckCount;
  }

  @override
  int get hashCode =>
      Object.hash(isRunning, phase, completed, total, activeDeckCount);
}

class INatEnrichmentQueueService extends ChangeNotifier {
  static final _log = Logger.forType(INatEnrichmentQueueService);
  final EnrichmentJobRepository _jobRepository;
  late final EnrichmentJobExecutor _executor;
  final EnrichmentBackgroundScheduler _backgroundScheduler;
  final DeckSpeciesSnapshotPort _deckSpeciesSnapshotPort;
  final String _foregroundOwner;

  final Map<String, EnrichmentJobRecord> _jobsByDeckId =
      <String, EnrichmentJobRecord>{};

  INatEnrichmentStatus _status = INatEnrichmentStatus.idle;
  Future<void>? _foregroundRunner;
  _QueueLifecycleObserver? _lifecycleObserver;

  INatEnrichmentQueueService(
    EnrichmentService enrichmentService, {
    required DeckSpeciesSnapshotPort deckSpeciesSnapshotPort,
    required DeckCoverStorePort deckCoverStore,
    required ImageService imageService,
    ScientificNameResolutionPort? nameResolutionPort,
    DeckSpeciesMutationPort? deckSpeciesMutationPort,
    UnresolvedNamesObserverPort? unresolvedNamesObserver,
    EnrichmentJobRepository? jobRepository,
    EnrichmentBackgroundScheduler? backgroundScheduler,
  }) : _jobRepository = jobRepository ?? EnrichmentJobRepository(),
       _backgroundScheduler =
           backgroundScheduler ?? const NoopEnrichmentBackgroundScheduler(),
       _deckSpeciesSnapshotPort = deckSpeciesSnapshotPort,
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
    unawaited(_initialize());
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
      currentPhase: _phaseForStage(job.currentStage),
      lastError: job.lastError,
      failureKind: switch (job.failureKind) {
        'temporary' => EnrichmentFailureKind.temporary,
        'permanent' => EnrichmentFailureKind.permanent,
        _ => null,
      },
      stillUnresolvedNames: job.payload.stillUnresolvedNames,
    );
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

    await _backgroundScheduler.scheduleProcessing();
    await _refreshState();
    _ensureForegroundRunner();
    if (waitForForegroundIdle) {
      await _awaitForegroundIdle();
    }
  }

  void cancelDeckEnrichment(String deckId) {
    _log.debug('Cancel enrichment requested deck=$deckId');
    unawaited(_cancelDeckEnrichment(deckId));
  }

  @override
  void dispose() {
    _detachLifecycleObserver();
    _log.debug('Dispose queue service foregroundOwner=$_foregroundOwner');
    unawaited(_jobRepository.pauseJobsOwnedBy(_foregroundOwner));
    super.dispose();
  }

  Future<void> _initialize() async {
    _log.debug('Initialize queue service foregroundOwner=$_foregroundOwner');
    await _backgroundScheduler.initialize();
    await _refreshState();
    _attachLifecycleObserver();
    _ensureForegroundRunner();
  }

  Future<void> _cancelDeckEnrichment(String deckId) async {
    await _jobRepository.cancelDeckJob(deckId);
    await _backgroundScheduler.cancelProcessingForDeck(deckId);
    await _refreshState();
  }

  void _handleAppLifecycleState(AppLifecycleState state) {
    _log.debug('Lifecycle state changed: $state');
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_onResumed());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_onBackgrounded());
        break;
    }
  }

  Future<void> _onResumed() async {
    _log.debug('Queue resumed');
    await _refreshState();
    _ensureForegroundRunner();
  }

  Future<void> _onBackgrounded() async {
    _log.debug('Queue backgrounded');
    await _jobRepository.pauseJobsOwnedBy(_foregroundOwner);
    await _backgroundScheduler.scheduleProcessing();
    await _refreshState();
  }

  void _ensureForegroundRunner() {
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
      );
    } finally {
      _foregroundRunner = null;
      _log.debug('Foreground runner exit owner=$_foregroundOwner');
      await _refreshState();
    }
  }

  Future<void> _awaitForegroundIdle() async {
    while (_foregroundRunner != null) {
      await _foregroundRunner;
    }
  }

  Future<void> _refreshState() async {
    final jobs = await _jobRepository.loadAllJobs();
    _jobsByDeckId
      ..clear()
      ..addEntries(jobs.map((job) => MapEntry(job.deckId, job)));
    _status = _deriveStatus(jobs);
    _log.debug(
      'Refresh queue state jobs=${jobs.length} '
      'running=${jobs.where((job) => job.status == EnrichmentJobStatus.runningForeground || job.status == EnrichmentJobStatus.runningBackground).length} '
      'pending=${jobs.where((job) => job.hasPendingWork).length}',
    );
    notifyListeners();
  }

  INatEnrichmentStatus _deriveStatus(List<EnrichmentJobRecord> jobs) {
    final runningJobs = jobs.where((job) {
      return job.status == EnrichmentJobStatus.runningForeground ||
          job.status == EnrichmentJobStatus.runningBackground;
    }).toList();
    if (runningJobs.isEmpty) return INatEnrichmentStatus.idle;

    final activeJob = runningJobs.first;
    return INatEnrichmentStatus(
      isRunning: true,
      phase: _phaseForStage(activeJob.currentStage) ?? INatEnrichmentPhase.base,
      completed: activeJob.progressCompleted,
      total: activeJob.progressTotal,
      activeDeckCount: runningJobs.length,
    );
  }

  INatEnrichmentPhase? _phaseForStage(EnrichmentStage? stage) {
    return switch (stage) {
      EnrichmentStage.nameResolution => INatEnrichmentPhase.nameResolution,
      EnrichmentStage.cover => INatEnrichmentPhase.cover,
      EnrichmentStage.base => INatEnrichmentPhase.base,
      EnrichmentStage.inatPrimary ||
      EnrichmentStage.inatBackfill => INatEnrichmentPhase.inat,
      EnrichmentStage.names => INatEnrichmentPhase.names,
      null => null,
    };
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
}

class _QueueLifecycleObserver with WidgetsBindingObserver {
  final INatEnrichmentQueueService _service;

  _QueueLifecycleObserver(this._service);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _service._handleAppLifecycleState(state);
  }
}
