/// How often a species is reported within a specific region, as recorded by
/// FishBase/SealifeBase's per-country distribution data (`Abundance` field on
/// their `Country`/`Countrysub` tables, ETL'd into
/// `taxonomy_distribution_regions.abundance`).
///
/// Ordered from most to least frequently sighted. Free-text source values
/// that don't match a known category (author citations, stray numbers from
/// upstream data issues, etc.) fail to parse and are treated as unknown.
enum RegionAbundance {
  abundant,
  common,
  fairlyCommon,
  occasional,
  scarce;

  /// Parses a raw FishBase/SealifeBase abundance string, e.g.
  /// "common (usually seen)", "very common", "common but endangered",
  /// "scarce (very unlikely)". Matching is keyword-based and case-insensitive
  /// since the source data mixes bracketed explanations with plain words.
  static RegionAbundance? fromRaw(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    if (normalized.contains('abundant') || normalized.contains('very common')) {
      return RegionAbundance.abundant;
    }
    if (normalized.contains('fairly common')) {
      return RegionAbundance.fairlyCommon;
    }
    if (normalized.contains('common')) {
      return RegionAbundance.common;
    }
    if (normalized.contains('occasional')) {
      return RegionAbundance.occasional;
    }
    if (normalized.contains('scarce') || normalized.contains('rare')) {
      return RegionAbundance.scarce;
    }
    return null;
  }

  /// Ordered from most to least frequently sighted, for ranking/sorting.
  static const List<RegionAbundance> tiers = [
    RegionAbundance.abundant,
    RegionAbundance.common,
    RegionAbundance.fairlyCommon,
    RegionAbundance.occasional,
    RegionAbundance.scarce,
  ];

  /// The most frequently-sighted tier parsed out of a set of raw abundance
  /// values (e.g. across every region a species is native to), or null if
  /// none of them parse (including when there are none at all).
  static RegionAbundance? best(Iterable<String> rawValues) {
    RegionAbundance? best;
    for (final raw in rawValues) {
      final parsed = fromRaw(raw);
      if (parsed == null) continue;
      if (best == null || tiers.indexOf(parsed) < tiers.indexOf(best)) {
        best = parsed;
      }
    }
    return best;
  }
}
