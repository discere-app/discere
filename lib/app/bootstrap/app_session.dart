import 'dart:async';

import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/import/remote_deck_service.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/service/deck_source_id_backfill_service.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/util/logger.dart';

/// What one run of the bootstrap started that keeps running on its own:
/// the setup deferred past the first frame, and the services that hold
/// timers, subscriptions or work in flight. [stop] ends all of it, for a
/// restart of the app.
///
/// Everything else the bootstrap builds goes with the provider tree it lives
/// in. That includes the `HostCooldownTracker`: its timers only expire
/// cooldowns, and a request of the old session still in flight reports to
/// it — disposed, it would fail that request's bookkeeping instead.
class AppSession {
  static const _log = ScopedLogger('bootstrap');

  AppSession({
    required NotificationService notificationService,
    required INatEnrichmentQueueService enrichmentQueue,
    required DeckRepository deckRepository,
    required RemoteDeckService remoteDeckService,
    required DeckUpdateService deckUpdateService,
    required ConnectivityNetworkAvailability networkAvailability,
    required LocalDiagnostics localDiagnostics,
  }) : _notificationService = notificationService,
       _enrichmentQueue = enrichmentQueue,
       _deckRepository = deckRepository,
       _remoteDeckService = remoteDeckService,
       _deckUpdateService = deckUpdateService,
       _networkAvailability = networkAvailability,
       _localDiagnostics = localDiagnostics;

  final NotificationService _notificationService;
  final INatEnrichmentQueueService _enrichmentQueue;
  final DeckRepository _deckRepository;
  final RemoteDeckService _remoteDeckService;
  final DeckUpdateService _deckUpdateService;
  final ConnectivityNetworkAvailability _networkAvailability;
  final LocalDiagnostics _localDiagnostics;

  Future<void>? _deferred;

  /// The setup that waits for the first frame. Runs once.
  Future<void> startDeferred() => _deferred ??= _runDeferred();

  Future<void> _runDeferred() async {
    _log.debug('deferred setup: starting');
    await _notificationService.initNotification();
    await _enrichmentQueue.initialize();
    // DeckSourceIdBackfillService is @Deprecated as a marker for when to
    // delete it (and this call) — see its class doc for the removal plan.
    await DeckSourceIdBackfillService(
      _deckRepository,
      _remoteDeckService,
    ).runIfNeeded();
    // Reads only; nothing to wait for when stopping.
    unawaited(_deckUpdateService.checkForUpdates());
    _log.debug('deferred setup: done');
  }

  /// Stops what this session started and completes once none of it writes
  /// to the user database any more: the deferred setup, the enrichment
  /// queue down to the item each worker is on, and the queued diagnostics
  /// writes. The connectivity subscription is cancelled.
  Future<void> stop() async {
    try {
      await _deferred;
    } catch (error, stackTrace) {
      _log.warn('Deferred setup failed', error: error, stackTrace: stackTrace);
    }
    await _enrichmentQueue.shutdown();
    _networkAvailability.dispose();
    await _localDiagnostics.flush();
  }
}
