/// Providers recognized as the `provider` column in
/// `entity_external_ids`/`external_identifier_cache` (see
/// `ExternalIdRepository`/`ExternalIdCacheRepository`).
///
/// Enum member names are persisted as-is (via `.name`) — matches the
/// lowercase provider strings already stored by the ETL and at runtime, so
/// introducing this enum required no data migration.
enum ExternalIdProvider { inaturalist, wikipedia }
