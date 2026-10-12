import 'dart:async';

/// Runs the sections that rewrite which species the enrichment queue tracks
/// for a deck one at a time, in call order.
///
/// Scheduling a deck hands `assignSpeciesOwners` a snapshot of the deck's
/// species, and the ownership planner treats that snapshot as authoritative:
/// a species missing from it is dropped. A name the `INatWorker` resolves and
/// registers between the snapshot and that write would be dropped with it.
/// Holding both sections under one lock keeps the registration either wholly
/// before the snapshot or wholly after the write.
///
/// A section's error reaches its caller, and the lock is free again for the
/// next one either way.
class DeckMembershipLock {
  Future<void> _lastSection = Future.value();

  Future<T> run<T>(Future<T> Function() section) async {
    final previousSection = _lastSection;
    final released = Completer<void>();
    _lastSection = released.future;
    await previousSection;
    try {
      return await section();
    } finally {
      released.complete();
    }
  }
}
