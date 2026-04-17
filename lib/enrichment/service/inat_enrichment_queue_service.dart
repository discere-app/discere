import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/util/logger.dart';

import 'enrichment_service.dart';

typedef DeckSpeciesResolver = Future<Set<String>> Function(Set<String> deckIds);
typedef DeckCoverPathUpdater = Future<void> Function(String deckId, String localPath);
typedef UnresolvedNamesResolver = Future<Map<String, String>> Function(List<String> names);
typedef DeckSpeciesAdder = Future<void> Function(String deckId, Set<String> speciesIds);
typedef UnresolvedNamesNotifier = void Function(String deckId, List<String> stillUnresolved);

enum EnrichmentFailureKind { temporary, permanent }

EnrichmentFailureKind _classifyFailure(Object error) {
  if (error is TimeoutException) return EnrichmentFailureKind.temporary;
  if (error is SocketException) return EnrichmentFailureKind.temporary;
  if (error is http.ClientException) return EnrichmentFailureKind.temporary;
  if (error is HttpDownloadException) {
    return error.isRetryable
        ? EnrichmentFailureKind.temporary
        : EnrichmentFailureKind.permanent;
  }
  return EnrichmentFailureKind.permanent;
}

enum INatEnrichmentPhase { idle, nameResolution, cover, base, inat, names }

class DeckEnrichmentInfo {
  final bool isActive;
  final bool hasPendingWork;
  final INatEnrichmentPhase? currentPhase;
  final DateTime? lastCompletedAt;
  final DateTime? lastAttemptedAt;
  final String? lastError;
  final EnrichmentFailureKind? failureKind;
  /// Species names that could not be resolved even after iNaturalist lookup.
  final List<String> stillUnresolvedNames;

  const DeckEnrichmentInfo({
    required this.isActive,
    required this.lastCompletedAt,
    required this.lastAttemptedAt,
    this.hasPendingWork = false,
    this.currentPhase,
    this.lastError,
    this.failureKind,
    this.stillUnresolvedNames = const [],
  });

  bool get hasFailedAttempt =>
      lastAttemptedAt != null &&
      (lastCompletedAt == null || lastAttemptedAt!.isAfter(lastCompletedAt!));

  @override
  bool operator ==(Object other) {
    return other is DeckEnrichmentInfo &&
        other.isActive == isActive &&
        other.hasPendingWork == hasPendingWork &&
        other.currentPhase == currentPhase &&
        other.lastCompletedAt == lastCompletedAt &&
        other.lastAttemptedAt == lastAttemptedAt &&
        other.lastError == lastError &&
        other.failureKind == failureKind &&
        _listEquals(other.stillUnresolvedNames, stillUnresolvedNames);
  }

  @override
  int get hashCode => Object.hash(
    isActive,
    hasPendingWork,
    currentPhase,
    lastCompletedAt,
    lastAttemptedAt,
    lastError,
    failureKind,
    Object.hashAll(stillUnresolvedNames),
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
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

enum _DeckEnrichmentStage { nameResolution, cover, base, inatPrimary, names, inatBackfill }

enum _DeckEnrichmentStageState { pending, running, succeeded, failed, skipped }

class _DeckStageSelection {
  final _DeckEnrichmentJob job;
  final _DeckEnrichmentStage stage;

  const _DeckStageSelection(this.job, this.stage);
}

class _DeckEnrichmentJob {
  final String deckId;
  final Map<_DeckEnrichmentStage, _DeckEnrichmentStageState> stageStates;
  String? coverImageUrl;
  String? lastError;
  EnrichmentFailureKind? lastFailureKind;
  DateTime updatedAt;
  /// Species names to resolve via iNaturalist in the background.
  List<String> unresolvedSpeciesNames;
  /// Species names that could not be resolved even after iNaturalist lookup.
  List<String> stillUnresolvedNames;
  /// Species-level progress for the currently running stage.
  int speciesCompleted = 0;
  int speciesTotal = 0;

  _DeckEnrichmentJob({
    required this.deckId,
    required this.stageStates,
    required this.updatedAt,
    this.coverImageUrl,
    this.lastError,
    this.lastFailureKind,
    this.unresolvedSpeciesNames = const [],
    this.stillUnresolvedNames = const [],
  });

  factory _DeckEnrichmentJob.create(String deckId) {
    return _DeckEnrichmentJob(
      deckId: deckId,
      updatedAt: DateTime.now(),
      stageStates: {
        for (final stage in _DeckEnrichmentStage.values)
          stage: _DeckEnrichmentStageState.skipped,
      },
    );
  }

  factory _DeckEnrichmentJob.fromJson(Map<String, dynamic> json) {
    final rawStageStates = (json['stageStates'] as Map<String, dynamic>? ?? {});
    final stageStates = <_DeckEnrichmentStage, _DeckEnrichmentStageState>{};

    for (final stage in _DeckEnrichmentStage.values) {
      final rawValue = rawStageStates[stage.name] as String?;
      stageStates[stage] = _DeckEnrichmentStageState.values.byName(
        rawValue ?? 'skipped',
      );
    }

    final rawFailureKind = json['lastFailureKind'] as String?;
    return _DeckEnrichmentJob(
      deckId: json['deckId'] as String,
      coverImageUrl: json['coverImageUrl'] as String?,
      lastError: json['lastError'] as String?,
      lastFailureKind: rawFailureKind != null
          ? EnrichmentFailureKind.values.byName(rawFailureKind)
          : null,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['updatedAt'] as int? ?? 0,
      ),
      stageStates: stageStates,
      unresolvedSpeciesNames: (json['unresolvedSpeciesNames'] as List<dynamic>?)
              ?.cast<String>() ??
          const [],
      stillUnresolvedNames: (json['stillUnresolvedNames'] as List<dynamic>?)
              ?.cast<String>() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'deckId': deckId,
    'coverImageUrl': coverImageUrl,
    'lastError': lastError,
    'lastFailureKind': lastFailureKind?.name,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'stageStates': {
      for (final entry in stageStates.entries) entry.key.name: entry.value.name,
    },
    if (unresolvedSpeciesNames.isNotEmpty)
      'unresolvedSpeciesNames': unresolvedSpeciesNames,
    if (stillUnresolvedNames.isNotEmpty)
      'stillUnresolvedNames': stillUnresolvedNames,
  };

  bool get isActive =>
      stageStates.values.contains(_DeckEnrichmentStageState.running);

  bool get hasPendingWork => stageStates.values.any(
    (state) =>
        state == _DeckEnrichmentStageState.pending ||
        state == _DeckEnrichmentStageState.running,
  );

  bool get hasFailedStage =>
      stageStates.values.contains(_DeckEnrichmentStageState.failed);

  INatEnrichmentPhase? get currentPhase {
    if (_stateFor(_DeckEnrichmentStage.nameResolution) ==
        _DeckEnrichmentStageState.running) {
      return INatEnrichmentPhase.nameResolution;
    }
    if (_stateFor(_DeckEnrichmentStage.cover) ==
        _DeckEnrichmentStageState.running) {
      return INatEnrichmentPhase.cover;
    }
    if (_stateFor(_DeckEnrichmentStage.base) ==
        _DeckEnrichmentStageState.running) {
      return INatEnrichmentPhase.base;
    }
    if (_stateFor(_DeckEnrichmentStage.inatPrimary) ==
            _DeckEnrichmentStageState.running ||
        _stateFor(_DeckEnrichmentStage.inatBackfill) ==
            _DeckEnrichmentStageState.running) {
      return INatEnrichmentPhase.inat;
    }
    if (_stateFor(_DeckEnrichmentStage.names) ==
        _DeckEnrichmentStageState.running) {
      return INatEnrichmentPhase.names;
    }
    return null;
  }

  bool hasScheduledStageForPhase(INatEnrichmentPhase phase) {
    return switch (phase) {
      INatEnrichmentPhase.idle => false,
      INatEnrichmentPhase.nameResolution =>
        _isScheduled(_DeckEnrichmentStage.nameResolution),
      INatEnrichmentPhase.cover => _isScheduled(_DeckEnrichmentStage.cover),
      INatEnrichmentPhase.base => _isScheduled(_DeckEnrichmentStage.base),
      INatEnrichmentPhase.inat =>
        _isScheduled(_DeckEnrichmentStage.inatPrimary) ||
            _isScheduled(_DeckEnrichmentStage.inatBackfill),
      INatEnrichmentPhase.names => _isScheduled(_DeckEnrichmentStage.names),
    };
  }

  bool isPhaseFinished(INatEnrichmentPhase phase) {
    return switch (phase) {
      INatEnrichmentPhase.idle => true,
      INatEnrichmentPhase.nameResolution =>
        _isFinished(_DeckEnrichmentStage.nameResolution),
      INatEnrichmentPhase.cover => _isFinished(_DeckEnrichmentStage.cover),
      INatEnrichmentPhase.base => _isFinished(_DeckEnrichmentStage.base),
      INatEnrichmentPhase.inat =>
        _isFinished(_DeckEnrichmentStage.inatPrimary) &&
            _isFinished(_DeckEnrichmentStage.inatBackfill),
      INatEnrichmentPhase.names => _isFinished(_DeckEnrichmentStage.names),
    };
  }

  void scheduleNameResolution(List<String> names) {
    if (names.isEmpty) return;
    unresolvedSpeciesNames = List.of(names);
    _setPending(_DeckEnrichmentStage.nameResolution);
  }

  void scheduleCover(String? imageUrl) {
    final normalizedUrl = imageUrl?.trim();
    if (normalizedUrl == null || normalizedUrl.isEmpty) {
      return;
    }
    coverImageUrl = normalizedUrl;
    _setPending(_DeckEnrichmentStage.cover);
  }

  void scheduleBase() {
    _setPending(_DeckEnrichmentStage.base);
  }

  void scheduleINatPhotos() {
    _setPending(_DeckEnrichmentStage.inatPrimary);
    _setPending(_DeckEnrichmentStage.inatBackfill);
  }

  void scheduleCommonNames() {
    _setPending(_DeckEnrichmentStage.names);
  }

  void markRunning(_DeckEnrichmentStage stage) {
    stageStates[stage] = _DeckEnrichmentStageState.running;
    updatedAt = DateTime.now();
  }

  void markSucceeded(_DeckEnrichmentStage stage) {
    stageStates[stage] = _DeckEnrichmentStageState.succeeded;
    updatedAt = DateTime.now();
  }

  void markFailed(
    _DeckEnrichmentStage stage,
    Object error,
    EnrichmentFailureKind kind,
  ) {
    stageStates[stage] = _DeckEnrichmentStageState.failed;
    lastError = error.toString();
    lastFailureKind = kind;
    updatedAt = DateTime.now();
  }

  _DeckEnrichmentStageState stateFor(_DeckEnrichmentStage stage) =>
      _stateFor(stage);

  void _setPending(_DeckEnrichmentStage stage) {
    final current = _stateFor(stage);
    if (current == _DeckEnrichmentStageState.succeeded ||
        current == _DeckEnrichmentStageState.running) {
      return;
    }
    stageStates[stage] = _DeckEnrichmentStageState.pending;
    updatedAt = DateTime.now();
  }

  bool _isScheduled(_DeckEnrichmentStage stage) =>
      _stateFor(stage) != _DeckEnrichmentStageState.skipped;

  bool _isFinished(_DeckEnrichmentStage stage) {
    final state = _stateFor(stage);
    return state == _DeckEnrichmentStageState.succeeded ||
        state == _DeckEnrichmentStageState.failed ||
        state == _DeckEnrichmentStageState.skipped;
  }

  _DeckEnrichmentStageState _stateFor(_DeckEnrichmentStage stage) =>
      stageStates[stage] ?? _DeckEnrichmentStageState.skipped;
}

class INatEnrichmentQueueService extends ChangeNotifier {
  static final _log = Logger.forType(INatEnrichmentQueueService);
  // Cover and reference image downloads are not subject to API rate limits and
  // run fully in parallel; actual network concurrency is bounded by
  // ImageService._maxConcurrentDownloads.
  static const _backgroundINatMaxConcurrent = 1;
  static const _backgroundINatRequestSpacing = Duration(milliseconds: 1100);
  static const _completedAtPreferencePrefix = 'inat_enrichment_completed_at.';
  static const _attemptedAtPreferencePrefix = 'inat_enrichment_attempted_at.';
  static const _jobPreferencePrefix = 'inat_enrichment_job.';

  final EnrichmentService _enrichmentService;
  final DeckSpeciesResolver _resolveSpeciesIds;
  final DeckCoverPathUpdater _updateCoverPath;
  final ImageService _imageService;
  final SharedPreferences? _preferences;
  final UnresolvedNamesResolver? _resolveNames;
  final DeckSpeciesAdder? _addSpeciesToDeck;
  final UnresolvedNamesNotifier? _onNamesUnresolved;
  final Map<String, DateTime> _lastCompletedAtByDeckId = <String, DateTime>{};
  final Map<String, DateTime> _lastAttemptedAtByDeckId = <String, DateTime>{};
  final Map<String, _DeckEnrichmentJob> _jobsByDeckId =
      <String, _DeckEnrichmentJob>{};

  INatEnrichmentStatus _status = INatEnrichmentStatus.idle;
  Future<void>? _assetRunner;
  Future<void>? _inatRunner;
  _QueueLifecycleObserver? _lifecycleObserver;

  INatEnrichmentQueueService(
    this._enrichmentService, {
    required DeckSpeciesResolver resolveSpeciesIds,
    required DeckCoverPathUpdater updateCoverPath,
    required ImageService imageService,
    SharedPreferences? preferences,
    UnresolvedNamesResolver? resolveNames,
    DeckSpeciesAdder? addSpeciesToDeck,
    UnresolvedNamesNotifier? onNamesUnresolved,
  }) : _resolveSpeciesIds = resolveSpeciesIds,
       _updateCoverPath = updateCoverPath,
       _imageService = imageService,
       _preferences = preferences,
       _resolveNames = resolveNames,
       _addSpeciesToDeck = addSpeciesToDeck,
       _onNamesUnresolved = onNamesUnresolved {
    _restoreCompletionTimestamps();
    _restoreJobs();
    _attachLifecycleObserver();
    _ensureRunners();
    _emitState();
  }

  INatEnrichmentStatus get status => _status;

  DeckEnrichmentInfo deckInfo(String deckId) {
    final job = _jobsByDeckId[deckId];
    return DeckEnrichmentInfo(
      isActive: job?.isActive ?? false,
      hasPendingWork: job?.hasPendingWork ?? false,
      currentPhase: job?.currentPhase,
      lastCompletedAt: _lastCompletedAtByDeckId[deckId],
      lastAttemptedAt: _lastAttemptedAtByDeckId[deckId],
      lastError: job?.lastError,
      failureKind: job?.lastFailureKind,
      stillUnresolvedNames: job?.stillUnresolvedNames ?? const [],
    );
  }

  Future<void> scheduleDeckEnrichment(
    List<String> deckIds, {
    bool includeINatPhotos = true,
    bool includeCommonNames = true,
    Map<String, String?> coverImageUrlsByDeckId = const {},
    Map<String, List<String>> unresolvedNamesByDeckId = const {},
  }) {
    final normalizedDeckIds = deckIds
        .map((deckId) => deckId.trim())
        .where((deckId) => deckId.isNotEmpty)
        .toSet();
    if (normalizedDeckIds.isEmpty) {
      return Future.value();
    }

    for (final deckId in normalizedDeckIds) {
      final job = _jobsByDeckId.putIfAbsent(
        deckId,
        () => _DeckEnrichmentJob.create(deckId),
      );

      job.scheduleCover(coverImageUrlsByDeckId[deckId]);
      job.scheduleBase();
      final unresolvedNames = unresolvedNamesByDeckId[deckId] ?? [];
      if (unresolvedNames.isNotEmpty) {
        job.scheduleNameResolution(unresolvedNames);
      }
      if (includeINatPhotos) {
        job.scheduleINatPhotos();
      }
      if (includeCommonNames) {
        job.scheduleCommonNames();
      }
    }

    _persistJobs();
    _ensureRunners();
    _emitState();
    return _awaitIdle();
  }

  void _handleAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _ensureRunners();
        _emitState();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _persistJobs();
        break;
    }
  }

  /// Removes all enrichment state for the given deck.
  ///
  /// Running stages for this deck will complete but their results are discarded
  /// because the job is already removed from the map.
  void cancelDeckEnrichment(String deckId) {
    final removed = _jobsByDeckId.remove(deckId);
    if (removed == null) return;

    _lastCompletedAtByDeckId.remove(deckId);
    _lastAttemptedAtByDeckId.remove(deckId);
    _preferences?.remove('$_completedAtPreferencePrefix$deckId');
    _preferences?.remove('$_attemptedAtPreferencePrefix$deckId');
    _preferences?.remove('$_jobPreferencePrefix$deckId');
    _persistJobs();
    _emitState();
  }

  @override
  void dispose() {
    _detachLifecycleObserver();
    _persistJobs();
    super.dispose();
  }

  Future<void> _awaitIdle() async {
    while (_assetRunner != null || _inatRunner != null) {
      final activeRunners = <Future<void>>[];
      if (_assetRunner != null) {
        activeRunners.add(_assetRunner!);
      }
      if (_inatRunner != null) {
        activeRunners.add(_inatRunner!);
      }
      await Future.wait(activeRunners);
    }
  }

  void _ensureRunners() {
    if (_assetRunner == null && _hasRunnableAssetJobs) {
      _assetRunner = _runAssetJobs();
    }
    if (_inatRunner == null && _hasRunnableINatJobs) {
      _inatRunner = _runINatJobs();
    }
  }

  bool get _hasRunnableAssetJobs => _jobsByDeckId.values.any((job) {
    return _canRunStage(job, _DeckEnrichmentStage.cover) ||
        _canRunStage(job, _DeckEnrichmentStage.base);
  });

  bool get _hasRunnableINatJobs => _jobsByDeckId.values.any((job) {
    return _canRunStage(job, _DeckEnrichmentStage.nameResolution) ||
        _canRunStage(job, _DeckEnrichmentStage.inatPrimary) ||
        _canRunStage(job, _DeckEnrichmentStage.names) ||
        _canRunStage(job, _DeckEnrichmentStage.inatBackfill);
  });

  Future<void> _runAssetJobs() async {
    try {
      while (true) {
        final jobCount = _jobsByDeckId.length;
        final selections = <_DeckStageSelection>[
          ..._takeRunnableStageSelections(
            _DeckEnrichmentStage.cover,
            limit: jobCount,
          ),
          ..._takeRunnableStageSelections(
            _DeckEnrichmentStage.base,
            limit: jobCount,
          ),
        ];
        if (selections.isEmpty) break;

        await Future.wait(selections.map(_runStageSelection));
      }
    } finally {
      _assetRunner = null;
      _persistJobs();
      _ensureRunners();
      _emitState();
    }
  }

  Future<void> _runINatJobs() async {
    try {
      while (true) {
        final selection = _takeNextRunnableINatSelection();
        if (selection == null) break;
        await _runStageSelection(selection);
      }
    } finally {
      _inatRunner = null;
      _persistJobs();
      _ensureRunners();
      _emitState();
    }
  }

  List<_DeckStageSelection> _takeRunnableStageSelections(
    _DeckEnrichmentStage stage, {
    required int limit,
  }) {
    final jobs = _sortedJobs()
        .where((job) => _canRunStage(job, stage))
        .toList();
    final selections = jobs.take(limit).map((job) {
      _markStageRunning(job, stage);
      return _DeckStageSelection(job, stage);
    }).toList();

    if (selections.isNotEmpty) {
      _persistJobs();
      _emitState();
    }
    return selections;
  }

  _DeckStageSelection? _takeNextRunnableINatSelection() {
    for (final job in _sortedJobs()) {
      for (final stage in const [
        _DeckEnrichmentStage.nameResolution, // highest priority
        _DeckEnrichmentStage.inatPrimary,
        _DeckEnrichmentStage.names,
        _DeckEnrichmentStage.inatBackfill,
      ]) {
        if (_canRunStage(job, stage)) {
          _markStageRunning(job, stage);
          _persistJobs();
          _emitState();
          return _DeckStageSelection(job, stage);
        }
      }
    }
    return null;
  }

  Iterable<_DeckEnrichmentJob> _sortedJobs() sync* {
    final jobs = _jobsByDeckId.values.toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    for (final job in jobs) {
      yield job;
    }
  }

  bool _canRunStage(_DeckEnrichmentJob job, _DeckEnrichmentStage stage) {
    final state = job.stateFor(stage);
    if (state != _DeckEnrichmentStageState.pending) {
      return false;
    }

    switch (stage) {
      case _DeckEnrichmentStage.nameResolution:
        return job.unresolvedSpeciesNames.isNotEmpty &&
            _resolveNames != null &&
            _addSpeciesToDeck != null;
      case _DeckEnrichmentStage.cover:
        return job.coverImageUrl != null && job.coverImageUrl!.isNotEmpty;
      case _DeckEnrichmentStage.base:
        return true;
      case _DeckEnrichmentStage.inatPrimary:
        return true;
      case _DeckEnrichmentStage.names:
        return true;
      case _DeckEnrichmentStage.inatBackfill:
        final primaryState = job.stateFor(_DeckEnrichmentStage.inatPrimary);
        return primaryState != _DeckEnrichmentStageState.pending &&
            primaryState != _DeckEnrichmentStageState.running;
    }
  }

  void _markStageRunning(_DeckEnrichmentJob job, _DeckEnrichmentStage stage) {
    job.markRunning(stage);
    _markDeckAttempted(job.deckId);
  }

  bool _isJobCancelled(_DeckEnrichmentJob job) =>
      !_jobsByDeckId.containsKey(job.deckId);

  Future<void> _runStageSelection(_DeckStageSelection selection) async {
    final job = selection.job;
    final stage = selection.stage;

    if (_isJobCancelled(job)) return;

    try {
      switch (stage) {
        case _DeckEnrichmentStage.nameResolution:
          await _runNameResolutionStage(job);
          break;
        case _DeckEnrichmentStage.cover:
          await _runCoverStage(job);
          break;
        case _DeckEnrichmentStage.base:
          await _runBaseStage(job);
          break;
        case _DeckEnrichmentStage.inatPrimary:
          await _runPrimaryINatStage(job);
          break;
        case _DeckEnrichmentStage.names:
          await _runCommonNameStage(job);
          break;
        case _DeckEnrichmentStage.inatBackfill:
          await _runBackfillINatStage(job);
          break;
      }

      if (_isJobCancelled(job)) return;
      job.markSucceeded(stage);
      _maybeMarkDeckCompleted(job);
    } catch (error) {
      if (_isJobCancelled(job)) return;
      final kind = _classifyFailure(error);
      job.markFailed(stage, error, kind);
      _log.warn(
        'Background enrichment failed for ${job.deckId} '
        '(${stage.name}, ${kind.name}): $error',
      );
    } finally {
      if (!_isJobCancelled(job)) {
        _persistJobs();
        _emitState();
      }
    }
  }

  Future<void> _runNameResolutionStage(_DeckEnrichmentJob job) async {
    final namesToResolve = job.unresolvedSpeciesNames;
    if (namesToResolve.isEmpty) return;

    job.speciesCompleted = 0;
    job.speciesTotal = namesToResolve.length;
    _emitState();

    final resolved = await _resolveNames!(namesToResolve);

    if (resolved.isNotEmpty && !_isJobCancelled(job)) {
      await _addSpeciesToDeck!(job.deckId, resolved.values.toSet());
    }

    final stillUnresolved = namesToResolve
        .where((name) => !resolved.containsKey(name))
        .toList();
    job.stillUnresolvedNames = stillUnresolved;

    if (stillUnresolved.isNotEmpty) {
      _log.warn(
        'Name resolution for deck ${job.deckId}: '
        '${stillUnresolved.length}/${namesToResolve.length} species still unresolved: '
        '${stillUnresolved.join(", ")}',
      );
      if (!_isJobCancelled(job)) {
        _onNamesUnresolved?.call(job.deckId, stillUnresolved);
      }
    } else {
      _log.debug(
        'Name resolution for deck ${job.deckId}: '
        'all ${namesToResolve.length} species resolved via iNaturalist',
      );
    }
  }

  Future<void> _runCoverStage(_DeckEnrichmentJob job) async {
    final coverImageUrl = job.coverImageUrl;
    if (coverImageUrl == null || coverImageUrl.isEmpty) {
      return;
    }

    final localPath = await _imageService.downloadAndSaveDeckCover(
      coverImageUrl,
    );
    await _updateCoverPath(job.deckId, localPath);
  }

  Future<void> _runBaseStage(_DeckEnrichmentJob job) async {
    final speciesIds = await _resolveSpeciesIds({job.deckId});
    if (speciesIds.isEmpty) return;

    await _enrichmentService.downloadBaseImagesForSpecies(
      speciesIds,
      onProgress: (completed, total) {
        job.speciesCompleted = completed;
        job.speciesTotal = total;
        _emitState();
      },
      isCancelled: () => _isJobCancelled(job),
    );
  }

  Future<void> _runPrimaryINatStage(_DeckEnrichmentJob job) async {
    final speciesIds = await _resolveSpeciesIds({job.deckId});
    if (speciesIds.isEmpty) return;

    await _enrichmentService.fetchINatPhotosForSpecies(
      speciesIds,
      primaryOnly: true,
      prioritizeSpeciesWithoutImages: true,
      maxConcurrent: _backgroundINatMaxConcurrent,
      requestSpacing: _backgroundINatRequestSpacing,
      onProgress: (completed, total) {
        job.speciesCompleted = completed;
        job.speciesTotal = total;
        _emitState();
      },
      isCancelled: () => _isJobCancelled(job),
    );
  }

  Future<void> _runCommonNameStage(_DeckEnrichmentJob job) async {
    final speciesIds = await _resolveSpeciesIds({job.deckId});
    if (speciesIds.isEmpty) return;

    await _enrichmentService.fetchINatCommonNamesForSpecies(
      speciesIds,
      maxConcurrent: _backgroundINatMaxConcurrent,
      requestSpacing: _backgroundINatRequestSpacing,
      onProgress: (completed, total) {
        job.speciesCompleted = completed;
        job.speciesTotal = total;
        _emitState();
      },
      isCancelled: () => _isJobCancelled(job),
    );
  }

  Future<void> _runBackfillINatStage(_DeckEnrichmentJob job) async {
    final speciesIds = await _resolveSpeciesIds({job.deckId});
    if (speciesIds.isEmpty) return;

    await _enrichmentService.backfillINatPhotosForSpecies(
      speciesIds,
      maxConcurrent: _backgroundINatMaxConcurrent,
      requestSpacing: _backgroundINatRequestSpacing,
      onProgress: (completed, total) {
        job.speciesCompleted = completed;
        job.speciesTotal = total;
        _emitState();
      },
      isCancelled: () => _isJobCancelled(job),
    );
  }

  void _maybeMarkDeckCompleted(_DeckEnrichmentJob job) {
    if (job.hasPendingWork || job.hasFailedStage) {
      return;
    }
    _markDeckCompleted(job.deckId);
  }

  void _restoreCompletionTimestamps() {
    final preferences = _preferences;
    if (preferences == null) return;

    for (final key in preferences.getKeys()) {
      final isCompletedKey = key.startsWith(_completedAtPreferencePrefix);
      final isAttemptedKey = key.startsWith(_attemptedAtPreferencePrefix);
      if (!isCompletedKey && !isAttemptedKey) continue;

      final value = preferences.getInt(key);
      if (value == null) continue;

      if (isCompletedKey) {
        final deckId = key.substring(_completedAtPreferencePrefix.length);
        _lastCompletedAtByDeckId[deckId] = DateTime.fromMillisecondsSinceEpoch(
          value,
        );
      }

      if (isAttemptedKey) {
        final deckId = key.substring(_attemptedAtPreferencePrefix.length);
        _lastAttemptedAtByDeckId[deckId] = DateTime.fromMillisecondsSinceEpoch(
          value,
        );
      }
    }
  }

  void _restoreJobs() {
    final preferences = _preferences;
    if (preferences == null) return;

    for (final key in preferences.getKeys()) {
      if (!key.startsWith(_jobPreferencePrefix)) continue;

      final rawJob = preferences.getString(key);
      if (rawJob == null || rawJob.isEmpty) continue;

      try {
        final json = jsonDecode(rawJob) as Map<String, dynamic>;
        final job = _DeckEnrichmentJob.fromJson(json);
        _jobsByDeckId[job.deckId] = job;
      } catch (error) {
        _log.warn('Failed to restore enrichment job from $key: $error');
      }
    }
  }

  void _persistJobs() {
    final preferences = _preferences;
    if (preferences == null) return;

    final persistedKeys = preferences.getKeys().where(
      (key) => key.startsWith(_jobPreferencePrefix),
    );
    final currentKeys = _jobsByDeckId.keys
        .map((deckId) => '$_jobPreferencePrefix$deckId')
        .toSet();

    for (final key in persistedKeys) {
      if (!currentKeys.contains(key)) {
        preferences.remove(key);
      }
    }

    for (final job in _jobsByDeckId.values) {
      preferences.setString(
        '$_jobPreferencePrefix${job.deckId}',
        jsonEncode(job.toJson()),
      );
    }
  }

  void _markDeckAttempted(String deckId) {
    final attemptedAt = DateTime.now();
    _lastAttemptedAtByDeckId[deckId] = attemptedAt;
    _preferences?.setInt(
      '$_attemptedAtPreferencePrefix$deckId',
      attemptedAt.millisecondsSinceEpoch,
    );
  }

  void _markDeckCompleted(String deckId) {
    final completedAt = DateTime.now();
    _lastCompletedAtByDeckId[deckId] = completedAt;
    _preferences?.setInt(
      '$_completedAtPreferencePrefix$deckId',
      completedAt.millisecondsSinceEpoch,
    );
  }

  void _emitState() {
    _status = _deriveStatus();
    notifyListeners();
  }

  INatEnrichmentStatus _deriveStatus() {
    final runningDecks = _jobsByDeckId.values
        .where((job) => job.isActive)
        .toList();
    if (runningDecks.isEmpty) {
      return INatEnrichmentStatus.idle;
    }

    final prioritizedPhases = <INatEnrichmentPhase>[
      INatEnrichmentPhase.nameResolution,
      INatEnrichmentPhase.inat,
      INatEnrichmentPhase.names,
      INatEnrichmentPhase.base,
      INatEnrichmentPhase.cover,
    ];

    for (final phase in prioritizedPhases) {
      final activeJobs = runningDecks
          .where((job) => job.currentPhase == phase)
          .toList();
      if (activeJobs.isEmpty) continue;

      // Sum species-level progress across all jobs active in this phase.
      final speciesCompleted = activeJobs.fold(
        0,
        (sum, job) => sum + job.speciesCompleted,
      );
      final speciesTotal = activeJobs.fold(
        0,
        (sum, job) => sum + job.speciesTotal,
      );

      return INatEnrichmentStatus(
        isRunning: true,
        phase: phase,
        completed: speciesCompleted,
        total: speciesTotal,
        activeDeckCount: runningDecks.length,
      );
    }

    return INatEnrichmentStatus(
      isRunning: true,
      phase: runningDecks.first.currentPhase ?? INatEnrichmentPhase.base,
      completed: 0,
      total: 0,
      activeDeckCount: runningDecks.length,
    );
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
      // Ignore if no binding is active anymore.
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
