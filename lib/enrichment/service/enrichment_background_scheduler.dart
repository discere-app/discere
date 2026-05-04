import 'dart:io';

import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

abstract class EnrichmentBackgroundScheduler {
  Future<void> initialize();

  /// Cancels any pending or running Workmanager enrichment task.
  ///
  /// Called on foreground cold-start to ensure no legacy background-isolate
  /// task can hold the user-DB writer lock during startup.
  Future<void> cancelAllPendingProcessing();

  /// No-op — kept so callers that cancel per-deck work compile without change.
  Future<void> cancelProcessingForDeck(String deckId);
}

class NoopEnrichmentBackgroundScheduler
    implements EnrichmentBackgroundScheduler {
  const NoopEnrichmentBackgroundScheduler();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> cancelAllPendingProcessing() async {}

  @override
  Future<void> cancelProcessingForDeck(String deckId) async {}
}

/// Thin Workmanager wrapper used only for startup cleanup.
///
/// New enrichment work is no longer dispatched to a Workmanager background
/// isolate — that path was removed to eliminate the SQLite writer-lock
/// conflict with the UI isolate. This class now only cancels any legacy task
/// that may have been scheduled by an older app version.
class WorkmanagerEnrichmentBackgroundScheduler
    implements EnrichmentBackgroundScheduler {
  static final _log = Logger.forType(WorkmanagerEnrichmentBackgroundScheduler);
  static const uniqueWorkName = 'discere-inat-enrichment-processing';

  final Function callbackDispatcher;
  bool _initialized = false;

  WorkmanagerEnrichmentBackgroundScheduler({required this.callbackDispatcher});

  @override
  Future<void> initialize() async {
    if (_initialized || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    await Workmanager().initialize(callbackDispatcher);
    _initialized = true;
  }

  @override
  Future<void> cancelProcessingForDeck(String deckId) async {}

  @override
  Future<void> cancelAllPendingProcessing() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    if (!_initialized) {
      try {
        await initialize();
      } catch (e) {
        _log.warn('Workmanager initialize failed during startup cancel: $e');
        return;
      }
    }
    try {
      await Workmanager().cancelByUniqueName(uniqueWorkName);
      _log.debug('Cancelled pending background enrichment task on startup');
    } catch (e) {
      _log.warn('Workmanager cancelByUniqueName failed: $e');
    }
  }
}
