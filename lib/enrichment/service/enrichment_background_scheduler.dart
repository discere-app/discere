import 'dart:io';

import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

abstract class EnrichmentBackgroundScheduler {
  Future<void> initialize();

  Future<void> scheduleProcessing({bool expedited = false});

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
  Future<void> scheduleProcessing({bool expedited = false}) async {}
}

class WorkmanagerEnrichmentBackgroundScheduler
    implements EnrichmentBackgroundScheduler {
  static final _log = Logger.forType(WorkmanagerEnrichmentBackgroundScheduler);
  static const processingTaskName = 'ch.feberle.discere.enrichment.processing';
  static const uniqueWorkName = 'discere-inat-enrichment-processing';

  final Function callbackDispatcher;
  bool _initialized = false;

  WorkmanagerEnrichmentBackgroundScheduler({required this.callbackDispatcher});

  @visibleForTesting
  AndroidOneOffSchedulePlan buildAndroidOneOffPlan({required bool expedited}) {
    return AndroidOneOffSchedulePlan(
      initialDelay: expedited ? null : const Duration(seconds: 5),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      outOfQuotaPolicy: expedited
          ? OutOfQuotaPolicy.runAsNonExpeditedWorkRequest
          : null,
    );
  }

  @override
  Future<void> initialize() async {
    if (_initialized || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    await Workmanager().initialize(callbackDispatcher);
    _initialized = true;
  }

  @override
  Future<void> scheduleProcessing({bool expedited = false}) async {
    if (!_initialized || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    _log.debug('Scheduling background enrichment task expedited=$expedited');
    if (Platform.isIOS) {
      await Workmanager().registerProcessingTask(
        uniqueWorkName,
        processingTaskName,
        initialDelay: const Duration(seconds: 5),
      );
      return;
    }

    final plan = buildAndroidOneOffPlan(expedited: expedited);
    await Workmanager().registerOneOffTask(
      uniqueWorkName,
      processingTaskName,
      initialDelay: plan.initialDelay,
      constraints: plan.constraints,
      existingWorkPolicy: plan.existingWorkPolicy,
      outOfQuotaPolicy: plan.outOfQuotaPolicy,
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

@visibleForTesting
class AndroidOneOffSchedulePlan {
  const AndroidOneOffSchedulePlan({
    required this.initialDelay,
    required this.constraints,
    required this.existingWorkPolicy,
    required this.outOfQuotaPolicy,
  });

  final Duration? initialDelay;
  final Constraints constraints;
  final ExistingWorkPolicy existingWorkPolicy;
  final OutOfQuotaPolicy? outOfQuotaPolicy;
}
