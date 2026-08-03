import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import 'test_utils.dart';

/// A fixture species with zero usable reference pictures (see
/// test/fixtures/discere_reference_test.db) — real reference-image
/// resolution for it always comes up empty, so combined with the
/// `inat_photo_cache` sentinel seeded below it exercises the real
/// SpeciesMediaService/LocalSpeciesImageService/INatPhotoCacheRepository
/// stack, not a fake standing in for "no photo".
const _speciesWithoutPictures = 'discere:sealifebase_species:67018';
const _deckId = 'no-photo-found-test-deck';

/// Seeds every row the real app needs to consider [_deckId]'s single species
/// image-enrichment-complete-with-no-photo *before* the app ever starts, so
/// `INatEnrichmentQueueService`'s very first refresh (during its own
/// `initialize()` in bootstrap) picks this up directly — avoiding a real
/// (and, under this suite's fail-fast HTTP override, effectively
/// undownloadable) enrichment run, and avoiding any race with the service's
/// delta-loading cursor that a post-startup seed would risk.
Future<void> _seedTerminallyImagelessDeck() async {
  final db = await DatabaseHelper.userDb;
  final now = DateTime.now().millisecondsSinceEpoch;

  await db.insert('decks', {
    'id': _deckId,
    'name': 'No Photo Found Test Deck',
    'description': '',
    'language': 1,
    'sortOrder': 0,
  });
  await db.insert('flashcard_stats', {
    'species_id': _speciesWithoutPictures,
    'deck_id': _deckId,
    'learning_mode': 'species',
    'name_type': 'commonName',
    'next_review_date': now - 1000,
  });
  await db.insert('enrichment_species_deck_membership', {
    'species_id': _speciesWithoutPictures,
    'deck_id': _deckId,
  });
  await db.insert('enrichment_species_work', {
    'species_id': _speciesWithoutPictures,
    'owner_deck_id': _deckId,
    'deck_count': 1,
    'wants_inat_photos': 1,
    'wants_common_names': 0,
    'updated_at': now,
  });
  for (final capability in ['base', 'inatPrimary']) {
    await db.insert('enrichment_species_capability_state', {
      'species_id': _speciesWithoutPictures,
      'capability': capability,
      'state': 'noResult',
      'attempt_count': 1,
      'updated_at': now,
    });
  }
  await db.insert('inat_photo_cache', {
    'species_id': _speciesWithoutPictures,
    'photo_url': '__empty__',
    'fetched_at': now,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
    await _seedTerminallyImagelessDeck();
  });

  tearDown(() async {
    await DatabaseHelper.close();
  });

  testWidgets(
    'a deck whose only species has no findable photo offers the gaps '
    'dialog, then shows the inline hint during review',
    (tester) async {
      final mockNotificationService = createMockNotificationService();
      await startApp(
        tester,
        notificationService: mockNotificationService,
        processEnrichmentJobs: false,
      );

      final BuildContext context = tester.element(find.byType(MaterialApp));
      await waitForCondition(tester, () {
        if (!context.mounted) return false;
        return Provider.of<INatEnrichmentQueueService>(context, listen: false)
            .deckInfo(_deckId)
            .imageStagesComplete;
      }, timeout: const Duration(seconds: 15));
      if (!context.mounted) {
        fail('MaterialApp context was unmounted while waiting');
      }
      expect(
        Provider.of<INatEnrichmentQueueService>(
          context,
          listen: false,
        ).deckInfo(_deckId).imageStagesComplete,
        isTrue,
        reason:
            'seeded capability rows should have made the queue service '
            'consider this deck\'s image stages complete on its first '
            'refresh during app startup',
      );

      final deckFinder = find.text('No Photo Found Test Deck');
      await tester.scrollUntilVisible(
        deckFinder,
        500.0,
        scrollable: find.descendant(
          of: find.byKey(const Key('home_deck_list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(deckFinder.last);
      await safePumpAndSettle(tester);

      // The proactive gaps dialog offers to remove the species — confirm
      // without checking it, i.e. "keep".
      await waitForFinder(tester, find.byKey(const Key('no_photo_gaps_dialog')));
      expect(
        find.byKey(const Key('no_photo_gaps_dialog')),
        findsOneWidget,
        reason:
            'the real SpeciesMediaService/INatPhotoCacheRepository stack '
            'should have classified the seeded species as a photo gap',
      );
      await tester.tap(find.byKey(const Key('no_photo_gaps_confirm_button')));
      await safePumpAndSettle(tester);
      expect(find.byKey(const Key('no_photo_gaps_dialog')), findsNothing);

      // The card itself is now showing, with the same information inline.
      await waitForFinder(
        tester,
        find.byKey(const Key('remove_species_button')),
      );
      expect(find.byKey(const Key('remove_species_button')), findsOneWidget);
    },
    timeout: integrationTestTimeout,
  );
}
