/// Lifecycle of one queued piece of enrichment work.
///
/// Shared by all three producer-consumer tables — species capabilities,
/// taxonomy work and unresolved names — so a worker, a projection and the
/// diagnostics view all read the same vocabulary.
library;

enum EnrichmentWorkState {
  /// Claimable now.
  pending('pending'),

  /// Claimed by a worker. Reset to [pending] on startup if a process died
  /// mid-claim, since nothing else would ever pick it up again.
  running('running'),

  /// Failed a retryable attempt; claimable again once `next_attempt_at`
  /// passes.
  retryScheduled('retryScheduled'),

  /// Data was fetched and written.
  done('done'),

  /// The source has nothing for this species — a real answer, not a failure.
  noResult('noResult'),

  /// Gave up after exhausting the retry budget.
  permanentFailure('permanentFailure');

  const EnrichmentWorkState(this.wireName);

  /// The value stored in the `state` column. Spelled out rather than derived
  /// from [name] so renaming a constant cannot silently change persisted
  /// data.
  final String wireName;

  /// Whether this state is final: the work will not be attempted again
  /// without an explicit reset. The queue is terminal-state driven, so this
  /// is the single definition of "done with it" the whole slice shares.
  bool get isTerminal =>
      this == done || this == noResult || this == permanentFailure;

  static EnrichmentWorkState fromWire(String wireName) => values.firstWhere(
    (state) => state.wireName == wireName,
    orElse: () =>
        throw ArgumentError.value(wireName, 'wireName', 'Unknown work state'),
  );
}
