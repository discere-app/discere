/// Drains the enrichment queues while the app is alive, in the UI isolate.
///
/// Three consumers run concurrently against their own queues: the deck cover
/// job, `BaseWorker` for reference images, and `INatWorker` as the single
/// rate-limited iNaturalist consumer. A pass ends when all three report
/// nothing left to claim.
///
/// There is deliberately no second isolate — one would race the UI isolate
/// for the user database's writer lock. Staying alive while backgrounded is
/// the foreground service's job, not this one's.
///
/// This owns only the pass: whether one may start, and whether another
/// should follow, stays with the queue service, which is what knows about
/// review sessions, connectivity and disposal.
library;

import 'dart:async';

import 'package:discere/enrichment/pipeline/service/base_worker.dart';
import 'package:discere/enrichment/pipeline/service/inat_worker.dart';
import 'package:discere/enrichment/queue/model/enrichment_job.dart';
import 'package:discere/enrichment/queue/service/cover_job_runner.dart';
import 'package:discere/shared/util/logger.dart';

class ForegroundEnrichmentRunner {
  static final _log = Logger.forType(ForegroundEnrichmentRunner);

  final CoverJobRunner _coverRunner;
  final BaseWorker _baseWorker;
  final INatWorker _iNatWorker;
  final String _owner;

  /// Asked between items rather than once at the start, so a pass reacts to
  /// disposal, a starting review session or a lost connection within one
  /// item instead of at the end of the batch.
  final bool Function() _shouldStop;

  /// Fired after every single item, so deck progress moves during a long
  /// batch instead of jumping once at the end.
  final void Function() _onProgress;

  /// Runs once a pass has finished and [isRunning] is false again.
  final Future<void> Function() _onPassFinished;

  Future<void>? _pass;

  ForegroundEnrichmentRunner({
    required CoverJobRunner coverRunner,
    required BaseWorker baseWorker,
    required INatWorker iNatWorker,
    required String owner,
    required bool Function() shouldStop,
    required void Function() onProgress,
    required Future<void> Function() onPassFinished,
  }) : _coverRunner = coverRunner,
       _baseWorker = baseWorker,
       _iNatWorker = iNatWorker,
       _owner = owner,
       _shouldStop = shouldStop,
       _onProgress = onProgress,
       _onPassFinished = onPassFinished;

  bool get isRunning => _pass != null;

  /// Starts a pass if none is running. Callers check their own preconditions
  /// first; this only guards against overlapping passes.
  void start() {
    if (_pass != null) return;
    _log.debug('Start foreground runner');
    _pass = _runPass();
  }

  /// Waits out the current pass, and any pass its completion starts.
  Future<void> awaitIdle() async {
    while (_pass != null) {
      await _pass;
    }
  }

  Future<void> _runPass() async {
    try {
      _log.debug('Foreground runner enter owner=$_owner');
      await Future.wait([
        _coverRunner.runUntilIdle(
          owner: _owner,
          runnerKind: EnrichmentRunnerKind.foreground,
          shouldStop: _shouldStop,
        ),
        _baseWorker.runUntilIdle(
          shouldStop: _shouldStop,
          onProgress: _onProgress,
        ),
        _iNatWorker.runUntilIdle(
          shouldStop: _shouldStop,
          onProgress: _onProgress,
        ),
      ]);
    } finally {
      _pass = null;
      _log.debug('Foreground runner exit owner=$_owner');
      await _onPassFinished();
    }
  }
}
