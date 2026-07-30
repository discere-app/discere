import 'package:discere/enrichment/pipeline/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'test_utils.dart';

/// Polls a raw DB condition, pumping the widget tree between checks so
/// pending async work (worker loops, DB writes) actually gets a chance to
/// run — [waitForCondition] only supports a synchronous predicate, which
/// can't await a database query directly.
Future<void> _pollUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  Duration step = const Duration(milliseconds: 300),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await tester.pump(step);
  }
}

/// Whether any row for [capability] has reached an outcome from its attempt
/// (retryScheduled/done/noResult/permanentFailure) — not just been claimed
/// (state 'running'). Waiting for this instead of merely "claimed" ensures
/// the worker's write recording that outcome has actually landed before the
/// test proceeds to tear down the database; otherwise that write can still
/// be in flight when tearDown closes the DB, throwing an uncaught
/// DatabaseException after the test itself has already finished.
Future<bool> _anyCapabilityRowSettled(String capability) async {
  final db = await DatabaseHelper.userDb;
  final rows = await db.query(
    EnrichmentWorkRepository.capabilityStateTable,
    where: 'capability = ? AND state NOT IN (?, ?)',
    whereArgs: [capability, 'pending', 'running'],
    limit: 1,
  );
  return rows.isNotEmpty;
}

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  tearDown(() async {
    await DatabaseHelper.close();
  });

  group('Enrichment pipeline', () {
    testWidgets(
      'BaseWorker and INatWorker independently claim and process a new '
      'deck\'s species once enrichment jobs are enabled, without blocking '
      'the UI',
      (tester) async {
        final mockNotificationService = createMockNotificationService();

        await startApp(
          tester,
          notificationService: mockNotificationService,
          processEnrichmentJobs: true,
        );

        // Create the deck and grant iNat consent through the services
        // directly, in a single scheduleDeckEnrichment call, rather than
        // through the create-deck page's own two-step UI flow (an initial
        // base-only schedule, then a second iNat-consent schedule after the
        // download dialog). Driving it as two separate calls with real time
        // in between can race INatEnrichmentQueueService's foreground
        // runner: if the runner's current pass has already let INatWorker's
        // loop exhaust its (still-empty) queue and return by the time the
        // second call seeds a speciesCommonNames row, nothing automatically
        // wakes INatWorker back up until some unrelated event (app
        // resume, network change, another schedule call) happens to call
        // _ensureForegroundRunner() again — see the review finding about
        // this exact gap. A single combined call sidesteps it by seeding
        // both `base` and `speciesCommonNames` before the very first
        // foreground pass ever starts.
        final BuildContext context = tester.element(find.byType(MaterialApp));
        if (!context.mounted) return;
        final deckId = await Provider.of<DeckImportService>(
          context,
          listen: false,
        ).importDeckFromSpeciesNames(
          name: 'Enrichment Pipeline Test Deck',
          description: '',
          scientificNames: const ['Amphiprion ocellaris'],
          language: Language.en,
        );
        if (!context.mounted) return;
        await Provider.of<INatEnrichmentQueueService>(
          context,
          listen: false,
        ).scheduleDeckEnrichment(
          [deckId],
          includeINatPhotos: true,
          includeCommonNames: true,
        );
        await safePumpAndSettle(tester);

        // BaseWorker claims the freshly-scheduled base-image work and
        // attempts a download. HTTP is forced to fail fast in tests (see
        // _FastFailHttpOverrides), so this quickly records a failed attempt
        // (state moves off 'pending') instead of hanging — proving the
        // queue service actually starts and runs BaseWorker once
        // processEnrichmentJobs is enabled.
        await _pollUntil(tester, () => _anyCapabilityRowSettled('base'));
        expect(
          await _anyCapabilityRowSettled('base'),
          isTrue,
          reason:
              'BaseWorker should have claimed and attempted the species\' '
              'base-image download by now',
        );

        // INatWorker independently claims the species-common-names item —
        // seeded at a fixed priority tier, not gated behind base's own
        // retry backoff — proving the two workers run concurrently rather
        // than one queueing behind the other.
        await _pollUntil(
          tester,
          () => _anyCapabilityRowSettled('speciesCommonNames'),
        );
        expect(
          await _anyCapabilityRowSettled('speciesCommonNames'),
          isTrue,
          reason:
              'INatWorker should have claimed and attempted the species '
              'common-names fetch by now, independently of BaseWorker\'s '
              'own retry backoff',
        );

        // The UI stays stable while this background work is in flight —
        // navigating to the deck list still renders normally rather than
        // hanging or showing a broken widget tree.
        await tester.pump();
        expect(find.byType(Card), findsWidgets);
      },
      timeout: integrationTestTimeout,
    );
  });
}
