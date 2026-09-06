import 'package:discere/enrichment/model/enrichment_work_state.dart';

/// A single (label, state) -> count row from one of the producer-consumer
/// work queue tables. [label] is a capability wire name (`base`,
/// `inatPrimary`, `speciesCommonNames`, `inatBackfill`),
/// `taxonomyCommonNames`, or `unresolvedNames` — the three tables do not
/// share one label vocabulary, so it stays a plain string; [state] does, and
/// is typed.
///
/// [nextAttemptAt] is the earliest scheduled retry within this group, only
/// meaningful for [EnrichmentWorkState.retryScheduled] — the other states
/// never set `next_attempt_at`, so it is null there.
class EnrichmentWorkStateCount {
  final String label;
  final EnrichmentWorkState state;
  final int count;
  final DateTime? nextAttemptAt;

  const EnrichmentWorkStateCount({
    required this.label,
    required this.state,
    required this.count,
    this.nextAttemptAt,
  });
}
