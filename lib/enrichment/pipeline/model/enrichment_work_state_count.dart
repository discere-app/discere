/// A single (label, state) → count row from one of the producer-consumer
/// work queue tables — `label` is the capability name (`base`, `inatPrimary`,
/// `names`, `inatBackfill`), `taxonomyCommonNames`, or `unresolvedNames`.
///
/// [nextAttemptAt] is the earliest scheduled retry within this group (only
/// meaningful for `state == 'retryScheduled'` — other states never set
/// `next_attempt_at`, so it's `null` there).
class EnrichmentWorkStateCount {
  final String label;
  final String state;
  final int count;
  final DateTime? nextAttemptAt;

  const EnrichmentWorkStateCount({
    required this.label,
    required this.state,
    required this.count,
    this.nextAttemptAt,
  });
}
