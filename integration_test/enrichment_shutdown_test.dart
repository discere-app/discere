import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/learning/service/deck_import_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'test_utils.dart';

/// Species from the reference-DB test fixture (see
/// etl/scripts/test_fixture_species.txt) — enough that INatWorker, which
/// rate-limits itself to one claim per ~1.1s (see INatWorker._requestSpacing),
/// is guaranteed to still be actively looping — mid-batch, with DB writes in
/// flight — for a long, deterministic stretch. That's a much wider target to
/// fire a shutdown into than hoping to get lucky against fast-failing (50ms)
/// HTTP calls with only a handful of species.
const _manySpeciesNames = [
  'Carcharodon carcharias',
  'Galeocerdo cuvier',
  'Prionace glauca',
  'Rhincodon typus',
  'Sphyrna mokarran',
  'Alopias vulpinus',
  'Phoxinus phoxinus',
  'Thymallus thymallus',
  'Oncorhynchus mykiss',
  'Amphiprion ocellaris',
  'Enteroctopus dofleini',
  'Abramis brama',
  'Natator depressus',
  'Pterois miles',
  'Chelonia mydas',
  'Costoanachis cascabulloi',
  'Staurastrum limneticum',
  'Nicolea chilensis',
  'Trichopodus trichopterus',
  'Americhelidium shoemakeri',
];

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  tearDown(() async {
    await DatabaseHelper.close();
  });

  group('Enrichment shutdown', () {
    testWidgets(
      'DatabaseHelper.close() completes promptly, and the user DB can be '
      'reopened right afterward, even while BaseWorker/INatWorker are '
      'actively mid-batch — reproduces (or clears) the mechanism behind a '
      'reported stuck-splash-screen bug: main.dart calls '
      'unawaited(DatabaseHelper.close()) on AppLifecycleState.detached '
      'because sqflite\'s native DB handle is a process-wide singleton keyed '
      'by path; if that close() never actually finishes releasing it, the '
      'next launch\'s openDatabase() on the same path hangs forever. A real '
      'engine detach/recreate can\'t be simulated inside one continuous '
      'integration_test process, so this drives the shared root cause '
      'directly: calling DatabaseHelper.close() for real, under real '
      'producer-consumer worker load, and bounding it with a timeout.',
      (tester) async {
        final mockNotificationService = createMockNotificationService();

        await startApp(
          tester,
          notificationService: mockNotificationService,
          processEnrichmentJobs: true,
        );

        final BuildContext context = tester.element(find.byType(MaterialApp));
        if (!context.mounted) return;

        final deckId = await Provider.of<DeckImportService>(
          context,
          listen: false,
        ).importDeckFromSpeciesNames(
          name: 'Shutdown Race Test Deck',
          description: '',
          scientificNames: _manySpeciesNames,
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

        // Give the foreground runner a moment to actually start claiming and
        // writing — well before the ~20+ second full drain (20 species *
        // ~1.1s INatWorker spacing) finishes, so the workers are guaranteed
        // still busy for what follows.
        await tester.pump(const Duration(milliseconds: 500));

        // The actual regression under test: does closing the user DB — the
        // same call main.dart's lifecycle observer fires unawaited on
        // AppLifecycleState.detached — complete promptly even with
        // BaseWorker/INatWorker mid-loop, or does it hang? A hang here is
        // exactly what leaves the native sqflite handle for
        // discere_user.db un-released, which is what makes the *next*
        // launch's openDatabase() on the same path stick forever.
        await DatabaseHelper.close().timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail(
            'DatabaseHelper.close() did not complete within 5s while '
            'BaseWorker/INatWorker were still actively processing — this is '
            'the mechanism behind the stuck-splash-screen bug: the native '
            'sqflite handle for discere_user.db is never released in time, '
            'so the next launch\'s openDatabase() on the same path can hang '
            'forever.',
          ),
        );

        // A fresh open of the same path right after — simulating the next
        // launch — must also succeed promptly, proving the native handle was
        // genuinely released rather than just the Dart-side call returning.
        final reopened = await DatabaseHelper.userDb.timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail(
            'Reopening discere_user.db immediately after close() hung — the '
            'native handle was not actually released.',
          ),
        );
        expect(await reopened.rawQuery('SELECT 1'), isNotEmpty);
      },
      timeout: integrationTestTimeout,
    );
  });
}
