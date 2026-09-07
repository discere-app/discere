/// The unit of species-level enrichment work: one row per
/// `(species_id, capability)` in `enrichment_species_capability_state`,
/// claimed and driven to a terminal state by `BaseWorker`/`INatWorker`.
///
/// Lives at slice level because both `pipeline/` (which persists and drains
/// the queue) and `queue/` (which reports on it) need the same vocabulary.
library;

enum EnrichmentCapability {
  /// Reference image from the bundled catalog. Seeded for every species.
  base('base'),

  /// First iNaturalist photo, sought only once `base` found nothing.
  inatPrimary('inatPrimary'),

  /// Vernacular names for the species itself, seeded on consent.
  speciesCommonNames('speciesCommonNames'),

  /// Further iNaturalist photos once a species already has one.
  inatBackfill('inatBackfill');

  const EnrichmentCapability(this.wireName);

  /// The value stored in `enrichment_species_capability_state.capability`.
  ///
  /// Spelled out rather than derived from [name] so renaming a constant
  /// cannot silently change what is already in the database: the two are
  /// equal today, and only this field is allowed to keep them that way.
  final String wireName;

  static EnrichmentCapability fromWire(String wireName) => values.firstWhere(
    (capability) => capability.wireName == wireName,
    orElse: () =>
        throw ArgumentError.value(wireName, 'wireName', 'Unknown capability'),
  );
}
