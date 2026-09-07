/// The derived status is not a straight relay of what the caller passes in,
/// and one case bites: with nothing pending it returns
/// [INatEnrichmentStatus.idle], which reports no host cooldown however
/// active the tracker says one is.
///
/// The queue service relies on that — it takes the cooldown timestamp from
/// the *derived* flag, not the tracker, so the per-deck states agree with
/// the status. Reordering those two steps looks harmless and is not.
library;

import 'package:discere/enrichment/model/deck_enrichment_projection.dart';
import 'package:discere/enrichment/queue/service/enrichment_progress_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// A deck whose species work has all reached a terminal outcome, so nothing
/// about it is pending.
///
/// Note this cannot be `DeckEnrichmentProjection.empty`: that has
/// `speciesCount == 0`, and `imageStagesComplete` requires at least one
/// species, so an empty projection counts as *not* terminal — which is what
/// makes it the right fallback for "no work known yet".
DeckWorkSnapshot _finishedDeck(String deckId) => DeckWorkSnapshot(
  deckId: deckId,
  coverJob: null,
  projection: DeckEnrichmentProjection(
    deckId: deckId,
    speciesCount: 1,
    imageCompleteSpeciesCount: 1,
    imageDoneSpeciesCount: 1,
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
    earliestRetryAt: null,
    staleBaseSpeciesCount: 0,
  ),
);

void main() {
  test('an empty batch is idle', () {
    final status = deriveEnrichmentStatus(const []);
    expect(status.hasPendingWork, isFalse);
    expect(status.activeDeckCount, 0);
  });

  test('a deck with no work recorded yet counts as pending', () {
    // The empty projection is the fallback for "nothing known yet", so it
    // must not read as finished — work may simply not be written.
    final status = deriveEnrichmentStatus([
      DeckWorkSnapshot(
        deckId: 'a',
        coverJob: null,
        projection: DeckEnrichmentProjection.empty('a'),
      ),
    ]);
    expect(status.hasPendingWork, isTrue);
  });

  test('decks with nothing pending report idle, not "pending with zero"', () {
    final status = deriveEnrichmentStatus([_finishedDeck('a'), _finishedDeck('b')]);
    expect(status.hasPendingWork, isFalse);
  });

  test('an active cooldown is dropped when nothing is pending', () {
    // The caller says a cooldown is active; the derivation still reports
    // idle, because there is no work for it to be holding up.
    final status = deriveEnrichmentStatus(
      [_finishedDeck('a')],
      hasActiveHostCooldown: true,
    );
    expect(status.hasActiveHostCooldown, isFalse);
  });

  test('background messaging is dropped when nothing is pending too', () {
    final status = deriveEnrichmentStatus(
      [_finishedDeck('a')],
      preferBackgroundMessaging: true,
    );
    expect(status.preferBackgroundMessaging, isFalse);
  });
}
