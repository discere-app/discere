import 'package:discere/enrichment/service/enrichment_background_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';

void main() {
  group('WorkmanagerEnrichmentBackgroundScheduler', () {
    late WorkmanagerEnrichmentBackgroundScheduler scheduler;

    setUp(() {
      scheduler = WorkmanagerEnrichmentBackgroundScheduler(
        callbackDispatcher: () {},
      );
    });

    test('expedited Android plan does not use an initial delay', () {
      final plan = scheduler.buildAndroidOneOffPlan(expedited: true);

      expect(plan.initialDelay, isNull);
      expect(plan.constraints.networkType, NetworkType.connected);
      expect(plan.existingWorkPolicy, ExistingWorkPolicy.keep);
      expect(
        plan.outOfQuotaPolicy,
        OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
      );
    });

    test('regular Android plan keeps the short initial delay', () {
      final plan = scheduler.buildAndroidOneOffPlan(expedited: false);

      expect(plan.initialDelay, const Duration(seconds: 5));
      expect(plan.constraints.networkType, NetworkType.connected);
      expect(plan.existingWorkPolicy, ExistingWorkPolicy.keep);
      expect(plan.outOfQuotaPolicy, isNull);
    });
  });
}
