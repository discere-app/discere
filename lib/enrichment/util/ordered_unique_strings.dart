/// Trims each value in [values], drops empties, and deduplicates while
/// preserving first-seen order. Shared by the enrichment job repository,
/// executor, service, and queue service — all of which normalize
/// deck/species/entity-key id lists the same way before persisting or
/// batching them.
List<String> orderedUniqueStrings(Iterable<String> values) {
  final ordered = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final normalized = value.trim();
    if (normalized.isEmpty || !seen.add(normalized)) {
      continue;
    }
    ordered.add(normalized);
  }
  return ordered;
}
