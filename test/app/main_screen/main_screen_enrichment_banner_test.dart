/// The banner's visibility rule decides when the global "working in the
/// background" strip appears at all. It was a condition inside a Selector
/// callback on the main screen until the banner became its own widget.
library;

import 'package:discere/app/main_screen/widgets/main_screen_enrichment_banner.dart';
import 'package:discere/enrichment/queue/model/inat_enrichment_status.dart';
import 'package:flutter_test/flutter_test.dart';

INatEnrichmentStatus _status({
  required bool hasPendingWork,
  bool hasActiveHostCooldown = false,
  int readyDeckCount = 0,
  int activeDeckCount = 0,
}) => INatEnrichmentStatus(
  isRunning: hasPendingWork,
  hasPendingWork: hasPendingWork,
  hasActiveWork: hasPendingWork,
  hasActiveHostCooldown: hasActiveHostCooldown,
  phase: hasPendingWork
      ? INatEnrichmentPhase.base
      : INatEnrichmentPhase.idle,
  completed: 0,
  total: 0,
  readyDeckCount: readyDeckCount,
  activeDeckCount: activeDeckCount,
);

void main() {
  test('stays hidden when there is no pending work', () {
    expect(
      MainScreenEnrichmentBanner.shouldShow(
        _status(hasPendingWork: false),
      ),
      isFalse,
    );
  });

  test('shows while some deck still has no image', () {
    expect(
      MainScreenEnrichmentBanner.shouldShow(
        _status(hasPendingWork: true, readyDeckCount: 1, activeDeckCount: 3),
      ),
      isTrue,
    );
  });

  test('hides once every active deck is ready — the deck cards say the rest', () {
    expect(
      MainScreenEnrichmentBanner.shouldShow(
        _status(hasPendingWork: true, readyDeckCount: 3, activeDeckCount: 3),
      ),
      isFalse,
    );
  });

  test('a host cooldown overrides that: no deck card explains a stall', () {
    expect(
      MainScreenEnrichmentBanner.shouldShow(
        _status(
          hasPendingWork: true,
          hasActiveHostCooldown: true,
          readyDeckCount: 3,
          activeDeckCount: 3,
        ),
      ),
      isTrue,
    );
  });
}
