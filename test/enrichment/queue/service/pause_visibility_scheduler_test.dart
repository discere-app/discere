import 'package:discere/enrichment/model/deck_enrichment_projection.dart';
import 'package:discere/enrichment/queue/presentation/deck_enrichment_state_presenter.dart';
import 'package:discere/enrichment/queue/service/enrichment_progress_status.dart';
import 'package:discere/enrichment/queue/service/pause_visibility_scheduler.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// A deck whose next retry is [untilRetry] away, which is what decides
/// whether it reads as paused.
DeckWorkSnapshot deckRetryingIn(String deckId, Duration? untilRetry) =>
    DeckWorkSnapshot(
      deckId: deckId,
      coverJob: null,
      projection: DeckEnrichmentProjection(
        deckId: deckId,
        earliestRetryAt: untilRetry == null
            ? null
            : DateTime.now().add(untilRetry),
        speciesCount: 1,
        imageCompleteSpeciesCount: 0,
        imageDoneSpeciesCount: 0,
        speciesCommonNamesWantedCount: 0,
        speciesCommonNamesTerminalCount: 0,
        inatBackfillWantedCount: 0,
        inatBackfillTerminalCount: 0,
        taxonomyTotalCount: 0,
        taxonomyTerminalCount: 0,
        pendingUnresolvedNameCount: 0,
        wantsInatPhotosSpeciesCount: 0,
        wantsCommonNamesSpeciesCount: 0,
        anyPermanentFailure: false,
        anyImagePermanentFailure: false,
        hasImmediatePendingWork: false,
        staleBaseSpeciesCount: 0,
      ),
    );

void main() {
  late List<String> events;

  PauseVisibilityScheduler build() =>
      PauseVisibilityScheduler(onBecameVisible: () => events.add('refresh'));

  setUp(() => events = <String>[]);

  group('host cooldown', () {
    test('records when it became active and clears when it ends', () {
      fakeAsync((async) {
        final scheduler = build();
        expect(scheduler.cooldownActiveSince, isNull);

        scheduler.syncCooldown(true);
        expect(scheduler.cooldownActiveSince, isNotNull);

        scheduler.syncCooldown(false);
        expect(scheduler.cooldownActiveSince, isNull);
        scheduler.dispose();
      });
    });

    test('a repeated report does not restart the clock', () {
      fakeAsync((async) {
        final scheduler = build();
        scheduler.syncCooldown(true);
        final first = scheduler.cooldownActiveSince;

        async.elapse(const Duration(seconds: 10));
        scheduler.syncCooldown(true);

        expect(scheduler.cooldownActiveSince, first);
        scheduler.dispose();
      });
    });

    test('asks for a recompute once it becomes showable, not before', () {
      // Time passing is not a change: without this wake-up a cooldown that
      // crosses the threshold while nothing else happens stays invisible.
      fakeAsync((async) {
        final scheduler = build();
        scheduler.syncCooldown(true);

        async.elapse(cooldownVisibleAfter - const Duration(seconds: 1));
        expect(events, isEmpty);

        async.elapse(const Duration(seconds: 2));
        expect(events, ['refresh']);
        scheduler.dispose();
      });
    });

    test('a cooldown that ends first asks for nothing', () {
      fakeAsync((async) {
        final scheduler = build();
        scheduler.syncCooldown(true);
        async.elapse(const Duration(seconds: 5));
        scheduler.syncCooldown(false);

        async.elapse(const Duration(minutes: 5));
        expect(events, isEmpty);
        scheduler.dispose();
      });
    });
  });

  group('deck pauses', () {
    test('a retry beyond the threshold wakes up when it reaches it', () {
      fakeAsync((async) {
        final scheduler = build();
        scheduler.syncDeckPauses([
          deckRetryingIn('deck-1', pauseVisibleAfter + const Duration(minutes: 3)),
        ]);

        async.elapse(const Duration(minutes: 2));
        expect(events, isEmpty);

        async.elapse(const Duration(minutes: 2));
        expect(events, ['refresh']);
        scheduler.dispose();
      });
    });

    test('a retry already inside the threshold needs no timer', () {
      // It reads as paused at the next recompute anyway.
      fakeAsync((async) {
        final scheduler = build();
        scheduler.syncDeckPauses([
          deckRetryingIn('deck-1', const Duration(seconds: 30)),
        ]);

        async.elapse(const Duration(hours: 1));
        expect(events, isEmpty);
        scheduler.dispose();
      });
    });

    test('a deck with no retry at all needs no timer', () {
      fakeAsync((async) {
        final scheduler = build();
        scheduler.syncDeckPauses([deckRetryingIn('deck-1', null)]);

        async.elapse(const Duration(hours: 1));
        expect(events, isEmpty);
        scheduler.dispose();
      });
    });

    test('a deck that stops needing one loses its pending timer', () {
      // Dropped here rather than when it fires: a deck that resumed or was
      // cancelled would otherwise keep a timer alive for a state it left.
      fakeAsync((async) {
        final scheduler = build();
        scheduler.syncDeckPauses([
          deckRetryingIn('deck-1', const Duration(minutes: 10)),
        ]);
        scheduler.syncDeckPauses(const []);

        async.elapse(const Duration(hours: 1));
        expect(events, isEmpty);
        scheduler.dispose();
      });
    });

    test('re-reporting the same deck does not stack timers', () {
      fakeAsync((async) {
        final scheduler = build();
        for (var i = 0; i < 5; i++) {
          scheduler.syncDeckPauses([
            deckRetryingIn('deck-1', const Duration(minutes: 10)),
          ]);
        }

        async.elapse(const Duration(hours: 1));
        expect(events, ['refresh']);
        scheduler.dispose();
      });
    });

    test('each deck wakes up on its own schedule', () {
      fakeAsync((async) {
        final scheduler = build();
        scheduler.syncDeckPauses([
          deckRetryingIn('deck-soon', const Duration(minutes: 4)),
          deckRetryingIn('deck-later', const Duration(minutes: 20)),
        ]);

        async.elapse(const Duration(minutes: 3));
        expect(events, ['refresh']);

        async.elapse(const Duration(minutes: 20));
        expect(events, ['refresh', 'refresh']);
        scheduler.dispose();
      });
    });
  });

  test('nothing is asked for after dispose', () {
    fakeAsync((async) {
      final scheduler = build();
      scheduler.syncCooldown(true);
      scheduler.syncDeckPauses([
        deckRetryingIn('deck-1', const Duration(minutes: 10)),
      ]);
      scheduler.dispose();

      async.elapse(const Duration(hours: 1));
      expect(events, isEmpty);
    });
  });

  test('syncing after dispose stays inert', () {
    fakeAsync((async) {
      final scheduler = build()..dispose();
      scheduler
        ..syncCooldown(true)
        ..syncDeckPauses([deckRetryingIn('deck-1', const Duration(minutes: 10))]);

      expect(scheduler.cooldownActiveSince, isNull);
      async.elapse(const Duration(hours: 1));
      expect(events, isEmpty);
    });
  });
}
