import 'dart:io';

import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

abstract class EnrichmentBackgroundScheduler {
  Future<void> initialize();

  Future<void> scheduleProcessing();

  Future<void> cancelProcessingForDeck(String deckId);
}

class NoopEnrichmentBackgroundScheduler
    implements EnrichmentBackgroundScheduler {
  const NoopEnrichmentBackgroundScheduler();

  @override
  Future<void> cancelProcessingForDeck(String deckId) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleProcessing() async {}
}

class WorkmanagerEnrichmentBackgroundScheduler
    implements EnrichmentBackgroundScheduler {
  static final _log = Logger.forType(WorkmanagerEnrichmentBackgroundScheduler);
  static const processingTaskName = 'ch.feberle.discere.enrichment.processing';
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
  Future<void> scheduleProcessing() async {
    if (!_initialized || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    _log.debug('Scheduling background enrichment task');
    if (Platform.isIOS) {
      await Workmanager().registerProcessingTask(
        uniqueWorkName,
        processingTaskName,
        initialDelay: const Duration(seconds: 5),
      );
      return;
    }

    await Workmanager().registerOneOffTask(
      uniqueWorkName,
      processingTaskName,
      initialDelay: const Duration(seconds: 5),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  @override
  Future<void> cancelProcessingForDeck(String deckId) async {
    if (!_initialized || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    await Workmanager().cancelByUniqueName(uniqueWorkName);
  }
}
