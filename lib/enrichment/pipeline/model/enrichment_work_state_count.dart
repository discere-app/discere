/// A single (label, state) → count row from one of the producer-consumer
/// work queue tables — `label` is the capability name (`base`, `inatPrimary`,
/// `names`, `inatBackfill`), `taxonomyCommonNames`, or `unresolvedNames`.
class EnrichmentWorkStateCount {
  final String label;
  final String state;
  final int count;

  const EnrichmentWorkStateCount({
    required this.label,
    required this.state,
    required this.count,
  });
}
